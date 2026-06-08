# Module: `eks-log-aggregation`

Ships EKS control-plane log streams (audit + authenticator) from the
per-cluster CloudWatch log group to the centralized log-archive S3
bucket in the log-archive account.

Closes #178.

## Pipeline

```
EKS control plane
  └── /aws/eks/<cluster>/cluster   (CloudWatch Logs)
        ├── kube-apiserver-audit  ──┐
        └── authenticator         ──┘
              │
              │  CloudWatch Logs subscription filter
              │  (filter_pattern = "")
              ▼
        Kinesis Data Firehose
              │
              │  buffer 60s / 5MB, GZIP, dynamic partition by accountId
              ▼
        S3 (log-archive bucket via cross-account write)
              │
              │  prefix: <eks-audit-prefix>/AWSLogs/<account>/<region>/<cluster>/
              ▼
        Object Lock + lifecycle (managed by centralized-logging module #182)
```

## Resources

| Resource | Purpose |
|---|---|
| `aws_cloudwatch_log_group.cluster` | Owns retention on the EKS-managed log group (`prevent_destroy = true`). |
| `aws_iam_role.firehose` + scoped policy | Cross-account S3 write + KMS encrypt + CloudWatch error logging. |
| `aws_kinesis_firehose_delivery_stream.this` | Buffered S3 delivery with dynamic partitioning by `userIdentity.accountId`. |
| `aws_iam_role.subscription` + policy | CloudWatch Logs → Firehose passthrough. |
| `aws_cloudwatch_log_subscription_filter.this[*]` | One per stream in `log_streams_to_forward` (default: audit + authenticator). |

## Inputs (most-used)

| Variable | Default | Purpose |
|---|---|---|
| `cluster_name` | (required) | Used in resource names + log group path. |
| `aws_region` | (required) | Used in S3 prefix construction. |
| `log_group_retention_days` | `90` | CloudWatch retention. Long-term retention is in S3. |
| `destination_s3_bucket_arn` | (required) | Output of `centralized-logging.bucket_arn` (#182). |
| `destination_s3_prefix` | `"eks-audit"` | Maps to `eks-audit` in `centralized-logging.log_source_prefixes`. |
| `destination_kms_key_arn` | (required) | Same KMS key as the destination bucket. |
| `log_streams_to_forward` | `["kube-apiserver-audit", "authenticator"]` | Streams to ship. |

## Log schema

Records arrive on S3 as gzipped newline-delimited JSON. Each line is one
CloudWatch Logs event:

```json
{
  "messageType": "DATA_MESSAGE",
  "owner": "111111111111",
  "logGroup": "/aws/eks/dev-platform/cluster",
  "logStream": "kube-apiserver-audit-...",
  "subscriptionFilters": ["dev-platform-kube-apiserver-audit-to-firehose"],
  "logEvents": [
    {
      "id": "...",
      "timestamp": 1736000000000,
      "message": "{\"kind\":\"Event\",\"apiVersion\":\"audit.k8s.io/v1\",...}"
    }
  ]
}
```

The inner `message` field is the raw EKS audit event. Downstream
consumers (Athena, OpenSearch, custom SIEM) typically extract that
field as the row payload.

## Access pattern

S3 layout:

```
s3://<log-archive-bucket>/eks-audit/AWSLogs/<account-id>/<region>/<cluster>/<year>/<month>/<day>/<hour>/<gz-file>
```

Athena query against the bucket (one-time setup of an external table
per environment):

```sql
SELECT
  audit_event.user.username,
  audit_event.verb,
  audit_event.objectRef.resource,
  audit_event.responseStatus.code
FROM eks_audit_external
WHERE
  account_id = '111111111111'
  AND region = 'eu-west-1'
  AND year = '2026' AND month = '05'
  AND audit_event.responseStatus.code >= 400
LIMIT 100;
```

The `centralized-logging` bucket policy grants this account `s3:PutObject`
to its prefix only — Firehose's IAM role uses cross-account access via
the bucket policy. Read access for forensic queries is granted separately
(typically via the security account's audit role).

## Cost

Approximate monthly cost per cluster (eu-west-1, 100-node cluster, normal
audit traffic ~50MB/day):

| Component | Volume | Cost |
|---|---|---|
| CloudWatch Logs ingestion | 1.5 GB/month | \$0.75 |
| CloudWatch Logs storage (90d) | 4.5 GB | \$0.15 |
| Firehose data ingestion | 1.5 GB | \$0.05 |
| Firehose dynamic partitioning | 1.5 GB | \$0.075 |
| S3 PUT requests | ~3000/month | \$0.02 |
| **Total** | | **~\$1-2/month/cluster** |

Long-term S3 storage is billed in the log-archive account (covered by
#182's cost estimate).

## Integration with `centralized-logging` (#182)

This module's consumer reads outputs from `centralized-logging` via a
cross-account remote-state read, e.g.:

```hcl
data "terraform_remote_state" "log_archive" {
  backend = "s3"
  config = {
    bucket = "tfstate-log-archive-eu-west-1"
    key    = "log-archive/eu-west-1/centralized-logging/terraform.tfstate"
    region = "eu-west-1"
  }
}

module "eks_log_aggregation" {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/eks-log-aggregation"

  cluster_name              = "dev-platform"
  aws_region                = "eu-west-1"
  destination_s3_bucket_arn = data.terraform_remote_state.log_archive.outputs.bucket_arn
  destination_s3_prefix     = data.terraform_remote_state.log_archive.outputs.log_source_prefixes["eks-audit"]
  destination_kms_key_arn   = "arn:aws:kms:eu-west-1:888888888888:alias/log-archive"
}
```

The cross-account state-read is read-only and goes through the bucket
policy added in #160 (DR-state PR).

## Rollback

`terraform destroy` removes the Firehose, IAM roles, subscription
filters, and the CloudWatch log group (`prevent_destroy` on the log
group will block; flip to false in a separate PR before destroy).
S3 objects already in the destination bucket remain (subject to
Object Lock retention).
