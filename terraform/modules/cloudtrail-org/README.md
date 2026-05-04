# cloudtrail-org

Organization-wide CloudTrail with multi-region coverage, log file
validation, KMS CMK encryption, S3 Object Lock + lifecycle, and CloudWatch
Logs integration.

Closes #161. This is the canonically-named wrapper around the
[`cloudtrail`](../cloudtrail/) module which already produces an
organization trail; new code should reference this module name to match
the source repo (qbiq-ai/infra) convention.

## What it produces

The underlying `cloudtrail` module creates:

- `aws_cloudtrail` with `is_organization_trail = true`,
  `is_multi_region_trail = true`,
  `enable_log_file_validation = true`, KMS CMK encryption, management
  events + S3/Lambda data events.
- `aws_s3_bucket` for log storage with versioning, KMS encryption,
  public-access block, lifecycle (STANDARD -> STANDARD_IA -> GLACIER
  -> EXPIRE), Object Lock (COMPLIANCE mode, retention configurable).
- `aws_iam_role` for CloudTrail-to-CloudWatch delivery.
- `aws_cloudwatch_log_group` for real-time analysis.

## Why a wrapper, not a rename?

Issue #161 asks for a module named `cloudtrail-org` mirroring the
source repo. The existing `cloudtrail` module already meets every #161
acceptance criterion (`is_organization_trail`, `is_multi_region_trail`,
log file validation, KMS, S3 delivery to log-archive). Renaming the
existing module would force state moves and break every test reference.
The wrapper gives the canonical name without churn.

## Usage

```hcl
module "cloudtrail_org" {
  source = "../../terraform/modules/cloudtrail-org"

  trail_name      = "platform-design-org-trail"
  organization_id = "o-xxxxxxxxxx"
  kms_key_arn     = aws_kms_key.cloudtrail.arn

  s3_bucket_name = "platform-design-cloudtrail-${local.account_id}"

  # Defaults are sensible — these are the most-tweaked knobs:
  # lifecycle_glacier_days        = 365
  # lifecycle_expiration_days     = 2555  # 7 years (PCI-DSS compliant)
  # object_lock_retention_days    = 365
  # cloudwatch_log_retention_days = 365

  tags = {
    Environment = "log-archive"
    ManagedBy   = "terragrunt"
  }
}
```

## Inputs

Identical to `terraform/modules/cloudtrail/`. See its variables.tf for
the full list. Most-tweaked:

| Name | Default | Description |
|---|---|---|
| `trail_name` | `org-trail` | CloudTrail trail name |
| `organization_id` | (required) | Used in S3 bucket policy for org-trail PUT permissions |
| `kms_key_arn` | (required) | CMK ARN for trail + S3 default encryption |
| `s3_bucket_name` | (required) | Bucket holding the logs (in log-archive account) |
| `enable_object_lock` | `true` | WORM via S3 Object Lock |
| `object_lock_retention_days` | `365` | COMPLIANCE-mode retention; **irreversible** |
| `lifecycle_expiration_days` | `2555` | 7 years (PCI-DSS Req 10.7) |
| `cloudwatch_log_retention_days` | `365` | CW Logs retention |

## Outputs

Delegated 1:1 to `terraform/modules/cloudtrail`:

`trail_arn`, `trail_name`, `s3_bucket_name`, `s3_bucket_arn`,
`cloudwatch_log_group_name`, `cloudwatch_log_group_arn`,
`cloudtrail_cloudwatch_role_arn`.

## Where it gets deployed

The org trail lives in the **management** account (only the management
account, or the AWS Organizations delegated administrator, can create an
organization trail). The S3 destination bucket should live in the
**log-archive** account for tamper resistance. Cross-account write is
authorized via the bucket policy on the log-archive bucket.

The accompanying terragrunt unit
[`terragrunt/_org/_global/cloudtrail/terragrunt.hcl`](../../../terragrunt/_org/_global/cloudtrail/terragrunt.hcl)
runs in the management account by virtue of being under `_org/`.

## Compliance

The underlying module documents PCI-DSS Req 10.1, 10.2, 10.3, 10.5,
10.5.3, 10.5.5, and 10.7 alignment. See the comments in
`terraform/modules/cloudtrail/main.tf` for the per-requirement breakdown.

## Related

- [`terraform/modules/cloudtrail/`](../cloudtrail/) — underlying module
- [`docs/scps.md`](../../../docs/scps.md#denydisablecloudtrail) — SCP that
  protects the trail from being disabled
- AWS docs: <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/creating-trail-organization.html>
