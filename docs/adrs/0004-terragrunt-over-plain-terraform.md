# ADR-0004: Terragrunt over plain Terraform for multi-account orchestration

- Status: **Accepted** — decision is *adopted (live in source estate)*
- platform-design status: **synced** — Terragrunt is the orchestration layer
  (`terragrunt/root.hcl`, `terragrunt/_envcommon/`, `catalog/units/` +
  `catalog/stacks/`); modules under `terraform/modules/`.
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

The platform spans many AWS accounts (per ADR-0001's OU split: production,
non-production, deployments, sandbox, plus security/network/shared) across four
EU regions. Managing that estate needs a strategy for DRY configuration,
consistent provider/backend wiring, and multi-account orchestration. This repo
already standardised on Terraform-only state bootstrap (ADR-0002); the question
is what orchestration layer sits on top. We evaluated:

1. **Plain Terraform** with workspaces.
2. **Terragrunt** as a thin Terraform wrapper.
3. **CDK for Terraform (CDKTF)** in TypeScript/Python.

## Decision

Use **Terragrunt** as the Terraform orchestration layer. A reviewer can check
conformance by confirming new infrastructure is expressed as a `terragrunt.hcl`
unit composing an `_envcommon/` definition, not a standalone root module with a
hand-written `backend` block.

## Alternatives considered

### Alternative A: Plain Terraform with workspaces
Use Terraform workspaces to separate accounts/environments.
Rejected because: workspaces share one backend/state-key namespace and one
provider block, which does not map cleanly onto an account-per-isolation model.
Backend and `default_tags` config would be copy-pasted per module, drifting over
time.

### Alternative B: CDKTF
Generate Terraform from a general-purpose language.
Rejected because: introduces a new language and a code-generation step the team
does not currently run. Existing expertise is Terraform/HCL; the marginal power
of a real language does not pay for the onboarding and debugging cost here.

### Alternative C: Status quo
Hand-wired Terraform root modules per account.
Rejected because: that is the duplication problem Terragrunt's `_envcommon/`
pattern exists to eliminate; it does not scale to the account/region count above.

## Consequences

### Positive
- `_envcommon/` patterns eliminate duplication: one module definition serves
  dev/stage/prod via account-specific `account.hcl` / `region.hcl` inputs.
- Automatic S3 backend config via `remote_state` — no per-module backend blocks
  (and consistent with the ADR-0002 bootstrap'd backend).
- `generate "provider"` produces consistent provider configs with `default_tags`
  across every deployment (drives the cost-allocation tags ADR-0001 relies on).
- `dependency` blocks give cross-module references without hardcoded outputs.
- `terragrunt run-all` plans/applies across accounts with dependency ordering.
- Adds a thin HCL layer rather than a new language.

### Negative
- Learning curve for Terragrunt-specific HCL patterns.
- Debugging is harder (generated files, nested configs).
- CI must install both Terraform and Terragrunt.

### Risks
- Terragrunt version upgrades can introduce breaking changes. Mitigated by
  pinning the Terragrunt version in CI and in the `.mise`/tool-version manifest.
- Some Terraform tooling (e.g. Terraform Cloud) has limited Terragrunt support.
  Accepted — the platform does not depend on those integrations.

## Implementation notes

- Module bodies live under `terraform/modules/`; orchestration under
  `_envcommon/` + `<account>/<region>/<unit>/terragrunt.hcl`.
- Backend block is generated, pointing at the ADR-0002 bootstrap S3 bucket.
- CI installs pinned Terraform + Terragrunt and runs `terragrunt run-all plan`.

## References

- Terragrunt docs: <https://terragrunt.gruntwork.io/>
- Ported from `infra` ADR-002 (Terragrunt over plain Terraform)
- Related: ADR-0001 (OU split), ADR-0002 (Terraform-only state backend)

---
*Ported from infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live).*
