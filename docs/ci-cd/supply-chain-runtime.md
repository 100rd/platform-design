# CI supply-chain: workflow SAST + runtime egress monitoring

> **Provenance:** spike from the 2026-06 platform supply-chain research, applying
> the lesson of the **2025 `tj-actions/changed-files` compromise** (a popular
> third-party action was backdoored to dump CI secrets into build logs).
> Extends **ADR-0016** (Tier-1 supply-chain hardening). Audit-mode by default,
> so it is non-breaking on day one.

## The gap this closes

ADR-0016 / ADR-0015 gave platform-design a strong **static, build-time**
supply-chain posture:

| Layer | Control | What it covers |
|-------|---------|----------------|
| App code SAST | CodeQL (`sast-codeql`) | Vulnerabilities in *our* application source |
| Image scan | Trivy (`trivy-scan`) | OS / system-lib CVEs in built images |
| Dependency scan | pip-audit + osv / npm audit (`*-dep-scan`) | Application-dependency CVEs |
| Secrets | gitleaks (`secret-scan.yml`) | Hard-coded secrets in source |
| Provenance | cosign keyless + SBOM attest (`cosign-sign`) | Image signing by digest |

Two blind spots remained — and they are **exactly** the class behind the
tj-actions incident:

1. **Nothing lints our own GitHub Actions.** CodeQL lints app code; nothing ever
   inspected the workflows and composite actions themselves for unpinned actions,
   dangerous `pull_request_target` + checkout, template-injection sinks, or
   over-broad `GITHUB_TOKEN` permissions.
2. **Zero runtime egress visibility on runners.** Every control above is
   static/build-time. If a compromised or typo-squatted action exfiltrated
   secrets *at run time*, no control would see the outbound connection.

This note documents the two additions that close them.

## 1. zizmor — static analysis of our GitHub Actions

[`zizmor`](https://github.com/zizmorcore/zizmor) is a dedicated SAST tool for
GitHub Actions. The workflow lives at
[`.github/workflows/zizmor.yml`](../../.github/workflows/zizmor.yml) and runs on
any change under `.github/` (plus `workflow_dispatch`).

- **Scope:** the whole `.github/` tree — both `workflows/` and the `actions/`
  composites.
- **Output:** SARIF uploaded to **GitHub Code Scanning**, joining the existing
  Trivy / CodeQL / gitleaks findings surface.
- **Gating:** **advisory at the workflow level**, mirroring `reusable-sast.yml`
  (ADR-0016). With `advanced-security: true` zizmor uploads SARIF and does **not**
  fail the job on findings; the job only fails on an internal zizmor error.
  Merge-blocking is enforced by **branch protection on the `zizmor` Code Scanning
  check**, not by failing the job — so it can be adopted without breaking open
  PRs.
- **TODO (tracked in the workflow):** once findings are triaged to zero, add the
  branch-protection rule on `main` to make the check merge-blocking.

The action is **SHA-pinned with a version comment**
(`zizmorcore/zizmor-action@5f14fd08…  # v0.5.6`), per the ADR-0015 convention.

## 2. StepSecurity Harden-Runner — runtime egress monitoring

[`Harden-Runner`](https://github.com/step-security/harden-runner) installs an
eBPF agent on the runner that records every **outbound network connection, file
write, and spawned process** for a job. Wrapped as a composite action at
[`.github/actions/harden-runner`](../../.github/actions/harden-runner/action.yml)
and demonstrated as the **first step** of both jobs in
[`container-build.yml`](../../.github/workflows/container-build.yml).

> It **must be the first step** so the agent is in place before any other step
> (checkout, AWS login, buildx, cosign) runs.

### Audit first, block later

- **Audit (default, what we ship):** `egress-policy: audit` — observe only.
  Every connection is logged to the StepSecurity insights page linked in the job
  summary; **nothing is blocked**, so it cannot break a build. Run it across CI
  for a few weeks to learn the legitimate endpoint set (ECR, the GitHub API,
  Sigstore/Fulcio/Rekor for cosign, the buildx GHA cache, package registries).
- **Block (the goal):** flip to `egress-policy: block` and pass the learned
  endpoints via `allowed-endpoints`. Any connection outside the allowlist is then
  **denied** and surfaced as a job annotation — turning the runner into a deny-by-
  default network.

```yaml
- name: Harden runner
  uses: ./.github/actions/harden-runner
  with:
    egress-policy: block
    allowed-endpoints: >
      github.com:443
      api.github.com:443
      objects.githubusercontent.com:443
      *.ecr.eu-west-1.amazonaws.com:443
      fulcio.sigstore.dev:443
      rekor.sigstore.dev:443
```

The action is **SHA-pinned with a version comment**
(`step-security/harden-runner@9af89fc7…  # v2.19.4`).

### Rollout

1. **Now:** audit mode wired into `container-build.yml` — zero behaviour change.
2. **Next:** review the StepSecurity insights for a few weeks; collect the real
   egress baseline per job.
3. **Then:** add the harden-runner step (audit) to the remaining high-value jobs
   (`reusable-build-and-push.yml`, the Terragrunt apply/plan workflows).
4. **Finally:** flip the highest-trust jobs (build/push, signing) to
   `egress-policy: block` with the learned `allowed-endpoints`.

## Relationship to ADR-0016

This is a **strict extension** of ADR-0016, not a replacement: the static Tier-1
controls stay exactly as they are. zizmor adds the missing *Actions-SAST* layer;
Harden-Runner adds the missing *runtime* layer. Both ship **advisory / audit** so
adoption is non-breaking, with a documented path to enforcement.
