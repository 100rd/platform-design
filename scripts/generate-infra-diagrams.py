#!/usr/bin/env python3
"""Generate infrastructure diagrams from Terragrunt unit metadata.

Walks `terragrunt/<account>/<region>/<module>/terragrunt.hcl` files, extracts
the `terraform.source` path and any declared `dependency` blocks, and emits:

  1. A Mermaid graph per account: `docs/diagrams/<account>.mmd`.
  2. A Mermaid graph for the whole repo: `docs/diagrams/overall.mmd`.

Mermaid was chosen over Graphviz because:
  - GitHub renders Mermaid natively in Markdown.
  - No system binary dependency (the workflow is pure Python + a single
    tiny shellout to grep — no `dot` install required).
  - Diffs as text in PRs.

Run locally:
    python3 scripts/generate-infra-diagrams.py

Run from CI (issue #176):
    .github/workflows/generate-diagrams.yml
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parent.parent
TG_ROOT = REPO_ROOT / "terragrunt"
DIAGRAM_DIR = REPO_ROOT / "docs" / "diagrams"

# Match `terraform { source = "${get_repo_root()}/.../<name>" }` (single line)
SOURCE_RE = re.compile(
    r'source\s*=\s*"[^"]*?/modules/([a-zA-Z0-9_\-]+)"'
)
# Match `dependency "<name>" {` lines — block start.
DEPENDENCY_RE = re.compile(r'dependency\s+"([a-zA-Z0-9_\-]+)"\s*\{')


def find_unit_files() -> Iterable[Path]:
    """Yield every terragrunt.hcl that's a per-unit config (not a stack)."""
    for path in TG_ROOT.rglob("terragrunt.hcl"):
        # Skip stack files (terragrunt.stack.hcl) and the synthesised
        # *.stack.hcl files which wouldn't match this pattern anyway.
        if path.name == "terragrunt.hcl":
            yield path


def parse_unit(path: Path) -> tuple[str, list[str]]:
    """Return (module_source_name, [dependency_names]) for a unit file.

    Lines inside HCL comments are intentionally NOT stripped — the regexes
    are tight enough that comment matches are rare and harmless.
    """
    text = path.read_text(encoding="utf-8")
    source_match = SOURCE_RE.search(text)
    module = source_match.group(1) if source_match else "unknown"
    deps = sorted(set(DEPENDENCY_RE.findall(text)))
    return module, deps


def relative_path(path: Path) -> str:
    """Path under terragrunt/ as a slash-joined string."""
    return path.relative_to(TG_ROOT).parent.as_posix()


def split_account_region(rel: str) -> tuple[str, str]:
    """Split 'dev/eu-west-1/eks' -> ('dev', 'eu-west-1/eks').

    Cope with `_global/...` paths and account-only paths (e.g. `_org/account.hcl`
    won't yield a unit; we filter elsewhere).
    """
    parts = rel.split("/", 1)
    if len(parts) < 2:
        return parts[0], ""
    return parts[0], parts[1]


def mermaid_node_id(rel: str) -> str:
    """Stable Mermaid node ID — slashes -> double underscores."""
    # Mermaid IDs must be plain word chars; map non-word to `_`.
    return re.sub(r"[^A-Za-z0-9_]", "_", rel)


def render_mermaid(units: dict[str, tuple[str, list[str]]]) -> str:
    """Build a Mermaid graph from the parsed unit map.

    Edges represent declared `dependency` blocks. Nodes are labeled
    `<rel-path>\n(<module>)`. A subgraph per account groups related units.
    """
    lines: list[str] = ["```mermaid", "graph LR"]

    # Group by account
    by_account: dict[str, list[tuple[str, str, list[str]]]] = {}
    for rel, (module, deps) in units.items():
        account, _ = split_account_region(rel)
        by_account.setdefault(account, []).append((rel, module, deps))

    for account in sorted(by_account):
        lines.append(f'  subgraph {account}["{account}"]')
        for rel, module, _deps in sorted(by_account[account]):
            node = mermaid_node_id(rel)
            lines.append(f'    {node}["{rel}<br/>({module})"]')
        lines.append("  end")

    # Edges across all accounts (dependency lines)
    for rel, (_module, deps) in sorted(units.items()):
        node = mermaid_node_id(rel)
        for dep in deps:
            # `dep` is the dependency block name, not a relative path.
            # We don't resolve it to a sibling-unit path here (that would
            # require parsing `config_path`); we just emit a labelled edge
            # to a synthetic dep node so the graph remains useful.
            dep_node = f"{node}__dep__{mermaid_node_id(dep)}"
            lines.append(f"  {node} -->|depends on| {dep_node}({dep})")

    lines.append("```")
    return "\n".join(lines)


def main() -> int:
    if not TG_ROOT.is_dir():
        print(f"error: terragrunt root {TG_ROOT} not found", file=sys.stderr)
        return 1

    units: dict[str, tuple[str, list[str]]] = {}
    for path in find_unit_files():
        rel = relative_path(path)
        if rel == ".":
            # The repo's terragrunt root.hcl isn't a unit; skip.
            continue
        module, deps = parse_unit(path)
        units[rel] = (module, deps)

    if not units:
        print("warn: no terragrunt units found; nothing to render", file=sys.stderr)
        return 0

    DIAGRAM_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Per-account diagrams
    by_account: dict[str, dict[str, tuple[str, list[str]]]] = {}
    for rel, val in units.items():
        account, _ = split_account_region(rel)
        by_account.setdefault(account, {})[rel] = val

    for account, sub in sorted(by_account.items()):
        out = DIAGRAM_DIR / f"{account}.md"
        body = (
            f"# Infrastructure diagram — `{account}`\n\n"
            f"Auto-generated by `scripts/generate-infra-diagrams.py`. Do not edit\n"
            f"by hand — re-run the script (or merge a PR that touches a unit;\n"
            f"the `generate-diagrams.yml` workflow regenerates on push to main).\n\n"
            f"{render_mermaid(sub)}\n"
        )
        out.write_text(body, encoding="utf-8")
        print(f"wrote {out.relative_to(REPO_ROOT)}")

    # 2. Overall diagram
    overall = DIAGRAM_DIR / "overall.md"
    overall_body = (
        "# Infrastructure diagram — repo-wide\n\n"
        "Auto-generated by `scripts/generate-infra-diagrams.py`. Spans every\n"
        "Terragrunt unit across all accounts. For per-account detail see the\n"
        "sibling `<account>.md` files in this directory.\n\n"
        f"{render_mermaid(units)}\n"
    )
    overall.write_text(overall_body, encoding="utf-8")
    print(f"wrote {overall.relative_to(REPO_ROOT)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
