# ADR-0015: Reusable CI/CD pipelines for the platform organisation

- Status: **Proposed** — decision is a *design-target* (the reusable-pipeline
  platform is being rolled out; source estate has the seed `build-and-push`
  workflow live)
- Date: 2026-06-03
- Authors: platform-team, security
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

Workloads across the platform organisation are converging onto the shared EKS
clusters (Graviton, `eu-west-1`). Each repository today carries its own ad-hoc
GitHub Actions YAML — variable in quality, hard to audit, and prone to drift on
patch-version pinning, scan thresholds, and OIDC role wiring. A central, versioned
set of building blocks lets us:

- Roll out security-policy changes (image-scan threshold, SBOM format, base-image
  scan) once and have all callers pick them up via a `@v1` floating tag.
- Eliminate per-repo IAM role sprawl by using **one** OIDC-federated role for ECR
  push, trust-scoped to the whole org.
- Standardise the GitOps deploy contract (PR into the GitOps repo) so the
  platform team has a single integration point with ArgoCD (ADR-0006).

The platform already has a proven OIDC + ECR + Trivy build workflow as the seed;
this ADR formalises and generalises it.

## Decision

Ship a **two-layer reuse model**: atomic **composite actions** and full
**reusable workflows** (`workflow_call`). Standardise on **one central
OIDC-federated IAM role** for ECR push (org-scoped trust, ECR resource policy
scoped to the platform's repository namespace), **multi-arch builds**
(`linux/arm64,linux/amd64` — Graviton default), a **GitOps deploy contract** that
opens a PR into the GitOps repo (auto-merge on non-prod, manual review on prod),
**SHA-pinned** third-party actions, and **semver** releases with a floating major
tag.

A reviewer can check conformance by confirming caller repos consume the reusable
workflows via `uses: <org>/infra/.github/workflows/reusable-*.yml@v1` rather than
hand-rolled pipelines, and that third-party `uses:` are SHA-pinned.

## Alternatives considered

### Alternative A: Per-repo bespoke pipelines (status quo)
Each repo keeps its own GitHub Actions YAML.
Rejected because: that is exactly the drift/audit problem — policy changes require
N copy-paste edits, and per-repo OIDC roles proliferate.

### Alternative B: Composite actions only (no reusable workflows)
Ship atomic building blocks but let each repo assemble its own pipeline.
Rejected because: it standardises steps but not the *pipeline shape*, so the
deploy contract and gating order still drift. The two-layer model lets callers mix
(use a reusable workflow wholesale, or compose atomic actions for custom paths).

### Alternative C: Reusable workflows only (no composite actions)
Ship only `workflow_call` pipelines.
Rejected because: repos that need one atomic step (just ECR login, or just a tag
bump) inside a custom workflow would have no building block to reuse. Both layers
are needed.

## Consequences

### Positive
- Single place to change security policy; callers float on `@v1`.
- One OIDC role for ECR push (org-scoped trust, namespace-scoped ECR policy; no
  IAM, no STS, no cross-account).
- Multi-arch images built once (`docker/build-push-action` + QEMU + gha cache).
- Single GitOps integration point: a deploy action opens a PR bumping image
  tag/digest in the GitOps repo (auto-merge on dev/stage, manual on prod).
- SHA-pinned, Renovate/Dependabot-maintained third-party actions.

### Negative
- The infra repo becomes a shared dependency with strict semver discipline —
  a breaking change in `@v1` would break all callers (mitigated below).
- arm64 QEMU emulation is ~2–3× slower than native; accepted for v1 since gha
  cache eliminates warm rebuilds and build counts are low.

### Risks
- **Wildcard org trust** on the OIDC role — any org repo can assume it. Mitigated
  by scoping the ECR resource policy to the platform's repository namespace only
  (no IAM/STS/cross-account), mandatory branch protection on callers, and a
  follow-up CloudTrail alarm on unusual ECR push patterns.
- **Compromised third-party action** could push a malicious image. Mitigated by
  SHA-pinning + Dependabot review, plus Trivy failing CRITICAL/HIGH before push
  and an SBOM attached to every image (signing is ADR-0016).
- **Breaking change in the `@v1` floating tag** breaks all callers. Mitigated by
  strict semver: breaking changes ship as `v2`; a smoke workflow gates the `v1`
  advance.
- **GitOps bot-token leak.** Mitigated by a fine-scoped token (`contents:write` on
  the GitOps repo only), rotated quarterly, never logged.

## Implementation notes

- Composite actions: `aws-oidc-login`, `ecr-login`, `docker-build-multiarch`,
  `trivy-scan`, `syft-sbom`, `argocd-tag-bump`, `python-ci`, `node-ci`.
- Reusable workflows: `reusable-build-and-push`, `reusable-python-ci`,
  `reusable-node-ci`, `reusable-deploy-via-argocd`, `reusable-full-release`, plus
  a path-filtered smoke workflow.
- Terraform: `modules/github-oidc-central-ecr` (central role + ECR push policy,
  reusing the existing OIDC provider via a `data` lookup) + Terragrunt unit
  (ADR-0004).
- `values_path` for the GitOps deploy is a **required** input — no implicit layout
  convention.
- Tier 1 supply-chain hardening (dep scan, secrets, SAST, signing, manifest
  validation, smoke) layers on top — see ADR-0016.

## References

- GitHub reusable workflows: <https://docs.github.com/actions/using-workflows/reusing-workflows>
- GitHub OIDC → AWS: <https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services>
- Ported from `qbiq-ai/infra` CI/CD ADR-001 (reusable pipelines)
- Related: ADR-0004 (Terragrunt), ADR-0006 (ArgoCD), ADR-0016 (Tier 1 hardening)

---
*Ported from qbiq-ai/infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: Proposed / rolling
out (design-target); the seed OIDC+ECR+Trivy build workflow is live.*
