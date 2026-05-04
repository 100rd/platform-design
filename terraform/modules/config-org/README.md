# config-org

Organization-wide AWS Config: per-account recorder + delivery channel,
org-wide aggregator (in the security/aggregator account), and a baseline
conformance pack applied across the organization.

Closes #162. Thin alias around the existing `aws-config` module which now
exposes the org-aggregator and conformance-pack additions made for this
issue.

## Coverage

| #162 acceptance criterion | How it's met |
|---|---|
| `modules/config-org` module | This module (alias of `aws-config`) |
| Aggregator in security account | **NEW**: `enable_organization_aggregator = true` -> `aws_config_configuration_aggregator` with org-wide source |
| Config recorder + delivery channel in each account | already in `aws-config` (recorder + delivery channel + S3 + IAM role + CIS rules) |
| Baseline conformance pack applied | **NEW**: `enable_organization_conformance_pack = true` -> `aws_config_organization_conformance_pack` |
| Logs to log-archive | already supported via `kms_key_arn` + `s3_bucket_name` (point at log-archive cross-account bucket) |

## Why a wrapper, not a rename?

Issue #162 asks for `modules/config-org` mirroring qbiq-ai/infra naming.
The existing `aws-config` module already creates the recorder, delivery
channel, IAM role, CIS managed rules, and S3 bucket. Renaming would force
state moves and break tests. The wrapper gives the canonical name without
churn; new code references `config-org`, existing `aws-config` callers
continue to work.

## Usage — per-account recorder

Deploy in every member account (typically via a per-account terragrunt
unit fan-out):

```hcl
module "config" {
  source = "../../terraform/modules/config-org"

  s3_bucket_name = "platform-design-config-${local.account_id}-${local.region}"
  kms_key_arn    = aws_kms_key.config.arn

  # Default: aggregator/conformance pack OFF — those run in the security
  # account only.

  tags = {
    Environment = "dev"
    ManagedBy   = "terragrunt"
  }
}
```

## Usage — security/aggregator account

In the security account (which has been delegated as Config administrator):

```hcl
module "config_aggregator" {
  source = "../../terraform/modules/config-org"

  s3_bucket_name = "platform-design-config-security-eu-west-1"
  kms_key_arn    = aws_kms_key.config.arn

  enable_organization_aggregator = true
  organization_aggregator_name   = "platform-design-org-aggregator"

  enable_organization_conformance_pack       = true
  baseline_conformance_pack_template_s3_uri  = "s3://aws-public-config-conformance-packs/Operational-Best-Practices-for-AWS-Foundational-Security-Best-Practices.yaml"
  organization_conformance_pack_name         = "platform-design-baseline-best-practices"

  tags = {
    Environment = "security"
    ManagedBy   = "terragrunt"
  }
}
```

## Pre-conditions

- The security account must have been registered as a Config delegated
  administrator (call `aws organizations register-delegated-administrator`
  with `service-principal=config.amazonaws.com` from the management
  account, or Terraform: `aws_organizations_delegated_administrator`).
- The S3 bucket can live in the same account as the recorder, or
  cross-account in log-archive (recommended). Cross-account requires the
  bucket policy to grant `config.amazonaws.com` write access from each
  member-account recorder.
- For the conformance pack, either `baseline_conformance_pack_template_body`
  (inline YAML) or `baseline_conformance_pack_template_s3_uri` (S3 URI to
  a YAML template) must be set when `enable_organization_conformance_pack
  = true`. AWS publishes ready-to-use templates in
  `s3://aws-public-config-conformance-packs/`.

## Inputs

Pass-through to `aws-config`. See
[`terraform/modules/aws-config/variables.tf`](../aws-config/variables.tf)
for full descriptions and validation rules. Highlights:

| Name | Default | Description |
|---|---|---|
| `s3_bucket_name` | (required) | Bucket holding Config snapshots |
| `kms_key_arn` | `""` | CMK for bucket SSE; empty -> AES-256 |
| `enable_organization_aggregator` | `false` | **NEW** — flip to `true` only in the security/aggregator account |
| `enable_organization_conformance_pack` | `false` | **NEW** — flip to `true` only where conformance packs should be deployed |
| `baseline_conformance_pack_template_s3_uri` | `""` | S3 URI to a Config conformance-pack template |

## Outputs

| Name | Description |
|---|---|
| `recorder_name` | Configuration recorder name |
| `s3_bucket_name` | S3 bucket name |
| `s3_bucket_arn` | S3 bucket ARN |

## Compliance

- PCI-DSS Req 1.1.1 (change tracking), Req 2.4 (resource inventory),
  Req 10.6 (log review), Req 11.5 (change detection)
- CIS managed rules already in `aws-config`: 1.5, 1.8-1.14, 1.10, 1.14,
  3.1, 3.2, 3.5, 3.7, 2.1.2

## Related

- [`terraform/modules/aws-config/`](../aws-config/) — underlying module
- AWS Config conformance packs:
  <https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html>
- AWS Config aggregator:
  <https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html>
