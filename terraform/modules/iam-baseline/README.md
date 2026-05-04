# iam-baseline

Per-account IAM hardening: PCI-DSS-aligned password policy, MFA enforcement
policy for break-glass IAM users, IAM Access Analyzer, account-level S3
public access block, EBS encryption-by-default, account alias, and a Config
rule that flags root access keys.

Closes #165. Builds on the original baseline by adding the missing pieces
called out in the issue: account alias and root access-key alarm.

## Coverage

| #165 acceptance criterion | How it's met |
|---|---|
| `modules/iam-baseline` module | This module |
| Password policy (length, complexity, rotation) | `aws_iam_account_password_policy.pci_dss` (defaults exceed PCI-DSS Req 8.2 minimums — 14 chars, complexity, 90-day rotation, 24-password reuse window) |
| Account alias set | **NEW**: `account_alias` input -> `aws_iam_account_alias` |
| Root access keys check (alarm if present) | **NEW**: `enable_root_access_key_alarm = true` (default) -> `aws_config_config_rule.iam_root_access_key_check` (managed rule `IAM_ROOT_ACCESS_KEY_CHECK`) |
| Applied to all accounts via Terragrunt | This module is consumed per-account; the terragrunt unit fans out across accounts |

Plus, beyond the issue:
- IAM Access Analyzer (CIS 1.20) — `aws_accessanalyzer_analyzer` (ORGANIZATION in mgmt, ACCOUNT in others)
- S3 account-level public access block (CIS 2.1.5)
- EBS encryption by default (CIS 2.2.1)
- MFA enforcement policy for IAM users (PCI-DSS Req 8.3)

## Usage

Per-account terragrunt unit:

```hcl
module "iam_baseline" {
  source = "../../terraform/modules/iam-baseline"

  account_alias = "platform-design-dev"   # NEW (#165)
  name_prefix   = "platform-"

  # Password policy defaults are PCI-DSS-compliant; tweak only if needed.

  # Use ORGANIZATION analyzer in management; ACCOUNT elsewhere.
  analyzer_type = "ACCOUNT"

  # Default EBS key
  ebs_kms_key_arn = aws_kms_key.ebs.arn

  # Root access-key alarm — keep on (default true)
  enable_root_access_key_alarm = true

  tags = {
    Environment = "dev"
    ManagedBy   = "terragrunt"
  }
}
```

## Inputs (selected)

| Name | Default | Description |
|---|---|---|
| `account_alias` | `""` | Account alias (3-63 chars, lowercase + hyphens). Empty to skip. **NEW in #165** |
| `name_prefix` | `""` | Prefix for IAM resource names |
| `minimum_password_length` | `14` | exceeds PCI-DSS Req 8.2.3 (>=7) |
| `max_password_age` | `90` | PCI-DSS Req 8.2.4 (<=90) |
| `password_reuse_prevention` | `24` | exceeds PCI-DSS Req 8.2.5 (>=4) |
| `analyzer_type` | `"ACCOUNT"` | `"ORGANIZATION"` in mgmt only |
| `ebs_kms_key_arn` | `""` | Custom CMK for default EBS encryption |
| `enable_root_access_key_alarm` | `true` | **NEW in #165** — Config rule `IAM_ROOT_ACCESS_KEY_CHECK` |

See `variables.tf` for the full list with descriptions.

## Outputs

| Name | Description |
|---|---|
| `password_policy_id` | Account password policy ID |
| `enforce_mfa_policy_arn` | ARN of the EnforceMFA managed policy (attach to break-glass IAM groups) |
| `access_analyzer_arn` | IAM Access Analyzer ARN |
| `iam_root_access_key_check_rule_arn` | (when alarm enabled) Config rule ARN |

## Why a Config rule for root access keys?

There is no native CloudWatch metric for "root has an active access key."
The supported AWS-native primitive is exactly the managed Config rule
`IAM_ROOT_ACCESS_KEY_CHECK`, which evaluates compliance and publishes
NON_COMPLIANT findings to:

1. AWS Config's findings stream
2. SecurityHub (#164) when subscribed
3. The centralized findings bucket in log-archive (when wired)

Combined that's the alarm pathway — non-compliance is surfaced wherever the
team monitors security findings.

The rule depends on AWS Config being enabled in the account
(`aws_config_configuration_recorder` etc.), which is provisioned by the
`config-org` module (#162). If Config is not yet enabled, the rule resource
still applies cleanly but evaluations will only begin once Config is
recording.

## Pre-conditions

- For the account alias to apply, the account must not already have a
  conflicting alias set out-of-band. AWS allows only one alias per account;
  re-running `terraform apply` is idempotent (`aws_iam_account_alias` is
  managed in-place).
- The Config rule depends on AWS Config being enabled (out-of-module);
  see `terraform/modules/aws-config` (issue #162).

## Compliance

- PCI-DSS Req 8.2.3, 8.2.4, 8.2.5, 8.3, 8.3.6
- CIS 1.1 (account alias), 1.8-1.14 (password policy), 1.20 (Access Analyzer),
  2.1.5 (S3 PAB), 2.2.1 (EBS encryption)

## Related

- [`docs/scps.md#denyrootaccountusage`](../../../docs/scps.md#denyrootaccountusage)
  — SCP that prevents root user actions in workload accounts
- [`terraform/modules/aws-config`](../aws-config/) — module that enables
  AWS Config (required for the root access-key alarm rule to evaluate)
