# Velero - Kubernetes Backup and Disaster Recovery

Velero provides backup, restore, and disaster recovery for Kubernetes clusters.

## Features

- **Scheduled backups** - Daily and weekly automated backups
- **On-demand backups** - Manual backup creation
- **Namespace filtering** - Include/exclude specific namespaces
- **Volume snapshots** - EBS snapshot integration via CSI
- **Cluster migration** - Move workloads between clusters
- **Disaster recovery** - Restore from S3 backups

## Prerequisites

1. **S3 Bucket** for backup storage
2. **IAM Role** with Velero permissions
3. **Pod Identity** or IRSA configured

### IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVolumes",
        "ec2:DescribeSnapshots",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::YOUR-BUCKET/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::YOUR-BUCKET"
    }
  ]
}
```

## Installation

```bash
# Install with required values
helm install velero . \
  -n velero \
  --create-namespace \
  --set configuration.backupStorageLocation[0].bucket=my-backup-bucket \
  --set configuration.backupStorageLocation[0].config.region=us-east-1
```

## Usage

### Create On-Demand Backup

```bash
# Backup all namespaces
velero backup create my-backup

# Backup specific namespace
velero backup create my-backup --include-namespaces production

# Backup with volume snapshots
velero backup create my-backup --snapshot-volumes
```

### List Backups

```bash
velero backup get
velero backup describe my-backup
```

### Restore from Backup

```bash
# Full restore
velero restore create --from-backup my-backup

# Restore specific namespace
velero restore create --from-backup my-backup --include-namespaces production

# Restore to different namespace
velero restore create --from-backup my-backup --namespace-mappings old-ns:new-ns
```

### Check Scheduled Backups

```bash
velero schedule get
velero schedule describe daily-full
```

## Default Schedules

| Schedule | Cron | Retention | Description |
|----------|------|-----------|-------------|
| daily-full | `0 2 * * *` | 30 days | All namespaces except system |
| weekly-full | `0 3 * * 0` | 90 days | All namespaces except system |

## Monitoring

ServiceMonitor is enabled for Prometheus scraping.

Key metrics:
- `velero_backup_total` - Total backup count
- `velero_backup_success_total` - Successful backups
- `velero_backup_failure_total` - Failed backups
- `velero_restore_total` - Total restores

## Troubleshooting

```bash
# Check Velero logs
kubectl logs -n velero -l app.kubernetes.io/name=velero

# Check backup status
velero backup logs my-backup

# Check node agent (for file system backups)
kubectl logs -n velero -l name=node-agent
```

## Disaster Recovery Runbook

1. **Identify the incident** - Determine scope of data loss
2. **List available backups** - `velero backup get`
3. **Select appropriate backup** - Choose based on timestamp and scope
4. **Perform restore** - `velero restore create --from-backup <backup-name>`
5. **Verify restore** - Check pods, services, and data integrity
6. **Document incident** - Record timeline and actions taken
