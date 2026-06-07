# modules/rcps — Resource Control Policies (resource-side data perimeter)

> **Provenance:** ADR-0017 — *Resource-side data perimeter and declarative org
> controls*. Epic #252. This module implements decision item **(1) Resource
> Control Policies** and is the resource-side complement to the principal-side
> SCP in [`modules/scps`](../scps).

## What this module does

Creates an `aws_organizations_policy` of type **`RESOURCE_CONTROL_POLICY`** — the
**org-perimeter RCP** — and attaches it to one or more OUs.

The org data perimeter was historically **principal-side only**: SCPs enforce
`aws:PrincipalOrgID` on *callers*. That gates identities, not resources, so a
public-bucket misconfiguration, an over-broad KMS grant, or a cross-account
trust still punched through the perimeter. The RCP closes the resource side:

| Half | Primitive | Gates | Lives in |
|------|-----------|-------|----------|
| Principal-side | `SERVICE_CONTROL_POLICY` | the *caller* | `modules/scps` (`DataPerimeter-DenyExternalPrincipals`) |
| **Resource-side** | **`RESOURCE_CONTROL_POLICY`** | *our resources* | **this module** |

### The seed RCP

`RCP-DataPerimeter-DenyExternalAccess` **denies** the canonical RCP-supported
services — **S3, STS, KMS, SecretsManager, SQS** — when:

- `aws:PrincipalOrgID` is **not** our org (`StringNotEqualsIfExists`), **and**
- the principal is **not** an AWS service (`BoolIfExists aws:PrincipalIsAWSService = false`).

`*IfExists` semantics mean the deny only fires when the key is *present and
mismatched* — service/STS edge cases that lack a fully-resolved `PrincipalOrgID`
context do not false-trip. The AWS-service carve-out keeps first-party flows
(log delivery, Config recorder, CloudTrail, cross-service calls) working.

## Evaluation model (read before reviewing)

RCPs evaluate **after** identity-based policy, SCPs, and resource-based policy.
An explicit `Deny` here is final. Because a mis-scoped RCP could deny legitimate
AWS-service access, this control is rolled out in **stages** (see below) rather
than straight to root.

RCPs have their **own slot budget**, separate from the 5-SCP-per-target cap, so
adding this control does **not** consume an SCP slot — it directly relieves the
root SCP slot pressure noted in ADR-0017.

## Staged rollout (ADR-0017 Implementation notes)

```
step 3  attach to Policy-Staging OU  ──►  verify no legitimate access breaks
step 4  promote to root              ──►  once staging is clean
```

The attachment is parameterized by `target_ou_ids` (a `for_each` set):

- **Now (staged):** wire the terragrunt input to the **Policy-Staging OU id**
  only. The terragrunt unit `_org/_global/rcps` does this via the organization
  module's `policy_staging_ou_id` output.
- **Promote:** switch the input to the **root id** (or add it). Because the
  attachment is `for_each`, promotion is additive and revertible.

## Prerequisite

`RESOURCE_CONTROL_POLICY` must be enabled in the organization's
`enabled_policy_types` (set in `_org/_global/organization`). Without it,
`aws_organizations_policy` of this type cannot be created.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `organization_id` | `string` | — | AWS Organization ID; the `aws:PrincipalOrgID` match. |
| `target_ou_ids` | `list(string)` | `[]` | OU/root IDs to attach the RCP to. **Staged: Policy-Staging OU only.** |
| `tags` | `map(string)` | `{}` | Tags for the RCP. |

## Outputs

| Name | Description |
|------|-------------|
| `policy_ids` | Map of RCP name → policy ID. |
| `policy_arns` | Map of RCP name → policy ARN. |
| `attached_target_ids` | OU/root IDs the RCP is attached to. |

## CI gate

Every change to `modules/scps` or `modules/rcps` is machine-checked by
`.github/workflows/policy-access-check.yml`, which runs IAM Access Analyzer
`check-no-new-access` / `check-access-not-granted` and gates on the JSON
`result` field. See ADR-0017 decision item (4).

## Testing

```bash
terraform init -backend=false
terraform validate
terraform test          # native tests, mock_provider — no AWS calls, no apply
```

> **Never `terraform apply` from here.** Apply is CI/CD-only, from `main`, via the
> terragrunt `_org/_global/rcps` unit, after the staged-rollout verification.
