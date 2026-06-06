# ADR-0022: CI supply-chain runtime hardening — Actions SAST + runner egress monitoring

- Status: **Proposed** — research-backed; decision to ratify, partly spiked.
- platform-design status: **pending** — no Actions-workflow linting or runner
  runtime monitoring is wired in; spike PR #251 prototypes part of it.
- Implemented by: spike PR #251 (partial — prototypes the zizmor / Harden-Runner
  wiring).
- Date: 2026-06-06
- Authors: platform-team, security
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)
- Extends: ADR-0016 (Tier-1 supply-chain hardening).

## Context

CI today is **build-time / static only**: cosign signing, syft SBOMs, trivy image
scanning, CodeQL SAST (ADR-0015 / ADR-0016). Two gaps remain, and they are exactly
the gaps behind the **2025 `tj-actions/changed-files` compromise**:

1. **We never lint our own GitHub Actions workflows.** No SAST runs over the
   `.github/workflows` YAML themselves — so an over-privileged `GITHUB_TOKEN`, an
   unpinned/`@main` action, a script-injection sink (`${{ github.event.* }}` into a
   `run:` block), or a dangerous `pull_request_target` pattern ships unflagged.
2. **No runtime egress visibility on runners.** A compromised dependency or action
   can exfiltrate secrets or tamper with the build, and we would have **no record
   of the runner's network/file/process activity** — the static scans all run
   before the malicious step executes.

The `tj-actions` incident was precisely this class: a compromised action exfiltrated
secrets at *runtime* from runners that had no egress monitoring, in repos whose
workflows were never SAST-linted.

## Decision

Add two **runtime/CI-self** controls, extending ADR-0016's Tier-1 set:

- **zizmor** — **GitHub Actions SAST**. Lint every workflow for the known
  failure modes (excess `GITHUB_TOKEN` permissions, unpinned actions, template-
  injection, risky `pull_request_target`), emitting **SARIF** to GitHub Code
  Scanning (same surface as CodeQL from ADR-0016).
- **StepSecurity Harden-Runner** — **runtime egress / file / process monitoring**
  on the runner. Start in **audit** mode (record outbound connections, file writes,
  spawned processes to build the allow-list), then promote to **block** (deny
  egress outside the allow-list) once the baseline is established.

As **follow-ons** (named, not yet decided in detail):

- **GitHub Artifact Attestations** (SLSA **L2/L3** build provenance).
- **Immutable Releases** (tags that cannot be moved after publish).
- **cosign 2.4 bundle verification** at deploy time.

A reviewer can check conformance by confirming every workflow is linted by zizmor
(SARIF in Code Scanning), that Harden-Runner runs on CI jobs (audit → block), and
that the follow-on attestation/immutable-release items are tracked.

## Alternatives considered

### Alternative A: Stay build-time-only (status quo / ADR-0016 as-is)
Keep static scans without Actions SAST or runtime monitoring.
Rejected because: that is exactly the `tj-actions` exposure — workflows go
un-linted and a runtime exfiltration leaves no trace. Static scans cannot see a
malicious step that runs *after* them.

### Alternative B: Actions SAST (zizmor) only, no runtime monitoring
Lint workflows but skip Harden-Runner.
Rejected because: SAST catches *static* workflow defects but not a compromised
*dependency/action* exfiltrating at runtime. Egress monitoring is the control that
would have caught `tj-actions`; the two are complementary.

### Alternative C: Runtime monitoring only, no Actions SAST
Add Harden-Runner but not zizmor.
Rejected because: detecting bad egress after the fact is weaker than preventing the
over-privileged / unpinned / injectable workflow from existing. Lint shifts the
defect left; monitoring is the runtime backstop.

## Consequences

### Positive
- Closes the `tj-actions`-class gap: workflows are SAST-linted and runner egress is
  monitored/blockable.
- Findings land on the existing GitHub Code Scanning surface (consistent with
  ADR-0016).
- Provenance strengthens toward SLSA L2/L3 via the attestation follow-ons.

### Negative
- Harden-Runner in block mode requires a maintained egress allow-list (mirrors of
  registries, package indexes, telemetry endpoints).
- zizmor will surface a backlog of existing workflow findings to triage.

### Risks
- Block mode breaking legitimate egress (a missed endpoint fails a build).
  Mitigated by **audit-first** to build the allow-list before blocking.
- zizmor false positives blocking PRs. Mitigated by SARIF dismissal + a repo-local
  config, advisory before merge-blocking.
- Follow-on scope creep (attestations/immutable releases). Mitigated by tracking
  them as explicit follow-ons, not bundling them into this ADR's gate.

## Implementation notes

- **zizmor:** run over `.github/workflows/**`, SARIF upload via `GITHUB_TOKEN`
  (no new secret), wired as a reusable workflow alongside ADR-0016's `sast-codeql`.
- **Harden-Runner:** add the `step-security/harden-runner` step to CI jobs;
  `audit` first, `egress-policy: block` once the allow-list is stable.
- **Follow-ons:** GitHub Artifact Attestations (SLSA L2/L3); Immutable Releases;
  cosign 2.4 bundle verification at deploy (extends ADR-0016 signing).
- **Spike PR #251** prototypes the zizmor + Harden-Runner wiring.

Effort: **L**.

## References

- zizmor (GitHub Actions SAST): <https://woodruffw.github.io/zizmor/>
- StepSecurity Harden-Runner: <https://docs.stepsecurity.io/harden-runner>
- GitHub Artifact Attestations / SLSA:
  <https://docs.github.com/actions/security-guides/using-artifact-attestations>
- Related: ADR-0016 (Tier-1 hardening — this ADR extends it), ADR-0015 (reusable CI
  pipelines)

---
*Research-backed — 2026 platform modernization; grounded in infra@572b54d /
argocd@c364c6c. Proposed: decision to ratify, not yet implemented in
platform-design; spike PR #251 prototypes part of it. Extends ADR-0016.*
