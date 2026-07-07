# Platform Specs — Conventions

These specs are a **portable reverse-engineering of this platform's design estate**: detailed
enough that a competent platform team can rebuild the same platform for a new client without
reading this repository. Every spec follows the rules below.

## Audience and purpose

- Audience: a senior platform/infra team building a **new instance** of this platform
  (different org, different accounts, possibly different cloud sub-choices).
- Purpose: capture *what to build*, *why it is built that way* (decision + trade-off), and
  *how to reproduce it* (blueprint-level detail), not to document this repo's history.

## Parameterization (portability)

Never hardcode client-specific identity. Use double-brace placeholders, defined once in
`SPEC-00-overview.md`:

| Placeholder | Meaning | Example value shape |
|---|---|---|
| `{{ORG}}` | organization / company slug | `acme` |
| `{{DOMAIN}}` | root DNS zone | `platform.example.com` |
| `{{MGMT_ACCOUNT_ID}}`, `{{PROD_ACCOUNT_ID}}`, … | AWS account IDs | `111111111111` |
| `{{PRIMARY_REGION}}` / `{{DR_REGION}}` | regions | `us-east-1` / `eu-west-1` |
| `{{VCS_ORG}}` | Git hosting org | `acme-platform` |
| `{{STATE_BUCKET}}` | Terraform state bucket | `{{ORG}}-tf-state-{{MGMT_ACCOUNT_ID}}` |

Add spec-local placeholders as needed; register any recurring one in SPEC-00.

## Sanitization (hard rule — this may be shared with clients)

- NO real AWS account IDs, ARNs with account IDs, real hostnames/domains, IPs (except
  RFC1918/documentation ranges), emails, tokens, or company-identifying names from this repo.
- Replace real values with placeholders; keep the *shape* (e.g. show a real-looking SCP JSON
  with `{{MGMT_ACCOUNT_ID}}`).
- Code snippets from the repo are encouraged but MUST be sanitized the same way.

## Per-spec structure (every SPEC-NN file)

1. **Scope & non-goals** — what this spec covers, one paragraph.
2. **Architecture** — components and their relationships; ASCII diagram where helpful.
3. **Decision record** — table: decision · rationale · trade-off accepted · source ADR
   (cite as `ADR-NNNN <title>` — ADR numbers refer to this estate's `docs/adrs/`).
4. **Implementation blueprint** — directory layout, key files, sanitized snippets of the
   load-bearing configuration (enough to re-create, not a full dump), ordering/dependencies
   (what must exist before what).
5. **Parameterization table** — every placeholder this spec consumes + sizing knobs
   (instance types, counts, CIDR ranges) with the default used here and guidance to resize.
6. **Best practices distilled** — numbered, each with the *why*; this is the client-facing
   value, be generous and specific.
7. **Known pitfalls** — what this estate learned to avoid (from ADRs, fix-commits, TODOs).
8. **Acceptance checklist** — verifiable statements ("`terragrunt run --all plan` clean from
   an empty account", "ArgoCD app-of-apps syncs with zero manual steps") a rebuild must pass.
9. **Dependencies on other specs** — explicit `SPEC-NN` cross-references.

## Style

- English only. Concrete over abstract: name the exact tools, versions (as pinned in this
  estate: cite `versions.hcl` / `.tool-versions` values), flags, file paths.
- "Maximally detailed" means: a reader should never have to guess a file's content shape —
  show it. But do not paste whole files where a 15-line excerpt + description carries the design.
- Each spec is self-contained: readable without the others except via explicit Dependencies.
- Present tense, imperative for instructions. No history narration ("we then decided…").

## File naming

`specs/SPEC-NN-<kebab-slug>.md`. NN is two digits; the index lives in `specs/SPEC-INDEX.md`;
the platform overview in `specs/SPEC-00-overview.md`.
