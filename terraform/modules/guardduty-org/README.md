# guardduty-org

Organization-wide GuardDuty with delegated administration, auto-enrollment
of all member accounts, full feature coverage (S3, EKS audit logs + runtime,
malware protection, RDS login, Lambda network), and optional S3 publishing
of findings to a centralized log-archive bucket.

Closes #163.

## Coverage

| #163 acceptance criterion | How it's met |
|---|---|
| `modules/guardduty-org` module | This module |
| Delegated admin = security account | `delegated_admin_account_id` input -> `aws_guardduty_organization_admin_account` (count=1 when delegating) |
| All accounts auto-enrolled | `auto_enable_org_members = true` -> `auto_enable_organization_members = "ALL"` on `aws_guardduty_organization_configuration` |
| EKS Audit Logs | `enable_eks_audit_log_monitoring = true` (default) |
| EKS Runtime monitoring | `enable_eks_runtime_monitoring = true` (default) |
| Malware Protection | `enable_malware_protection = true` (default) — EBS scan-on-finding |
| RDS protection | `enable_rds_protection = true` (default) — `RDS_LOGIN_EVENTS` feature |
| Findings published to centralized location | **NEW**: `findings_destination_bucket_arn` -> `aws_guardduty_publishing_destination` writing findings to S3 in the log-archive account |

Plus, beyond the issue:
- S3 data event protection (`enable_s3_protection`)
- Lambda network activity monitoring (`enable_lambda_protection`)

## Usage

```hcl
module "guardduty_org" {
  source = "../../terraform/modules/guardduty-org"

  delegated_admin_account_id = "111122223333"  # security account
  auto_enable_org_members    = true

  # Findings centralization (cross-account to log-archive)
  findings_destination_bucket_arn  = "arn:aws:s3:::platform-design-guardduty-findings"
  findings_destination_kms_key_arn = aws_kms_key.findings.arn

  # All feature toggles default to true; flip off if you don't need a feature
  # enable_lambda_protection = false

  tags = {
    Environment = "security"
    ManagedBy   = "terragrunt"
  }
}
```

## Pre-conditions for findings publishing

The `findings_destination_bucket_arn` bucket (in log-archive account) must:
1. Have a bucket policy granting `guardduty.amazonaws.com` `s3:PutObject` on
   `<bucket>/*` with the GuardDuty service principal.
2. Be encrypted with a KMS CMK whose key policy allows
   `kms:GenerateDataKey` to `guardduty.amazonaws.com`.

A separate `centralized-logging` (or similar) module in the log-archive
account creates the bucket + key + policies. Pass its outputs to this
module's inputs.

## Inputs (selected)

| Name | Type | Default | Description |
|---|---|---|---|
| `delegated_admin_account_id` | string | `""` | Security account ID to delegate GD to |
| `auto_enable_org_members` | bool | `true` | Auto-enable for all current and future members |
| `enable_s3_protection` | bool | `true` | S3 data event monitoring |
| `enable_eks_audit_log_monitoring` | bool | `true` | EKS audit logs |
| `enable_eks_runtime_monitoring` | bool | `true` | EKS runtime agent (`EKS_RUNTIME_MONITORING`) |
| `enable_malware_protection` | bool | `true` | EBS volume scan-on-finding |
| `enable_rds_protection` | bool | `true` | `RDS_LOGIN_EVENTS` feature |
| `enable_lambda_protection` | bool | `true` | `LAMBDA_NETWORK_LOGS` feature |
| `findings_destination_bucket_arn` | string | `null` | S3 bucket ARN for centralized findings (NEW in #163) |
| `findings_destination_kms_key_arn` | string | `null` | KMS CMK for findings encryption |
| `tags` | map(string) | `{}` | Tags |

## Outputs

| Name | Description |
|---|---|
| `detector_id` | GuardDuty detector ID |
| `detector_arn` | GuardDuty detector ARN |
| `delegated_admin_account_id` | Configured delegated admin account |

## Compliance

- PCI-DSS Req 10.6 — daily log/event review (automated via GuardDuty)
- PCI-DSS Req 11.4 — IDS/IPS (GuardDuty as cloud-native IDS)
- PCI-DSS Req 11.5 — change-detection (EBS malware scanning)

## Related

- [`docs/scps.md`](../../../docs/scps.md#denyguarddutychanges) — SCP that
  protects the GuardDuty configuration from being disabled
- AWS GuardDuty docs:
  <https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_settingup.html>
