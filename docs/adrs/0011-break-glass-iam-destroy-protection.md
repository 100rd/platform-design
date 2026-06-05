# ADR-0011: Break-glass IAM user destroy protection

- Status: **Accepted** — decision is *adopted (live in source estate)*
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

Each member account has a `break-glass-<account>` IAM user created by the
`modules/break-glass-user` module. It is the last-resort emergency access path
when AWS SSO / Identity Center is unavailable (control-plane outage,
mis-configured permission set, accidental SSO org detachment).

The module set `force_destroy = false` on `aws_iam_user.this`, which is **not**
equivalent to `lifecycle { prevent_destroy = true }`:

- `force_destroy = false`: Terraform fails *at apply* if it tries to delete the
  user while attached policies exist — but the deletion can still be **planned**.
- `lifecycle { prevent_destroy = true }`: Terraform errors *at plan time* if any
  configuration produces a destroy action — before any API call.

A `terraform destroy` or a stray `moved` block could silently plan deletion of a
break-glass user with only `force_destroy = false` in place.

## Decision

Add `lifecycle { prevent_destroy = true }` to `aws_iam_user.this` in
`modules/break-glass-user/main.tf`, in addition to `force_destroy = false`. A
reviewer can check conformance by confirming the break-glass user resource
carries both guards.

## Alternatives considered

### Alternative A: Rely on `force_destroy = false` alone
Keep the existing single guard.
Rejected because: it only blocks at apply, after the destroy is already planned —
it does not prevent a destroy plan from being produced, and the protection
depends on attached policies still existing.

### Alternative B: Out-of-band protection (SCP / resource tag + manual review)
Protect the user via an SCP denying `iam:DeleteUser` on the principal.
Rejected because: it adds cross-account policy surface for a guarantee Terraform
can make locally and declaratively. (An SCP could complement this later, but is
not the primary control.)

### Alternative C: Status quo
Leave it as-is.
Rejected because: emergency-access continuity is too important to leave to a
guard that only triggers at apply time.

## Consequences

### Positive
- Plan-time protection: the resource cannot appear in any destroy plan regardless
  of trigger (targeted destroy, full destroy, accidental `moved`).
- Defence in depth: two independent layers stop accidental deletion.
- Emergency-access continuity preserved during incidents.
- Intentional removals remain possible via a deliberate, reviewed commit removing
  the lifecycle block.

### Negative
- `terraform destroy` on an account with a break-glass user always fails for
  `aws_iam_user.this` until the lifecycle block is removed — intentional and
  expected.

### Risks
- Operators who must deliberately delete a break-glass user must (1) PR removing
  the lifecycle block, (2) get it reviewed/merged, (3) apply. This is the desired
  friction, not a bug.
- CI pipelines running `terraform destroy` for ephemeral environments are
  unaffected — the break-glass module is only used in long-lived account stacks.

## Implementation notes

- `modules/break-glass-user/main.tf`: add `lifecycle { prevent_destroy = true }`
  on `aws_iam_user.this`; keep `force_destroy = false`.
- Pairs with the break-glass operating procedure in `docs/break-glass-procedure.md`.

## References

- Terraform `prevent_destroy`: <https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle>
- Ported from `qbiq-ai/infra` ADR-010 (break-glass non-delete protection)
- Related: ADR-0001 (OU split / SCP guardrails)

---
*Ported from qbiq-ai/infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live).*
