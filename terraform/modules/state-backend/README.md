# state-backend

Terraform-only bootstrap of an S3 + DynamoDB remote-state backend for one AWS
account. Replaces the legacy CloudFormation bootstrap pattern (TF-only, no
`bootstrap/state-backend.yaml`).

## What it creates

| Resource | Name | Hardening |
|---|---|---|
| `aws_s3_bucket.state` | `tfstate-<account>-<region>` | `prevent_destroy`, versioning, AES256/KMS, public-access block, self-logging, lifecycle, deny-non-TLS + deny-DeleteBucket policy |
| `aws_dynamodb_table.locks` | `terraform-locks-<account>` | `prevent_destroy`, PAY_PER_REQUEST, PITR, SSE |

The names are **load-bearing** — they must match the `remote_state` block in
`terragrunt/root.hcl`:

```hcl
bucket         = "tfstate-${local.account_name}-${local.aws_region}"
dynamodb_table = "terraform-locks-${local.account_name}"
```

If you change the naming scheme here, change it in `terragrunt/root.hcl` too,
or every Terragrunt unit will lose its state on next plan.

## Usage

This module is normally consumed by the bootstrap stack at
`bootstrap/state-backend/`, which is designed to run with **local** state
(no backend), bring up its own S3+DDB pair, and then optionally migrate
itself to remote state. See `scripts/deploy-state-backends.sh` for the
end-to-end flow.

Direct usage example:

```hcl
module "state_backend" {
  source = "../../terraform/modules/state-backend"

  account_name = "dev"
  aws_region   = "eu-west-1"

  # Optional: bring your own CMK
  # kms_key_arn = aws_kms_key.tfstate.arn

  tags = {
    Project = "platform-design"
    Owner   = "platform-team"
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `account_name` | string | (required) | One of: management, network, dev, staging, prod, dr, gcp-staging |
| `aws_region` | string | `eu-west-1` | AWS region for the state bucket |
| `kms_key_arn` | string | `null` | Optional customer-managed KMS key for S3+DDB encryption |
| `noncurrent_version_retention_days` | number | `90` | Days to retain noncurrent S3 object versions |
| `tags` | map(string) | `{}` | Extra tags merged into all resources |

## Outputs

| Name | Description |
|---|---|
| `state_bucket_name` | Created S3 bucket name |
| `state_bucket_arn` | Created S3 bucket ARN |
| `state_bucket_region` | Region the bucket lives in |
| `lock_table_name` | DynamoDB lock table name |
| `lock_table_arn` | DynamoDB lock table ARN |
| `terragrunt_remote_state_config` | Map matching the root.hcl `remote_state.config` shape |

## Bootstrap procedure

See [`bootstrap/state-backend/README.md`](../../../bootstrap/state-backend/README.md)
for the chicken-and-egg bootstrap workflow:

1. Run `scripts/deploy-state-backends.sh plan <account>` with management
   credentials to plan one account.
2. Run `scripts/deploy-state-backends.sh apply <account>` to create the
   bucket+table.
3. Subsequent Terragrunt runs in that account will find the backend already
   present and Just Work.

## Cost

- S3: storage is dominated by state files (kilobytes per unit) + access logs.
  At 5 accounts × 4 regions × ~1 MB total state, well under $0.10/month per
  bucket.
- DynamoDB: PAY_PER_REQUEST, with state-locks the read/write count is in the
  single digits per terraform run. Effectively free at this scale (< $1/mo
  per account).

## Rollback

Both resources have `lifecycle.prevent_destroy = true`. To remove a state
backend you must:

1. Migrate all units off it (`terraform state pull`/`push` or `terragrunt run-all`).
2. Empty the bucket (delete all object versions + delete markers).
3. Remove `prevent_destroy` from the resource block in this module.
4. Run `terraform apply` to delete.

This is intentional — losing the bucket means losing all state.
