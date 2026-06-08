# break-glass-user

Single emergency-access IAM user per account, used **only** when AWS SSO /
Identity Center is unavailable (control-plane outage, mis-configured permission
set, accidental SSO org detachment).

Implements **ADR-0011 — Break-glass IAM user destroy protection**. The user
carries two independent destruction guards:

| Guard | Trigger | What it stops |
|---|---|---|
| `lifecycle { prevent_destroy = true }` | plan time | The user can never appear in any destroy plan — targeted destroy, full destroy, or a stray `moved` block — until the block is deliberately removed via PR. |
| `force_destroy = false` | apply time | Terraform fails if it tries to delete the user while attached policies still exist. |

## Resources

| Resource | Purpose |
|---|---|
| `aws_iam_user.this` | The break-glass user, name `break-glass-<account_name>`, path `/break-glass/`, with `prevent_destroy` + `force_destroy = false` |
| `aws_iam_user_policy.mfa_enforcement` | Inline deny — locks the user to MFA-only setup actions until MFA is enrolled and `aws:MultiFactorAuthPresent = true` |
| `aws_iam_user_policy_attachment.administrator_access` | AWS-managed `AdministratorAccess` (only effective within an MFA-present session) |
| `aws_iam_user_login_profile.this` | Optional console login (`create_console_login`), password reset required on first login |
| `aws_iam_access_key.this` | Optional initial programmatic key (`create_access_key`, sensitive output) |
| `aws_cloudwatch_log_metric_filter.usage` + `aws_cloudwatch_metric_alarm.usage` | Alarm on any CloudTrail event with `userIdentity.userName = break-glass-<account_name>` |

## Inputs

| Variable | Required | Default | Description |
|---|---|---|---|
| `account_name` | yes | — | Account short name; user becomes `break-glass-<account_name>` |
| `name_prefix` | no | `""` | Prefix for the inline-policy and alarm names (not the user name) |
| `create_access_key` | no | `false` | Whether to create the initial access key (opt-in, single-apply bootstrap) |
| `create_console_login` | no | `false` | Whether to create a console login profile for emergency console access |
| `alarm_sns_topic_arn` | no | `""` | SNS topic to notify on break-glass use. Skips the alarm if empty |
| `cloudtrail_log_group_name` | no | `""` | CloudWatch Logs group receiving CloudTrail. Required for the metric filter |
| `tags` | no | `{}` | Extra tags merged over the module defaults |

## Outputs

- `user_name`, `user_arn` — identifiers for documentation
- `mfa_serial` — *expected* MFA device ARN once enrolled (a hint, not a real device)
- `access_key_id`, `access_key_secret` (sensitive) — copy once, then rotate
- `console_password` (sensitive) — initial console password when `create_console_login = true`
- `alarm_arn` — for downstream dashboards

## Break-glass runbook

1. **Confirm SSO is unavailable.** Don't reach for break-glass for routine work.
2. **Retrieve credentials from the team password manager** for the target account
   (access_key_id, secret_access_key, MFA serial, and console password if used).
3. **Export the access key:**
   ```bash
   export AWS_ACCESS_KEY_ID=<from-vault>
   export AWS_SECRET_ACCESS_KEY=<from-vault>
   ```
4. **Acquire an MFA-present session token** (every other API call is denied by the
   inline policy without it):
   ```bash
   aws sts get-session-token \
     --serial-number arn:aws:iam::<acct>:mfa/break-glass-<account_name> \
     --token-code <6-digit-MFA-code> \
     --duration-seconds 3600
   ```
   Export the returned `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and
   `AWS_SESSION_TOKEN`.
5. **Verify** with `aws sts get-caller-identity` — should report the break-glass
   user with `aws:MultiFactorAuthPresent = true`.
6. **Operate.** Full Administrator policy is now in effect.
7. **After the incident (within 24h):**
   - Document the use in the incident retro.
   - Rotate the access key: create a new key, save it, then delete the old one.
   - Confirm the CloudWatch alarm fired and was acknowledged by security.

See [`docs/break-glass-procedure.md`](../../../docs/break-glass-procedure.md) for the
full operating procedure.

## Intentional removal

The `prevent_destroy` guard is deliberate friction. To remove a break-glass user:

1. Open a PR removing the `lifecycle { prevent_destroy = true }` block.
2. Get it reviewed and merged.
3. Apply.

This is the desired workflow, not a bug — see ADR-0011.

## Anti-features (deliberately not done)

- **No automatic rotation.** Rotating into vaults from Terraform creates a leak surface.
- **No groups, no shared roles.** Single-purpose user, no membership management.
- **No SSO permission set.** Break-glass is the *fallback* when SSO is the thing that's broken.

## See also

- [`docs/adrs/0011-break-glass-iam-destroy-protection.md`](../../../docs/adrs/0011-break-glass-iam-destroy-protection.md) — the ADR this module implements
- [`modules/iam-baseline`](../iam-baseline/) — per-account password policy + MFA enforcement policy + Access Analyzer
- [`modules/cloudtrail`](../cloudtrail/) — provides the CloudWatch log group this module's alarm reads from
- [`modules/scps`](../scps/) — org guardrails that complement the destroy protection
