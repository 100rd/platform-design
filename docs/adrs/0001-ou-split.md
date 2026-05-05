# ADR-0001: OU split — Production / Non-Production / Deployments / Suspended / Sandbox

- Status: **Accepted**
- Date: 2026-05-04
- Authors: platform-team
- Related issues: #157, #158
- Supersedes: (none)
- Superseded by: (none)

## Context

The platform-design repo originally created five Organizational Units:
`Security`, `Infrastructure`, `Workloads/NonProd`, `Workloads/Prod`, plus a
hard-coded `Suspended` OU inside the organisation Terraform module. This was
adequate for the initial rollout but missed two pieces called out by AWS
Control Tower best practice and the source-repo `qbiq-ai/infra` lineage:

1. A `Deployments` OU to isolate AFT (Account Factory for Terraform) and
   CI/CD automation accounts from the workload data plane.
2. A `Sandbox` OU for developer experimentation with a different SCP profile
   than NonProd (region-restricted, hard spend caps, no shared services).

Issue #158 asks for the canonical 5-OU split: `Production`, `Non-Production`,
`Deployments`, `Suspended`, `Sandbox`.

## Decision

Adopt the canonical 5-OU split, mapped onto the existing repo OU naming as
follows:

| Canonical name | This repo |
|---|---|
| Production | `Prod` (nested under `Workloads`) |
| Non-Production | `NonProd` (nested under `Workloads`) |
| Deployments | `Deployments` (NEW, top-level) |
| Suspended | `Suspended` (already exists, top-level) |
| Sandbox | `Sandbox` (NEW, top-level) |

Keep the existing functional OUs (`Security`, `Infrastructure`, `Workloads`)
in place. They are additional axis-of-organisation atop the canonical 5 and
do not conflict.

`Deployments` is **not** included in `workload_ou_names`, so the
`DenyRootAccount` SCP does not attach. `Sandbox` **is** included.

## Alternatives considered

### Alternative A: Full rename to canonical names
Rename `Prod` → `Production` and `NonProd` → `Non-Production` to match the
canonical names exactly.

Rejected because: this would force a Terraform state migration (`terraform
state mv`) on the SCP attachments and the SSO permission-set assignments
already merged in PRs #191/#192, with no functional improvement. The doc-level
mapping (this ADR + `docs/ou-structure.md`) is a sufficient bridge.

### Alternative B: Status quo (no Deployments / Sandbox)
Continue with the existing 5-OU layout (`Security`, `Infrastructure`,
`Workloads`, `NonProd`, `Prod` plus `Suspended`).

Rejected because: AFT (issue #168) needs its own OU so SCPs can grant
narrow permissions to the AFT pipeline IAM principals without touching
workload OUs. Developer sandboxes are a recognised access pattern that
deserves its own SCP profile (region-restrict + spend cap + no shared
services).

### Alternative C: Sub-OUs under `Workloads`
Place `Sandbox` as `Workloads/Sandbox` and `Deployments` as
`Infrastructure/Deployments`.

Rejected because: SCPs at the parent OU (`Workloads`, `Infrastructure`)
would inherit unintentionally, and AWS limits 5 SCPs per OU including
inherited ones. Top-level placement keeps the SCP attachment math clean.

## Consequences

### Positive
- AFT (#168) lands cleanly in its own OU with tightly-scoped SCPs.
- Developer-sandbox accounts don't pollute NonProd's SCP profile.
- SCP attachment matrix is documented in `docs/ou-structure.md`.

### Negative
- Doc-level alias mapping (`Prod` ↔ `Production`) adds a small cognitive
  burden for new contributors. Mitigated by linking to this ADR from
  `docs/ou-structure.md` and `terragrunt/_org/_global/organization/terragrunt.hcl`.
- Two new OUs increase the live SCP attachment count by 12
  (6 SCPs × 2 OUs) — well within AWS limits.

### Risks
- If a future workflow demands a human-administered Deployments account, we
  must remember to add `Deployments` to `workload_ou_names`. Mitigated by an
  inline comment in the SCPs unit explaining the omission.

## Implementation notes

- Files touched in #158:
  - `terragrunt/_org/_global/organization/terragrunt.hcl` (added 2 OUs)
  - `terragrunt/_org/_global/scps/terragrunt.hcl` (extended `mock_outputs`,
    added `Sandbox` to `workload_ou_names`)
  - `docs/ou-structure.md` (new — full hierarchy + SCP matrix)
- Rollback: revert PR #200; the two new OUs disappear and SCP attachments
  unwind via the same `for_each`.
- CI test coverage: `terragrunt plan` runs against the SCPs unit with the
  extended mock map; passes when `Deployments` and `Sandbox` are present.

## References

- Issue #158
- `docs/ou-structure.md`
- Source repo: `qbiq-ai/infra` issues #114-#117
- AWS Control Tower OU best practices:
  <https://docs.aws.amazon.com/controltower/latest/userguide/organizations.html>
