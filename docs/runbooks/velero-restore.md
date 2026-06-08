# Runbook: Velero backup & restore

Velero deploys via ArgoCD from `apps/infra/velero/` (auto-discovered by
`infra-appset.yaml`). Backups are written to a per-cluster S3 bucket with
SSE-KMS encryption, plus a cross-region DR mirror.

Closes part of issue #185.

## Backup schedule

Configured in `apps/infra/velero/values.yaml`:

| Schedule | When | TTL | Coverage |
|---|---|---|---|
| `daily-full` | 02:00 UTC every day | 30 days | All namespaces except kube-system / kube-public / kube-node-lease / velero. Cluster-scoped resources included. EBS snapshots included. |
| `weekly-full` | 03:00 UTC every Sunday | 90 days | Same coverage, longer retention. |

Per-namespace ad-hoc backups can be triggered with `velero backup create`.

## Pre-requisites

- S3 bucket: per-env override sets `velero.configuration.backupStorageLocation[*].bucket`. Recommended naming: `<env>-<region>-velero-backups`.
- KMS key: alias `alias/velero` per region. Used for SSE-KMS on the bucket.
- IAM role for service account (IRSA): `velero` ServiceAccount in the `velero` namespace, with policy permitting:
  - `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on the backup bucket
  - `ec2:*Snapshot*` for EBS volume snapshots
  - `kms:Decrypt`, `kms:Encrypt`, `kms:GenerateDataKey` on the KMS key alias

## Verifying a backup

```bash
# List schedules
velero schedule get

# List recent backups
velero backup get | head -10

# Inspect a specific backup
velero backup describe <backup-name> --details
velero backup logs <backup-name> | less
```

## Restoring

### 1. List candidates
```bash
velero backup get | grep -i <namespace-or-app>
```

### 2. Dry-run a restore
```bash
velero restore create \
  --from-backup <backup-name> \
  --namespace-mappings prod-ns:restore-test-ns \
  --dry-run
```

### 3. Execute the restore

For a **single namespace**:
```bash
velero restore create restore-$(date +%s) \
  --from-backup <backup-name> \
  --include-namespaces prod-ns \
  --restore-volumes=true
```

For a **specific resource**:
```bash
velero restore create restore-$(date +%s) \
  --from-backup <backup-name> \
  --include-resources deployments,services,persistentvolumeclaims \
  --include-namespaces prod-ns
```

For a **whole-cluster DR restore** (rare, escalation only):
```bash
velero restore create disaster-recovery-$(date +%s) \
  --from-backup <weekly-or-daily-backup> \
  --restore-volumes=true \
  --existing-resource-policy=update
```

### 4. Verify restore progress
```bash
velero restore describe restore-<id> --details
velero restore logs restore-<id> | less
```

Restored objects appear in the target namespaces; PV claims are bound to
new EBS volumes from snapshots.

## Cross-region DR scenario

Primary backup bucket: `<env>-<primary-region>-velero-backups`
DR mirror bucket: `<env>-<dr-region>-velero-backups`
Both have SSE-KMS encryption (different per-region keys).

To restore in the DR region after a primary-region outage:
1. Re-deploy the EKS cluster in the DR region (per the EKS DR runbook).
2. Configure Velero in the DR cluster to point at the DR bucket
   (`backupStorageLocation[1]` in the chart).
3. Run a `velero restore create` against a backup labelled `aws-dr`.

## Failure modes

### "Backups are stuck in `InProgress`"
- Check Velero pod logs: `kubectl -n velero logs deploy/velero | grep -i error`.
- Common cause: IRSA role missing `kms:GenerateDataKey` on the KMS alias.
- Verify with: `aws iam simulate-principal-policy --policy-source-arn <role-arn> --action-names kms:GenerateDataKey`.

### "Restore fails with `volumesnapshotcontents` not found"
- The CSI plugin requires the `EnableCSI` feature flag (already set in
  values.yaml under `configuration.features`).
- If still failing, the source-cluster's CSI driver version must match
  the destination-cluster's. Re-run with `--exclude-resources volumesnapshotcontents`
  to skip the CSI step and rely on filesystem-only backup.

### "Backup TTL expired before I could restore"
- Default `daily-full` TTL is 30 days; `weekly-full` 90 days. For
  long-term retention, create a one-off backup with extended TTL:
  ```bash
  velero backup create archive-$(date +%Y%m%d) --include-namespaces=<ns> --ttl=8760h
  ```
- 8760h = 1 year.

## Cost

Velero itself: free. Underlying costs:
- S3 storage: ~\$0.023/GB-month for STANDARD; ~\$0.004/GB-month for GLACIER.
- EBS snapshots: ~\$0.05/GB-month.
- KMS API calls: ~\$0.03 per 10,000 requests.

For a typical 100-pod cluster with 500GB of PV data and daily backups
(30-day rolling window, weekly 90-day retention): ~\$30-50/month per
cluster.

## References

- Issue #185
- Velero docs: <https://velero.io/docs/v1.15/>
- `apps/infra/velero/values.yaml`
- `apps/infra/velero/Chart.yaml`
- KMS key alias provisioned by `terraform/modules/kms` (`_envcommon/kms.hcl`).
