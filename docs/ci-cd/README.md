# CI/CD: platform-workflows consolidation model

> **Provenance:** mirrors `platform-workflows@3bb35df` (2026-06 sync).
> This document and the accompanying `.github/actions/` composite actions and
> `.github/workflows/reusable-*.yml` reusable workflows reflect the real-estate
> consolidation into a single shared CI/CD repository. This is a **mock** —
> a faithful, representative port, not a 1:1 copy of every upstream action.

## Why this exists

Historically every repo carried its own self-contained CI/CD. platform-design
still embeds **22 self-contained in-repo workflows** (Terragrunt plan/apply,
container build, k8s/helm validation, security scans, etc.) with **no image
signing, no SBOM, no reusable pipeline pattern**.

In the real estate, the Tier-1 hardening building blocks were **consolidated
out of `infra` into a shared `platform-workflows` repository** so
every service repo composes the same audited actions instead of copy-pasting
CI. This PR reflects that model inside platform-design:

- **Composite actions** under `.github/actions/` — the reusable Tier-1 steps.
- **Reusable `workflow_call` workflows** under `.github/workflows/reusable-*.yml`
  — the pipelines that compose those actions.
- **Signing wired in**: `container-build.yml` and `reusable-build-and-push.yml`
  now sign pushed images and attest SBOMs. The upstream
  `reusable-build-and-push` notably **builds, scans and pushes but never
  signs** — this port closes that gap.

In real consumer repos the reusables are referenced as
`uses: platform-workflows/.github/workflows/<wf>.yml@<ref>`. In this
mock they live in-repo and are referenced via local `./.github/...` paths.

## Tier-1 composite actions (`.github/actions/`)

The full Tier-1 set is now in-repo. The **dependency-scan and SAST composites
(`python-dep-scan`, `node-dep-scan`, `sast-codeql`) were the remaining
ADR-0016 design-target** and are added here — completing the set whose signing /
SBOM / manifest-validation / smoke half landed in PR #241.

| Action | Purpose | Gate |
|--------|---------|------|
| `python-dep-scan` | Scan Python deps for CVEs with `pip-audit` (PyPI Advisory DB + OSV). Post-filters the JSON report on `severity-threshold`, honours a `.audit-ignore` allowlist, emits SARIF. Catches application-dependency CVEs that the Trivy **image** scan (OS/system libs only) misses. | **Gating** — fails on `CRITICAL,HIGH` (set `exit-code: 0` for advisory). |
| `node-dep-scan` | Scan Node deps for CVEs with `npm audit --audit-level=high` + `osv-scanner`. Honours `.audit-ignore`, uploads osv-scanner SARIF. | **Gating** — fails on `high`+ (set `exit-code: 0` for advisory). |
| `sast-codeql` | GitHub CodeQL static analysis for one language (`security-and-quality` suite). SARIF → Code Scanning. Wraps `github/codeql-action`. | **Advisory** — findings surface in Code Scanning; merge-blocking is enforced by branch protection on that check, not by the job. |
| `cosign-sign` | Keyless image signing via Sigstore + GitHub OIDC, **by digest** (immutable). Optionally attaches the SBOM as a signed cosign attestation (SPDX/CycloneDX). `advisory: true` downgrades sign failures to warnings during Sigstore incidents. | Gating (unless `advisory`). |
| `syft-sbom` | Generate an SBOM (default `spdx-json`) for an image with Syft and upload it as a workflow artifact. | n/a |
| `trivy-scan` | Scan an image with Trivy; the table scan is the **gate** (fails on `CRITICAL,HIGH`), the SARIF upload is best-effort reporting (tolerates repos without Advanced Security). | Gating. |
| `manifest-validate` | `helm lint --strict` + `helm template \| kubeconform -strict` + `conftest` against OPA/Rego policies. Catches bad apiVersions, missing values, and policy violations before ArgoCD syncs. | Gating (conftest advisory in v1). |
| `argocd-tag-bump` | Open a PR in the argocd config repo (`100rd/argocd`) bumping `image.tag` + `image.digest` in a values file. Labels non-prod PRs `auto-merge`. | n/a |
| `argocd-wait-sync-and-smoke` | Post-deploy gate: wait for the ArgoCD app to reach Synced + Healthy, then HTTP-probe an endpoint for an expected 2xx. | Gating. |

## Reusable pipelines (`.github/workflows/`)

### `reusable-build-and-push.yml`
`checkout → AWS OIDC + ECR login → buildx (load) → trivy-scan → syft-sbom →
push → cosign-sign (+ SBOM attest)`.

Outputs `image_uri`, `image_digest`, `image_tag`. The **sign-by-digest** step is
the gap closure relative to upstream: it signs the exact pushed digest and
attests the SBOM, all keyless via the job's GitHub OIDC identity. Set
`push: false` for build-only smoke runs (skips ECR + signing).

### `reusable-deploy-via-argocd.yml`
Calls `argocd-tag-bump` to open an image-bump PR in `100rd/argocd`. Auto-merge
defaults to **true for non-prod, false for prod** (human-gated prod), overridable
via `auto_merge_override`.

### `reusable-manifest-validate.yml`
Wraps `manifest-validate`. Intended to run on the tag-bump PRs created by
`reusable-deploy-via-argocd.yml`, and usable directly from any chart-owning repo.

### `reusable-dep-scan.yml`
Wraps `python-dep-scan` / `node-dep-scan` (selected by the `language` input).
**Gating** by default (fails on `CRITICAL,HIGH` / `high`+); `advisory: true`
flips it to reporting-only. Honours a per-repo `.audit-ignore` allowlist and
uploads SARIF to GitHub Security. Run it as an upstream gate alongside language
lint/test, before `reusable-build-and-push`.

### `reusable-sast.yml`
Wraps `sast-codeql` over a matrix of `languages` (CodeQL `security-and-quality`).
**Advisory** at the workflow level — SARIF flows to Code Scanning and
merge-blocking is enforced by branch protection on that check, not by failing the
job (`continue-on-error` unless `fail_on_error: true`). SAST is the long pole;
per ADR-0016 it can move to a scheduled scan if CI minutes blow up.

### `reusable-pipeline-demo.yml`
Manual (`workflow_dispatch`) thin caller wiring `reusable-build-and-push` →
`reusable-deploy-via-argocd` end to end.

## GitOps deploy model

Deploys are **PR-based**, never `kubectl apply` from CI:

1. Build/sign produces an immutable `tag` + `digest`.
2. `argocd-tag-bump` opens a PR in `100rd/argocd` writing both into the env values file.
3. **Non-prod** PRs are `auto-merge`-labelled and merge once checks pass;
   **prod** PRs are left for human review.
4. ArgoCD syncs the merged change; `argocd-wait-sync-and-smoke` confirms
   Synced + Healthy and smoke-probes the endpoint.

## Expected org-level secrets & variables

Configure at the **organization** (or repo) level; the workflows read them as
`secrets.*` / `vars.*`.

| Name | Type | Used by | Purpose |
|------|------|---------|---------|
| `ECR_PUSH_ROLE_ARN` | var | `reusable-build-and-push`, `container-build` (as `AWS_ROLE_ARN`) | IAM role assumed via GitHub OIDC for ECR push. |
| `ARGOCD_BOT_TOKEN` | secret | `reusable-deploy-via-argocd`, `argocd-tag-bump` | Token with `contents:write` + `pull-requests:write` on `100rd/argocd`. |
| `GITOPS_APP_ID` / `GITOPS_APP_KEY` | var / secret | argocd-bump (GitHub App alternative to `ARGOCD_BOT_TOKEN`) | GitHub App credentials minting short-lived bump tokens. |
| `ARGOCD_AUTH_TOKEN` | secret | `argocd-wait-sync-and-smoke` | Read-only, project-scoped ArgoCD API token. |
| `ARGOCD_SERVER` | var | `argocd-wait-sync-and-smoke` | ArgoCD server hostname (no scheme). |

> No long-lived AWS keys: image push uses **GitHub OIDC → IAM role assumption**.
> Image signing is **keyless** — identity is bound to the workflow, no private
> keys to store or rotate. SBOM attestations are signed the same way.

## Required job permissions

```yaml
permissions:
  id-token: write        # OIDC: AWS role assumption + cosign keyless
  contents: read
  security-events: write # Trivy SARIF upload to the Security tab
```

## Relationship to existing platform-design workflows

The 22 existing in-repo workflows are **preserved unchanged** except
`container-build.yml`, which gains SBOM generation and a `cosign-sign` step on
push (closing the unsigned-image gap) while keeping its detect-changes matrix,
Trivy table+SARIF scan, and ECR push intact. The OPA policy machinery this
repo already has (`conftest-opa.yml`, `tests/opa/`) is what `manifest-validate`
plugs into via its `policies-path` input.
