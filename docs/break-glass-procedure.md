# Break-glass procedure for root account access

Closes part of issue #169.

## What "break-glass" means here

The **management account root user** (`000000000000` per
`terragrunt/_org/account.hcl`) is the most privileged identity in the AWS
Organization. It can:

- Close the organisation, leave a parent organisation, change the org root.
- Modify SCPs that block all other principals.
- Delete the audit trail (CloudTrail).
- Reach any account via `OrganizationAccountAccessRole`.

Day-to-day administrative work uses **AWS Identity Center** (SSO) plus
delegated-admin roles in the security account. The root credentials are
locked away and used only when **no other path works** — for example:

- AWS Identity Center is broken / IdP outage; cannot assume any role.
- Billing / payment-method changes (a small set of operations still
  require root).
- Recovering from a misconfigured SCP that locked out the platform team.
- Closing the organisation or a member account.

The "break-glass" runbook below is the only sanctioned path to use the
root credentials. **Every use generates a high-severity alert and a
post-incident review.**

## Pre-conditions (one-time setup)

1. **MFA on the root account** — virtual or hardware MFA registered. Two
   independent admins each have a MFA device; both required for access.
2. **Strong password** — 32+ char generated, stored in offline 1Password
   vault `aws-root` accessible only to the platform-team-leads group.
3. **No long-lived access keys** — root has zero programmatic access keys.
   The IAM Config rule `IAM_ROOT_ACCESS_KEY_CHECK` (added in PR #195)
   alerts on any key creation.
4. **CloudTrail** — `_org/_global/cloudtrail` (PR #193) covers all root
   activity in the org-trail bucket in `log-archive`.
5. **Alerting** — `aws-cli-root-credential-usage` EventBridge rule routes
   `aws.iam` events with `userIdentity.type == "Root"` to the
   `platform-oncall` SNS topic, which fans out to PagerDuty and the
   `#aws-security` Slack channel.

## Procedure

### 1. Justification (BEFORE pulling credentials)

- Open a ticket in the `aws-security` Jira project with template
  `BREAK-GLASS`. Include:
  - What you're trying to do (one sentence).
  - Why no non-root path works (link to attempted path / error message).
  - Expected duration in the root session.
  - Reviewer (the second admin who will dual-witness).
- Get explicit Slack ack from the second admin in `#aws-security`.

### 2. Retrieve credentials

```bash
# Run from your laptop; do not redirect or pipe to anything.
./scripts/break-glass.sh request --reason "JIRA-123: closing organisation"
```

The script:
- Validates that you are on the platform-team-leads list.
- Records the `--reason` to CloudWatch Logs.
- Prints the password retrieval URL (1Password vault).
- Prints the MFA code prompt (you fetch from your MFA device).
- Does **NOT** print or persist the password or MFA code itself.

### 3. Sign in

- Use **incognito browser** / dedicated Firefox profile with clean state.
- Navigate to <https://signin.aws.amazon.com>.
- Sign in as the management account root user.
- Re-authenticate with MFA when prompted.

### 4. Perform the operation

- Keep the session **as short as possible** (target <15 minutes).
- Do **not** create access keys, IAM users, or password policies.
- Do **not** disable CloudTrail, GuardDuty, SecurityHub, or any SCP.
- Do **not** modify the audit trail bucket policy in `log-archive`.

### 5. Sign out & rotate

- Click "Sign out" (do not close the tab).
- Run:
  ```bash
  ./scripts/break-glass.sh release --reason "JIRA-123: complete"
  ```
- The script:
  - Records the release to CloudWatch Logs.
  - Triggers a password rotation via 1Password CLI.
  - Updates the Jira ticket with end-time and a CloudTrail link to the
    session events.

### 6. Post-incident review (within 24h)

- Pull the CloudTrail events for the session (the `release` step prints
  the link).
- File a short writeup in the Jira ticket: what was done, what the
  CloudTrail events show, whether anything unexpected happened.
- If a procedural improvement is identified, open a follow-up issue in
  the `platform-design` repo.

## Failure modes & recovery

### "I can't reach 1Password"
- Backup vault: offline-stored YubiKey-encrypted file in the Frankfurt
  office safe. Two leads + the office manager have access; coordinate
  retrieval via `#aws-security` Slack.

### "MFA device lost"
- AWS root MFA cannot be re-bound from inside the account if you can't
  log in. Use the **lost MFA device** flow (calls AWS Support, email
  verification to the root mailbox `aws+management@example.com`).
- The root mailbox is itself protected: 2FA, SSO via Google Workspace,
  audit log monitored by the security team.

### "Alert didn't fire"
- The CloudTrail-based alert has a ~5 min delay. If you don't see a
  PagerDuty page within 10 min of sign-in, escalate via `#aws-security`
  and check the EventBridge rule status.

## Related controls

- **`scps` module** (PR #192): `DenyLeaveOrganization`,
  `DenyDisableCloudTrail` — these apply to **member** accounts, NOT the
  management account itself. The management root is exempt by design;
  break-glass is the only legitimate path to those operations.
- **`iam-baseline` module** (PR #195): `IAM_ROOT_ACCESS_KEY_CHECK`
  Config rule — fires non-compliant if root has any active access key.
- **`securityhub-org`** (PR #197): centralised findings; root usage
  surfaces here as well as in CloudTrail.

## References

- Issue #169
- Source repo: `qbiq-ai/infra` issue #68
- AWS root user best practices:
  <https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#lock-away-credentials>
- `scripts/break-glass.sh`
