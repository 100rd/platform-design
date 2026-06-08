# Runbook: Terraform state-backend regional failover

**Severity**: P1 (deploy capability is degraded but no production traffic
is impacted directly).
**Audience**: Platform on-call.
**Trigger**: AWS region containing the primary state bucket
(`tfstate-<account>-<primary_region>`) is unavailable for terraform reads or
writes for >15 minutes.

This runbook covers the case where a regional outage in the **primary**
state region (default `eu-west-1`) prevents `terragrunt init/plan/apply`. It
fails over to the DR replica created by the `state-backend-dr` module
(default DR region `eu-central-1`).

---

## Pre-conditions

- The DR replica was provisioned via `state-backend-dr` (PR #160 / issue
  #160) and has been actively replicating for >24h.
- You have IAM access to the affected account in the DR region.
- You can reach github.com to push a config change.

---

## Decision tree

1. **Is it actually a regional outage?**
   - Check [AWS Health Dashboard](https://health.aws.amazon.com/health/home).
   - Try `aws s3 ls "s3://tfstate-<account>-eu-west-1" --region eu-west-1`.
   - If it fails for >15 min and the dashboard confirms eu-west-1 S3 or DDB
     impairment, proceed.
   - If only one service is impacted (e.g. S3 fine, DDB degraded), see
     "Partial-outage" below.
2. **Is the DR replica healthy?**
   - `aws s3 ls "s3://tfstate-<account>-eu-central-1" --region eu-central-1`
     should list current state files with mtimes within the last few minutes
     (matching the SLA of S3 cross-region replication, typically <15 min).
   - `aws dynamodb describe-table --table-name "terraform-locks-<account>"
     --region eu-central-1` should return `TableStatus = ACTIVE` and show
     `Replicas` containing both regions.
3. **Are there active terraform runs?** Coordinate stop with anyone running
   plan/apply pipelines. Once you flip the backend, runs against the old
   region will fail and may leave stale locks.

---

## Failover steps

### 1. Update terragrunt/root.hcl

In a feature branch:

```hcl
# terragrunt/root.hcl
remote_state {
  backend = "s3"
  ...
  config = {
    bucket = "tfstate-${local.account_name}-eu-central-1"   # was -eu-west-1
    region = "eu-central-1"                                  # was eu-west-1
    ...
    dynamodb_table = "terraform-locks-${local.account_name}" # unchanged — Global Table
  }
}
```

The DDB lock table name does not change because the replica is part of a
DDB Global Table and the writeable endpoint is per-region. Terragrunt picks
up the right regional endpoint via the `region` field.

### 2. Open a PR titled "incident: failover state to <dr-region>"

- Body should reference the AWS Health Dashboard event ID and the time of
  outage detection.
- Tag platform on-call as reviewers.
- Merge with the explicit knowledge that this is an emergency path. A
  follow-up PR will revert it during recovery.

### 3. Verify failover

After merge:

```bash
# Pick any unit and run plan
cd terragrunt/dev/eu-west-1/some-unit
terragrunt plan
```

`init` should reconfigure the backend automatically (Terragrunt always
regenerates `backend.tf` via `if_exists = "overwrite_terragrunt"`). Plan
should succeed against the replica.

### 4. Note locks

If there were locks held in the primary region's DDB at the time of outage,
they appear in the replica too (Global Tables are bidirectionally
replicated). Stale locks block new operations. Identify them:

```bash
aws dynamodb scan --table-name terraform-locks-<account> \
  --region eu-central-1 \
  --query 'Items[*].LockID.S'
```

If a lock is genuinely orphaned (the holder has crashed and is not coming
back), force-unlock with the lock ID printed by `terragrunt`:

```bash
terragrunt force-unlock <LOCK_ID>
```

Document every force-unlock in the incident channel.

---

## Recovery: failing back to primary region

When the primary region recovers:

1. Confirm `aws s3 ls "s3://tfstate-<account>-eu-west-1" --region eu-west-1`
   works again.
2. **Sync writes-during-outage** back to primary. Replication is one-way
   (replica is the read-only side during normal ops). Anything written to
   the replica during failover is NOT auto-replicated back:

   ```bash
   aws s3 sync \
     "s3://tfstate-<account>-eu-central-1/" \
     "s3://tfstate-<account>-eu-west-1/" \
     --source-region eu-central-1 \
     --region eu-west-1 \
     --copy-props metadata-directive
   ```

   Spot-check version histories on a few critical state files to confirm
   no divergence.
3. **Open a fail-back PR** that reverts step 1 of the failover (point
   `bucket` and `region` back to the primary). Title:
   `incident: revert state failover, primary <region> healthy`.
4. After merge, run `terragrunt plan` against any unit to confirm
   `init -reconfigure` picks up the primary again.
5. Inspect `aws_dynamodb_table_replica.locks_dr` — if the table replica
   remained healthy throughout, no action needed. If anything looks off
   (table status not ACTIVE), open a follow-up incident.

---

## Partial-outage scenarios

| Symptom | Action |
|---|---|
| S3 in primary works, DDB does not | DDB Global Tables are active-active; Terragrunt will use the regional DDB endpoint specified in `region`. Temporarily flip ONLY the `region` field on the lock table side (custom override) — but in practice, since both come from `region`, do the full failover. |
| DDB works, S3 control plane partially degraded | Wait. Terragrunt retries are configured (`retry_max_attempts = 3` in root.hcl). Most partial S3 control-plane degradations clear within an hour without action. |
| S3 data plane returns 5xx for a single bucket | Check bucket policy + replication status. Could be a misconfiguration, not an outage. |

---

## What NOT to do

- **Do not** run `aws s3 rb` or `aws dynamodb delete-table` on either
  side. Both have `prevent_destroy = true` in Terraform; manual deletion
  would orphan terraform state and require an emergency restore from S3
  versions.
- **Do not** disable replication on the primary bucket "to avoid
  conflicts." Replication is what populated the replica in the first
  place; turning it off mid-incident breaks the recovery path.
- **Do not** create a new bucket and copy state into it under a different
  name. The bucket name is load-bearing in `terragrunt/root.hcl`. Match
  the naming convention exactly.

---

## Post-incident checklist

- [ ] Fail-back PR merged.
- [ ] Spot-check confirms no state divergence between primary and replica.
- [ ] Replication metrics back to baseline (delta < 60s).
- [ ] All force-unlocks documented in the incident report.
- [ ] If RTO/RPO targets were missed, file a follow-up to investigate
      replication lag root cause.
- [ ] Update this runbook with anything that surprised you.

---

## Related docs

- [`terraform/modules/state-backend-dr/README.md`](../../terraform/modules/state-backend-dr/README.md)
- [`terraform/modules/state-backend/README.md`](../../terraform/modules/state-backend/README.md)
- [`bootstrap/state-backend/README.md`](../../bootstrap/state-backend/README.md)
- [AWS S3 cross-region replication docs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [DynamoDB Global Tables v2](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html)
