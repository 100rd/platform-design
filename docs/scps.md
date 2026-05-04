# Service Control Policies (SCPs)

**Source of truth**: `terraform/modules/scps/main.tf`
**Live config**: `terragrunt/_org/_global/scps/terragrunt.hcl`
**Closes**: #166

This page documents every SCP attached to the org, where it's attached, what
it denies, and which principals are exempt.

---

## Attachment topology

```
Root (r-XXXX)
├── DenyS3PublicAccess                      (root-level — applies everywhere)
├── RequireEBSEncryption                    (root-level — applies everywhere)
├── DataPerimeter-DenyExternalPrincipals    (root-level — applies everywhere) [NEW in #166]
│
├── Security OU
│   ├── DenyLeaveOrganization
│   ├── RestrictToEURegions
│   ├── DenyDisableCloudTrail
│   └── DenyGuardDutyChanges
│
├── Infrastructure OU
│   ├── DenyLeaveOrganization
│   ├── RestrictToEURegions
│   ├── DenyDisableCloudTrail
│   └── DenyGuardDutyChanges
│
├── Workloads OU (NonProd)
│   ├── DenyLeaveOrganization
│   ├── RestrictToEURegions
│   ├── DenyDisableCloudTrail
│   ├── DenyGuardDutyChanges
│   └── DenyRootAccountUsage
│
├── Prod OU
│   ├── DenyLeaveOrganization
│   ├── RestrictToEURegions
│   ├── DenyDisableCloudTrail
│   ├── DenyGuardDutyChanges
│   └── DenyRootAccountUsage
│
└── (optional) Suspended OU
    └── DenyAllSuspended
```

**AWS limit**: 5 SCPs per attachment target (including the implicit
`FullAWSAccess`). At root we currently use 4 of 5 slots
(`DenyS3PublicAccess`, `RequireEBSEncryption`, `DataPerimeter-DenyExternalPrincipals`,
plus `FullAWSAccess`). Each non-root OU uses 4 of 5 (5 for workload OUs that
also get `DenyRootAccountUsage`).

---

## Policy reference

### `DenyLeaveOrganization`
Prevents `organizations:LeaveOrganization`. No exemptions.

### `DenyDisableCloudTrail`
Denies `cloudtrail:DeleteTrail`, `StopLogging`, `UpdateTrail`. **No exemptions** — this is the audit trail. Terraform must not modify trails outside the dedicated `cloudtrail-org` module run from the management account.

### `DenyRootAccountUsage`
Denies any action where `aws:PrincipalArn` matches `arn:aws:iam::*:root`. Attached to **workload OUs only** (NonProd, Prod) — the management account legitimately uses root for the initial AWS Organizations setup.

### `RestrictToEURegions`
Denies any action where `aws:RequestedRegion` is not in the allowed list (default: `eu-west-1`, `eu-west-2`, `eu-west-3`, `eu-central-1`, `us-east-1`).

`us-east-1` is included because IAM, ACM (for CloudFront), Route 53, and CloudFront all hit the global endpoint that physically lives in us-east-1. Removing it would break those services.

**Exemptions**:
- `arn:aws:iam::*:role/OrganizationAccountAccessRole` (account vending requires global service access).
- `arn:aws:iam::*:role/${var.project}-terraform-*` (Terraform CI/CD role manages global IAM/ACM/CloudFront/Route 53 resources).

### `DenyGuardDutyChanges`
Denies `guardduty:DeleteDetector`, `DisassociateFromMasterAccount`, `UpdateDetector`. **No exemptions** — GuardDuty is managed only via delegated admin in the security account (PR #163).

### `DenyS3PublicAccess` (root-level)
Denies `s3:PutBucketPublicAccessBlock` and `s3:PutAccountPublicAccessBlock`.

**Exemption**: `arn:aws:iam::*:role/${var.project}-terraform-*` only. Terraform always sets these to *block* public access; the SCP keeps anyone else from removing the block. `OrganizationAccountAccessRole` is intentionally NOT exempt — there's no legitimate reason for account-vending to disable public-access blocks.

### `RequireEBSEncryption` (root-level)
Denies `ec2:CreateVolume` when `ec2:Encrypted = false`. **No exemptions** — Terraform must always create encrypted volumes.

### `DataPerimeter-DenyExternalPrincipals` (root-level) [NEW in #166]
Denies any action whose principal's `aws:PrincipalOrgID` does not match our organization. This is the identity-perimeter half of the AWS data-perimeter pattern.

**Conditions**:
- `StringNotEqualsIfExists aws:PrincipalOrgID = ${var.organization_id}`
- `BoolIfExists aws:PrincipalIsAWSService = false` — service principals (CloudTrail, Config recorder, etc.) are not affected; their service-linked roles often lack a full `PrincipalOrgID` context but they are clearly first-party.
- `ArnNotLike aws:PrincipalArn` exempts `OrganizationAccountAccessRole` and `${var.project}-terraform-*` — same pattern as `RestrictToEURegions`.

**Why `IfExists`?** Some STS endpoint calls during account vending or during the bootstrap of an Identity Store user lack a fully-resolved `PrincipalOrgID` context. The `IfExists` modifier means the deny only fires when the key is *present and not-equal* — eliminating the false-positive class while still blocking the real attack pattern (a principal whose OrgID is from a different org).

**What this catches**:
- A principal in a foreign organization gaining access to one of our roles via a misconfigured trust relationship.
- A compromised IAM user from outside our org acting through a service.
- Cross-org STS chain attacks.

**What this does NOT catch** (yet):
- Resource-perimeter (our principals reaching out to resources in foreign orgs). That requires `aws:ResourceOrgID` conditions on resource-using actions and is a follow-up.
- Network-perimeter (requests from unexpected VPCs / IPs). Handled separately in VPC endpoints / SCPs that gate `aws:SourceVpc`.

### `DenyAllSuspended`
Attached to the Suspended OU only. Denies all actions except those by `OrganizationAccountAccessRole` (used for break-glass and audit trail extraction during offboarding). Activated by setting `suspended_ou_id` in the terragrunt unit.

---

## Exemption philosophy (Issue #166 acceptance criterion)

The issue specifically calls for "exemptions limited to TerraformExecutionRole + OrganizationAccountAccessRole." In practice, this repo names them:

- `OrganizationAccountAccessRole` — created automatically by AWS Organizations when an account is invited or created.
- `${var.project}-terraform-*` — pattern matching the Terraform CI/CD apply role and any helper roles. Concretely today:
  - `platform-design-terraform-apply` (CI/CD)
  - `platform-design-terraform-plan` (CI/CD)
  - `platform-design-terraform-bootstrap` (state-backend bootstrap from #159)

Both patterns are codified in `var.project = "platform-design"`. Changing the project name regenerates every SCP that references the role pattern.

**Where exemptions ARE granted** (intentional):
- `RestrictToEURegions` — global services need us-east-1.
- `DenyS3PublicAccess` — Terraform sets `block_public_acls = true` etc. via `aws_s3_bucket_public_access_block` resources, which requires `PutBucketPublicAccessBlock`.
- `DataPerimeter-DenyExternalPrincipals` — same as above.
- `DenyAllSuspended` — `OrganizationAccountAccessRole` only (for offboarding).

**Where exemptions are NOT granted** (intentional — no exemption):
- `DenyDisableCloudTrail` — audit trail must be tamper-proof.
- `DenyRootAccountUsage` — root user must never act in workload accounts.
- `DenyGuardDutyChanges` — security telemetry must be tamper-proof.
- `RequireEBSEncryption` — encryption must always happen.
- `DenyLeaveOrganization` — accounts must not detach themselves.

---

## Adding a new SCP

1. Edit `terraform/modules/scps/main.tf`. Add the policy + attachment.
2. Run `terraform fmt`, `terraform validate`, and `terraform test`.
3. Update this document with the new policy (inventory section + topology
   diagram).
4. PR + merge.
5. **Watch the 5-SCP-per-OU limit**. If you're at 5 and need a 6th, either
   move a less-impactful one to root level (which has its own 5-cap
   limit) or merge two policies into one.

## Removing an SCP

1. Detach (`aws_organizations_policy_attachment` removed from `for_each` or
   `count` set to 0).
2. Wait for `terragrunt apply` to detach.
3. Then delete the `aws_organizations_policy` resource. Detach must
   precede delete or AWS rejects the delete.
4. PR + merge each step separately.

## Verification (after apply)

```bash
# List all org-level SCPs
aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].[Name,Id]' --output table

# List policies attached to a specific OU
aws organizations list-policies-for-target \
  --target-id ou-XXXX-YYYYYYYY \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].[Name,Id]' --output table

# Inspect the data-perimeter policy
aws organizations describe-policy --policy-id p-XXXXXXXX \
  --query 'Policy.Content' --output text | jq
```

## Related

- AWS data perimeter docs: <https://aws.amazon.com/identity/data-perimeters-on-aws/>
- AWS SCP documentation: <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html>
- Original issues this builds on: qbiq-ai/infra#5, #67, #110
