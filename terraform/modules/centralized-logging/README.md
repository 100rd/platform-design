# Module: `centralized-logging`

Org-wide log archive in the log-archive account. Aggregates CloudTrail
org-trails, Config snapshots, VPC Flow Logs, EKS audit/authenticator
streams into a single immutable S3 bucket with cross-region replication
to a DR-region mirror.

Closes #182.

## Resources

| Resource | When created |
|---|---|
| `aws_s3_bucket.this` | always — primary bucket with Object Lock enabled at creation |
| `aws_s3_bucket_versioning.this` | always |
| `aws_s3_bucket_public_access_block.this` | always |
| `aws_s3_bucket_server_side_encryption_configuration.this` | always — SSE-KMS via `var.kms_key_arn` |
| `aws_s3_bucket_object_lock_configuration.this` | when `enable_object_lock = true` (default) |
| `aws_s3_bucket_lifecycle_configuration.this` | always — STANDARD → IA → GLACIER → expire |
| `aws_s3_bucket_policy.this` | always — DenyInsecureTransport + per-account writers + CloudTrail/Config service principals |
| `aws_s3_bucket.dr[0]` | when `enable_replication = true` AND `dr_kms_key_arn != ""` |
| `aws_iam_role.replication[0]` + scoped policy | when replication enabled |
| `aws_s3_bucket_replication_configuration.this[0]` | when replication enabled — replicates everything (Versioning + delete-markers + KMS-encrypted objects) |

## Inputs (most-used)

| Variable | Default | Purpose |
|---|---|---|
| `bucket_name` | (required) | Globally unique bucket name. Convention: `<project>-log-archive-<account_id>-<region>`. |
| `kms_key_arn` | (required) | Primary-region KMS key (`alias/log-archive`). |
| `dr_kms_key_arn` | `""` | DR-region KMS key. Required for replication. |
| `enable_object_lock` | `true` | PCI-DSS Req 10.5 immutable retention. **Cannot be disabled later.** |
| `object_lock_mode` | `"GOVERNANCE"` | `GOVERNANCE` (admin override) or `COMPLIANCE` (no override). |
| `object_lock_retention_days` | `365` | Default per-object retention. |
| `lifecycle_*` | 30 / 90 / 365 / 2555 | Tier transitions + 7-year expiry. |
| `trusted_writer_account_ids` | `[]` | List of member-account IDs that may write to their own prefix. |
| `log_source_prefixes` | 5 default sources | Map of source-name → prefix. |

## Provider configuration

The module declares an `aws.dr` provider alias (see `versions.tf`). The
consuming root supplies it:

```hcl
provider "aws" {
  region = "eu-west-1"
}

provider "aws" {
  alias  = "dr"
  region = "eu-central-1"
}
```

## Bucket policy

The auto-generated policy enforces:

- **TLS-only** (`DenyInsecureTransport` deny statement).
- **Per-account scoped writes** — each member account in
  `trusted_writer_account_ids` can `PutObject` to its own
  `<prefix>/AWSLogs/<account>/*` path with
  `s3:x-amz-acl == bucket-owner-full-control`.
- **CloudTrail + Config service principals** — the standard
  `s3:GetBucketAcl` + `s3:PutObject` allow statements required by AWS
  for org-trail and aggregated-Config delivery.

The DR bucket has no bucket policy of its own — replication writes
inherit the role's permissions.

## Lifecycle

Object lifecycle: `STANDARD` → `STANDARD_IA` (30d) → `GLACIER` (90d) →
expire (2555d ≈ 7 years).

PCI-DSS Req 10.5 specifies tamper-proof retention for at least 1 year
in immediately-accessible storage, plus extended retention for 3+
years. The defaults here exceed both requirements.

## Cost

Approximate monthly cost for a typical 9-account org with full
CloudTrail / Config / VPC Flow / EKS audit ingestion:

| Component | ~Volume | Cost |
|---|---|---|
| STANDARD storage (first 30d) | 50 GB | \$1.15 |
| STANDARD_IA (30-90d) | 100 GB | \$1.25 |
| GLACIER (90d-7yr) | 5 TB | \$20 |
| KMS API calls | ~1M/month | \$3 |
| Cross-region replication transfer | 50 GB | \$1 |
| Replicated storage (DR) | full mirror | matches primary |
| **Total** | | **~\$50-60/month** |

## Rollback

`terraform destroy` is **disabled** by Object Lock — once a bucket has
Object Lock enabled, neither the bucket nor objects under retention
can be deleted until retention expires. To roll back:
1. Wait out the retention period (default 365 days), OR
2. If `object_lock_mode = "GOVERNANCE"`, an admin with
   `s3:BypassGovernanceRetention` can delete objects sooner.

The bucket itself can be deleted only when empty AND no objects under
retention remain.
