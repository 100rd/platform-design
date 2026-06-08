# state-backend-dr

Cross-region disaster-recovery for the Terraform state backend. Adds an S3
replica bucket, IAM replication role, replication configuration on the
primary bucket, and a DynamoDB Global Tables v2 replica.

Closes #160.

## What it creates

| Resource | Region | Purpose |
|---|---|---|
| `aws_s3_bucket.state_replica` | `dr_region` | Read-only replica of the primary state bucket |
| `aws_s3_bucket_versioning.state_replica` | `dr_region` | Required for replication |
| `aws_s3_bucket_server_side_encryption_configuration.state_replica` | `dr_region` | aws:kms with optional CMK |
| `aws_s3_bucket_public_access_block.state_replica` | `dr_region` | All four knobs ON |
| `aws_s3_bucket_logging.state_replica` | `dr_region` | Self-logging |
| `aws_s3_bucket_lifecycle_configuration.state_replica` | `dr_region` | Abort multipart, expire noncurrent |
| `aws_s3_bucket_policy.state_replica` | `dr_region` | Deny non-TLS, deny DeleteBucket |
| `aws_iam_role.replication` | primary | Service role assumed by S3 |
| `aws_iam_role_policy.replication` | primary | Read source, write replica, optional KMS grants |
| `aws_s3_bucket_replication_configuration.state` | primary | Rule on the primary bucket |
| `aws_dynamodb_table_replica.locks_dr` | `dr_region` | Lock-table replica via DDB Global Tables v2 |

## Prerequisite: enable streams on the primary lock table

`aws_dynamodb_table_replica` requires the source table to have streams
enabled. Set this on the primary `state-backend` module **before** applying
this one:

```hcl
module "state_backend" {
  source = "../../terraform/modules/state-backend"

  account_name            = "dev"
  aws_region              = "eu-west-1"
  enable_dynamodb_streams = true   # <-- required for DR
}
```

This is an in-place update on the existing table; it does not recreate.

## Usage

```hcl
provider "aws" {
  region = "eu-west-1"
}

provider "aws" {
  alias  = "dr"
  region = "eu-central-1"
}

module "state_backend" {
  source = "../../terraform/modules/state-backend"

  account_name            = "dev"
  aws_region              = "eu-west-1"
  enable_dynamodb_streams = true
}

module "state_backend_dr" {
  source = "../../terraform/modules/state-backend-dr"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  account_name = "dev"
  primary_region = "eu-west-1"
  dr_region      = "eu-central-1"

  source_bucket_id      = module.state_backend.state_bucket_name
  source_bucket_arn     = module.state_backend.state_bucket_arn
  source_lock_table_arn = module.state_backend.lock_table_arn

  # Optional: pass through any CMKs in use
  # source_kms_key_arn = aws_kms_key.tfstate_primary.arn
  # kms_key_arn_dr     = aws_kms_key.tfstate_dr.arn
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `account_name` | string | (required) | Account short name |
| `primary_region` | string | `eu-west-1` | Primary state-backend region |
| `dr_region` | string | `eu-central-1` | DR region (must differ from primary) |
| `source_bucket_id` | string | (required) | Primary state bucket name |
| `source_bucket_arn` | string | (required) | Primary state bucket ARN |
| `source_lock_table_arn` | string | (required) | Primary DynamoDB lock table ARN (must have streams enabled) |
| `source_kms_key_arn` | string | `null` | Optional CMK ARN of the primary bucket — adds kms:Decrypt to replication role |
| `kms_key_arn_dr` | string | `null` | Optional CMK ARN in `dr_region` for the replica bucket — adds kms:Encrypt to replication role + sets `replica_kms_key_id` on the replication rule |
| `noncurrent_version_retention_days` | number | `90` | Days to retain noncurrent versions in the replica |
| `tags` | map(string) | `{}` | Extra tags |

## Outputs

| Name | Description |
|---|---|
| `replica_bucket_name` | Replica S3 bucket name |
| `replica_bucket_arn` | Replica S3 bucket ARN |
| `replica_bucket_region` | Replica region |
| `replication_role_arn` | IAM role used by S3 for replication |
| `replication_rule_id` | Replication rule ID on the primary bucket |
| `lock_table_replica_arn` | DDB lock-table replica ARN |
| `lock_table_replica_region` | DDB lock-table replica region |
| `failover_summary` | Map summarising primary + replica endpoints (use in runbooks) |

## Failover runbook

See [`docs/runbooks/state-backend-failover.md`](../../../docs/runbooks/state-backend-failover.md)
for the full step-by-step procedure for failing over from a regional outage.

Quick sketch:

1. Confirm primary region is genuinely unavailable (S3 + DynamoDB control
   planes both impacted; check AWS Health Dashboard).
2. Update `terragrunt/root.hcl`'s `remote_state.config.bucket` and `region`
   to point at the DR replica:
   ```hcl
   bucket = "tfstate-${local.account_name}-eu-central-1"
   region = "eu-central-1"
   ```
3. The DynamoDB lock table is a Global Table — the replica is already
   writeable in the DR region; no config change needed (Terragrunt will
   auto-discover it via the unchanged `dynamodb_table` name).
4. `terragrunt run-all init -migrate-state` is **not** required — state has
   been replicated continuously. `terragrunt plan` should succeed against
   the replica.
5. After primary recovers, run `aws s3 sync` from replica back to primary
   for objects that landed during the outage, then revert the root.hcl
   change. (Bidirectional replication is intentionally NOT enabled — see
   below.)

## Why one-way replication only

Bidirectional S3 cross-region replication on the same bucket pair creates a
loop unless every object has a replication-status header that breaks the
cycle. This is fragile; the AWS-recommended pattern is one-way + a manual
sync-back step on recovery. The DynamoDB Global Tables side IS bidirectional
(active-active) — that's the point of DDB GT — but there are no writes to
the lock table during a healthy run beyond brief lease grabs, so split-brain
risk is minimal.

## Cost

- S3 cross-region replication: $0.02 per GB transferred + replication PUT
  cost. State files are kilobytes; expected cost < $0.10 per account per
  month.
- DynamoDB Global Tables: replicated writes priced at standard regional
  WCU/RCU rates. With PAY_PER_REQUEST and infrequent locks, expect under
  $1 per account per month.

Total expected uplift over #159: ~$5 / month across all accounts.

## Rollback

To remove DR (rare — typically only when retiring an account or changing DR
region):

1. Remove the module block from the calling stack.
2. `terraform plan` shows the destroy. Review carefully.
3. Empty the replica bucket (versioned — needs explicit version delete).
4. Set `prevent_destroy = false` on the replica bucket via a fork of this
   module if needed (default has it on).
5. `terraform apply`.

The DDB replica can be removed without destroying the primary table
(promotes the global table back to a single-region table).
