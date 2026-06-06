# ADR-0016: Tier 1 CI/CD hardening — dep scan, secrets, SAST, signing, manifest validation, smoke

- Status: **Accepted** — implemented. Extends ADR-0015. The signing /
  manifest-validation / smoke controls landed in PR #241; the remaining dep-scan
  and SAST composites are now wired in, so the full Tier-1 set is in-repo.
- platform-design status: **synced** — the complete Tier-1 set is present.
  Dependency scanning (`python-dep-scan` = pip-audit + OSV; `node-dep-scan` =
  npm audit + osv-scanner; gating on CRITICAL/HIGH with a `.audit-ignore`
  allowlist, wired via `reusable-dep-scan`), SAST (`sast-codeql` =
  CodeQL `security-and-quality`, SARIF → Code Scanning, advisory at the workflow
  level / merge-blocking via branch protection, wired via `reusable-sast`),
  image signing (`cosign-sign`, keyless, wired into `reusable-build-and-push`
  after push by digest + SBOM attestation), manifest validation
  (`manifest-validate` action + `reusable-manifest-validate` workflow +
  `conftest-opa.yml`), and post-deploy smoke (`argocd-wait-sync-and-smoke`) are
  all present. Secrets scanning runs via the standalone `secret-scan.yml`.
- Implemented by: PR #241 (Tier-1 composite actions + reusable workflows +
  cosign signing; consolidated CI/CD).
- Date: 2026-06-03
- Authors: platform-team, security
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

ADR-0015 delivers the baseline: lint/test → multi-arch build → Trivy image scan →
SBOM → ECR push → GitOps PR. That gets every microservice to *shippable*. Tier 1
takes them from shippable to **production-grade** by adding the six controls that
catch the next class of supply-chain and configuration risk:

1. Application-dependency vulnerabilities (Trivy image scan only covers
   OS/system libs).
2. Hard-coded secrets in source.
3. Static application security (SAST) findings.
4. Image provenance signing.
5. Helm/Kustomize manifest validation before ArgoCD touches them.
6. Post-deploy smoke verification.

## Decision

Add six atomic composite actions (matching ADR-0015's form factor) and wire them
additively into the existing reusable workflows, with **zero new long-lived
secrets** (signing uses keyless OIDC; SARIF uploads use the built-in
`GITHUB_TOKEN`). Tool choices:

- **Dependency scan:** `pip-audit` (Python); `npm audit` + `osv-scanner` (Node).
  Gate on HIGH/CRITICAL; per-repo `.audit-ignore` allow-list.
- **Secrets scan:** `gitleaks`, SARIF to GitHub Security; fail on any finding.
- **SAST:** CodeQL (`security-and-quality`), SARIF to Code Scanning;
  merge-blocking left to branch protection.
- **Image signing:** `cosign` keyless via GitHub OIDC (Fulcio + Rekor); sign by
  **digest**, attach the SBOM as a signed attestation.
- **Manifest validation:** `helm lint` → `kubeconform -strict` → `conftest`
  (OPA/Rego) — a reusable workflow callable from the GitOps repo's CI.
- **Post-deploy smoke:** `argocd app wait --health --sync` then an HTTP probe;
  opt-in via an optional `smoke_url` input.

A reviewer can check conformance by confirming the full-release workflow runs
`secrets-scan` and `sast-codeql` as upstream gates feeding `build`, that
`cosign-sign` runs after push (by digest), and that GitOps manifest changes pass
`reusable-manifest-validate`.

## Alternatives considered

### Alternative A: Stop at the ADR-0015 baseline
Ship only image scanning + SBOM.
Rejected because: Trivy image scan covers OS libs only — application-dependency
CVEs, leaked secrets, SAST findings, provenance, and manifest defects all go
uncaught. That is "shippable", not "production-grade".

### Alternative B: KMS-backed signing keys instead of keyless cosign
Sign images with a managed KMS key.
Rejected because: KMS key sprawl + rotation burden + another IAM scope. Keyless
cosign binds the signature to a specific repo+workflow OIDC identity and the
public transparency log is an **audit advantage**, not a leak (repo names are not
secrets).

### Alternative C: semgrep instead of CodeQL for SAST
Use semgrep's free ruleset.
Rejected as the default because: CodeQL is natively integrated (SARIF → Security
tab) and the org already has Advanced Security. semgrep remains a fallback if
CodeQL minutes become a problem.

## Consequences

### Positive
- Catches app-dependency CVEs, leaked secrets, SAST findings, unsigned images, and
  bad manifests before they reach production.
- No new long-lived secrets — keyless signing + `GITHUB_TOKEN` SARIF uploads.
- Unified findings surface (Trivy + CodeQL + gitleaks all in GitHub Security).
- Manifest validation runs in the GitOps repo's CI, so bad values files are caught
  before ArgoCD (ADR-0006) syncs them.

### Negative
- ~4–7 min added per build on top of the ADR-0015 baseline (SAST is the long
  pole). Acceptable for production-grade pipelines; SAST can move to a scheduled
  scan if minutes blow up at scale.
- More moving parts (six new actions + two new reusable workflows).

### Risks
- `.audit-ignore` becoming a dumping ground. Mitigated by requiring an expiry-date
  comment per entry and a quarterly review.
- gitleaks false positives blocking PRs. Mitigated by a repo-local `.gitleaks.toml`
  allow-list and finding-level dismissal in Code Scanning.
- conftest policies too strict. Mitigated by shipping them **advisory** in v1
  (`fail-on-policy-violations: false`), promoted to a gate once manifests
  stabilise.
- Sigstore Fulcio/Rekor outage blocking releases. Mitigated by an `advisory` input
  that makes signing best-effort during incidents.

## Implementation notes

- Composite actions: `python-dep-scan`, `node-dep-scan`, `secrets-scan`,
  `sast-codeql`, `cosign-sign`, `manifest-validate`, `argocd-wait-sync-and-smoke`.
- Reusable workflows: `reusable-secrets-scan`, `reusable-manifest-validate`
  (callable from the GitOps repo); standalone in-repo `secrets-scan` +
  `smoke-tier1`.
- Gating order in `reusable-full-release`: `secrets-scan` + `sast-codeql` run
  parallel to language CI, both feeding `build`; dep-scan layered inside the
  language CI workflows; `cosign-sign` inside build-and-push after push; smoke
  inside deploy.
- All new third-party `uses:` SHA-pinned with the Renovate-comment convention
  from ADR-0015.

## References

- cosign / Sigstore keyless: <https://docs.sigstore.dev/cosign/signing/overview/>
- kubeconform: <https://github.com/yannh/kubeconform>; conftest:
  <https://www.conftest.dev/>
- Ported from `infra` CI/CD ADR-002 (Tier 1 hardening)
- Related: ADR-0015 (reusable CI pipelines), ADR-0006 (ArgoCD), ADR-0014 (Argo
  Rollouts canary)

---
*Ported from infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Signing / manifest-validation / smoke implemented in
platform-design by PR #241; the dep-scan (`python-dep-scan` / `node-dep-scan`)
and SAST (`sast-codeql`) composites + their `reusable-dep-scan` / `reusable-sast`
wiring complete the Tier-1 set. Status: Accepted — implemented; fully synced.*
