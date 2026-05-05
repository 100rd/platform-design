# Module: `orphaned-resource-cleanup`

Scheduled Lambda (EventBridge cron, weekly Mon 06:00 UTC by default) that
scans the configured AWS regions for "orphaned" resources and posts an
advisory JSON report to S3 plus an optional SNS summary for Slack relay.

**Advisory only — never deletes anything.**

Closes #181.

## Resources

| Resource | When created |
|---|---|
| `aws_iam_role.scanner` | always |
| `aws_iam_role_policy.scanner` | always (read-only EC2/ELB + scoped S3 PutObject + optional SNS Publish) |
| `aws_iam_role_policy_attachment.logs` | always (`AWSLambdaBasicExecutionRole`) |
| `aws_lambda_function.scanner` | always (`python3.12`, packages `lambda/scanner.py`) |
| `aws_cloudwatch_event_rule.schedule` | always |
| `aws_cloudwatch_event_target.schedule` | always |
| `aws_lambda_permission.events` | always |

## Checks

| Check | Default | Tunable |
|---|---|---|
| `unattached_ebs_volumes` | true | `ebs_volume_min_age_days` (default 7) |
| `unused_elastic_ips` | true | — |
| `available_enis` | true | — |
| `old_ebs_snapshots` | true | `ebs_snapshot_max_age_days` (default 90) |
| `idle_nat_gateways` | true | (heuristic: state=available + no targets) |
| `unattached_load_balancers` | true | (no target groups bound) |

Each check is independently togglable via `var.checks_enabled`.

## Inputs (most-used)

| Variable | Default | Purpose |
|---|---|---|
| `name_prefix` | (required) | Used in resource names. |
| `report_s3_bucket` | (required) | S3 bucket for report uploads. Must already exist. |
| `report_s3_prefix` | `"orphaned-resources"` | Bucket prefix; one folder per scan date. |
| `slack_sns_topic_arn` | `""` | Optional SNS topic for summary publish. Empty disables. |
| `schedule_expression` | `"cron(0 6 ? * MON *)"` | EventBridge cron. |
| `regions_to_scan` | 4 EU regions | Per-invocation scan list. |
| `lambda_memory_mb` | `512` | Lambda memory. |
| `lambda_timeout_seconds` | `600` | Lambda timeout (cross-region scans serialise). |

## Report shape

```json
{
  "scan_started": "2026-05-04T06:00:00Z",
  "regions": ["eu-west-1", "eu-west-2", ...],
  "checks_enabled": {...},
  "by_region": {
    "eu-west-1": {
      "unattached_ebs_volumes": [
        {"kind": "ebs_volume", "id": "vol-...", "size_gb": 100, ...}
      ],
      "unused_elastic_ips": [...],
      ...
    },
    ...
  },
  "scan_finished": "2026-05-04T06:01:23Z",
  "totals": {
    "unattached_ebs_volumes": 4,
    "unused_elastic_ips": 0,
    ...
  }
}
```

## Cost

- Lambda: weekly run × 600s × 512MB ≈ \$0.05/month
- EventBridge: free for managed schedules
- S3: report sizes are KB-scale; lifecycle the prefix to Glacier after 30d

Total: ~\$1/month per account where the scanner runs.

## Security

- IAM role is read-only across EC2 and ELBv2.
- S3 PutObject scoped to `<bucket>/<report_prefix>/*`.
- SNS Publish scoped to the configured topic only (no wildcard).
- No write/destroy permissions on any AWS resource. The module
  intentionally cannot delete what it finds.

## NOT in scope (deliberate)

- **Auto-deletion** — the issue's acceptance criteria explicitly say
  "No auto-deletion (advisory only)". Deletion is an operator decision
  with rollback consequences; this module exists to surface candidates,
  not to act on them.
- **CloudWatch Metrics-based idle detection** — the NAT-gateway check is
  state-based heuristic only. A v2 enhancement could query
  CloudWatch's `BytesOutToDestination` over 7 days for higher accuracy.
- **Cross-account scanning** — each consumer deploys this module in
  their own account. AFT (#168) will likely propagate it as a baseline.

## Rollback

`terraform destroy` against the consuming unit removes the Lambda,
schedule, IAM role, and event rule. The S3 reports remain (lifecycle
managed externally).
