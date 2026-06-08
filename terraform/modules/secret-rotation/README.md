# Module: `secret-rotation`

Automated rotation of a single DB/API credential in AWS Secrets Manager, plus the
rotation Lambda and least-privilege plumbing the existing `modules/secrets` rotation
hook needs but never provided. Implements **ADR-0031**.

`modules/secrets` will wire `aws_secretsmanager_secret_rotation` **only if handed a
Lambda ARN**. This module *produces* that Lambda (placeholder or an AWS-provided RDS
rotation template), scoped IAM, KMS encryption, and VPC config — and can rotate its
own secret end-to-end.

Part of epic #252.

## Resources created

- `aws_secretsmanager_secret.this` — the KMS-encrypted (customer-managed CMK)
  credential. `prevent_destroy` is set. Values are populated by the rotation Lambda
  or a secure pipeline, never in Terraform.
- `aws_secretsmanager_secret_rotation.this` — the rotation schedule via
  `rotation_rules` (`automatically_after_days` **or** a `schedule_expression`
  cron/rate window, plus optional `duration`). `rotate_immediately` honored.
- `aws_lambda_function.rotation` — the rotation function. Packages the bundled
  **placeholder** handler (`lambda/index.py`) by default, or a prebuilt `.zip`
  (e.g. an AWS RDS single-user / alternating-user template) via
  `lambda_package_path`. X-Ray tracing on; env payload encrypted with the secret CMK.
- `aws_iam_role.rotation` + `aws_iam_role_policy.rotation` — **least-privilege**:
  `secretsmanager:{DescribeSecret,GetSecretValue,PutSecretValue,UpdateSecretVersionStage}`
  scoped to **this secret ARN only**, `secretsmanager:GetRandomPassword`, and
  `kms:{Decrypt,GenerateDataKey}` scoped to **this secret's CMK only**.
- `aws_iam_role_policy_attachment.vpc_access` — attaches
  `AWSLambdaVPCAccessExecutionRole` **only when VPC config is enabled** (ENI mgmt).
- `aws_cloudwatch_log_group.rotation` — explicit log group with enforced retention,
  KMS-encrypted.
- `aws_lambda_permission.secretsmanager` — lets Secrets Manager invoke the function.

## Inputs (most-used)

| Variable | Default | Purpose |
|---|---|---|
| `name` | (required) | Secret name + base for Lambda/role/log-group names. |
| `kms_key_arn` | (required) | CMK for at-rest encryption AND the rotator's scoped KMS grant. |
| `secret_description` | `"Rotated credential ..."` | Human description of the credential. |
| `rotation_after_days` | `30` | Days between rotations (PCI-DSS Req 3.6.4 ≤ 90). Set `null` to use a schedule expression. |
| `rotation_schedule_expression` | `null` | `cron()`/`rate()` schedule (mutually exclusive with `rotation_after_days`). |
| `rotation_duration` | `null` | Rotation window length, e.g. `"3h"`. |
| `rotate_immediately` | `true` | Provider default; rotates once on enable. |
| `lambda_package_path` | `null` | Prebuilt rotation `.zip` (RDS template). `null` → bundled placeholder. |
| `lambda_runtime` | `"python3.12"` | Matches AWS RDS rotation templates. |
| `lambda_handler` | `"index.lambda_handler"` | Placeholder entrypoint; RDS template uses `lambda_function.lambda_handler`. |
| `vpc_subnet_ids` | `[]` | Private subnets for the Lambda ENIs (must route to RDS). Empty → no VPC config. |
| `vpc_security_group_ids` | `[]` | SGs for the Lambda ENIs (must reach the DB port). |
| `log_retention_days` | `365` | CloudWatch Logs retention. |

See `variables.tf` for the full list.

## Outputs

`secret_arn`, `secret_name`, `rotation_lambda_arn`, `rotation_lambda_name`,
`rotation_role_arn`, `rotation_enabled`, `log_group_name`.

`secret_arn` is what an ESO `ExternalSecret` references; `rotation_lambda_arn` can be
fed to `modules/secrets` to rotate *additional* secrets with the same function.

## Rotation schedule

Provide **exactly one** of:

- `rotation_after_days` (e.g. `30`) — simple N-day cadence, **or**
- `rotation_schedule_expression` (e.g. `"cron(0 3 1 * ? *)"`) with `rotation_after_days = null`.

`rotation_duration` (e.g. `"3h"`) optionally bounds the window. Verified against the
[`aws_secretsmanager_secret_rotation`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_rotation)
provider docs.

## Placeholder Lambda — replace before production

`lambda/index.py` is a **non-functional placeholder** that raises
`NotImplementedError`. It exists so the module packages and plans/validates cleanly.
Before enabling rotation against a live credential, supply a real implementation via
`lambda_package_path`:

- **Databases** → an [AWS-provided RDS rotation template](https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_available-rotation-templates.html)
  (single-user or alternating-user).
- **Non-RDS (e.g. model-provider API keys)** → a custom handler that calls the
  provider's key-rotation API, following the
  [four-step rotation protocol](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets-required-lambda-function.html).

## Closing the loop to pods (ESO)

Rotating the value in Secrets Manager is only half the job. The consuming
`ExternalSecret` must set a bounded **`refreshInterval`** so ESO re-pulls the rotated
`SecretString`, and consumers should use **Stakater Reloader** (or an ESO checksum
annotation) so the pods actually roll onto the new value. See
`apps/infra/external-secrets/README.md` and ADR-0031.

## Usage via Terragrunt

A unit under `terragrunt/<env>/<region>/.../secret-rotation/` sets `source` to this
module and supplies `kms_key_arn` (from the `kms` unit) and `vpc_subnet_ids` /
`vpc_security_group_ids` (from the network/RDS units) as `dependency` outputs.

## Testing

`secret-rotation.tftest.hcl` runs against a `mock_provider "aws"` — KMS encryption,
default 30-day cadence, schedule-expression override, VPC-config toggle, least-privilege
IAM scoping, and the invalid-`rotation_after_days` rejection. Run with
`terraform test`.
