# Runbook: ML-Platform DC Failover — Bare-Metal (Talos UK DCs)

> **Scope (WS-E):** the **ML-platform view** of a UK-DC failover on the owned Talos
> estate — what happens to **GPU serving**, **in-flight training**, **MLflow/registry
> state**, and the **Talos control plane** when the primary DC is lost. This is a thin
> companion to the authoritative trading-platform
> [DC-failover runbook](uk-dc-failover.md) (data tiers, RPO/RTO, QuestDB/PG/Iceberg) —
> **follow that for the data-plane failover**; this doc covers only the ML-platform
> and Talos-cluster decisions layered on top.
>
> **Reuse, don't reinvent:** failover is driven by the existing
> [`failover-controller/`](../../failover-controller/) (Go, raft, anti-split-brain) +
> [`dns-monitor/`](../../dns-monitor/) — WS-E adds **no new failover machinery**
> (ADR-0049 §7 decision 8: independent per-DC clusters + DNS/health failover, NOT a
> stretched ClusterMesh).
>
> **Targets (from the trading runbook):** RPO < 60 s; RTO < 15 min planned / < 30 min
> unplanned. **SOC2 evidence:** CC7.4 / A1.2 / A1.3 in the
> [bare-metal SOC2 matrix](../compliance/soc2-control-matrix-baremetal.md); the
> quarterly DR drill runs per the SOC2 CC-series (UK doc).
>
> **ADRs:** ADR-0049 (multi-DC foundation), ADR-0052 (Rook-Ceph/MinIO replication),
> ADR-0054 (elasticity — training is DC-pinned), ADR-0040 (on-call, reused).

## 1. The load-bearing rule

| Workload class | Failover behaviour |
|---|---|
| **GPU serving** (vLLM / inference) | **Fails over.** `failover-controller` promotes the standby DC; `dns-monitor` repoints the serving VIP. Standby is sized ~40% (UK doc) to absorb the serving load, not to co-work. |
| **In-flight training / eval** (gang-scheduled GPU jobs) | **NOT migrated.** Gang-scheduled jobs are not safely relocatable (ADR-0054, same rule as ADR-0036 D5). They are **DC-pinned and re-queued** on recovery — checkpoint-resume from the last MLflow/MinIO checkpoint, not live-migrated. |
| **MLflow / registry state** | Reads fail over (Postgres streaming replica + MinIO site-replication / Ceph-RGW). Writes resume on the promoted DC. |
| **Talos control plane** | Each DC runs its **own** control plane + etcd (independent clusters). No cross-DC quorum to lose; the standby cluster is already up. |

## 2. Pre-failover verification (ML-platform additions)

Do the [trading runbook §3 data checks](uk-dc-failover.md#3-replication--site-replication-verification) first, then:

```bash
# MinIO site-replication / Ceph-RGW object lag for the MLflow artifact bucket.
mc admin replicate status uk-primary/ uk-standby/ --json | jq '.maxLag'

# Standby Talos cluster + GPU pool ready to absorb serving?
kubectl --context talos-uk-standby get nodes -l nvidia.com/gpu.present=true \
  -o custom-columns=NODE:.metadata.name,READY:.status.conditions[-1].type

# Standby KubePrism / API reachable (the standby cluster must already be healthy).
kubectl --context talos-uk-standby get --raw='/readyz?verbose'
```

*Criteria:* artifact replication lag < 60 s; standby GPU pool Ready; standby API `ok`.

## 3. Failover (ML-platform steps)

> The `failover-controller` performs the promotion + DNS cutover. These are the
> **ML-platform-specific** actions around it — none are `apply` against this mock; in
> a real incident they run under the on-call's authority.

1. **Acknowledge** the PagerDuty incident (`platform-oncall` + `ml-pipeline`).
2. Let `failover-controller` promote standby + `dns-monitor` repoint serving VIPs
   (do **not** hand-edit DNS — anti-split-brain raft owns it).
3. **Drain the dead DC's training queue intent:** mark the primary's in-flight
   `training-*` PodGroups as re-queue-on-recovery (they are lost, not migrated). Record
   which jobs to resume.
4. **Point the in-DC Airflow + MLflow** at the standby Postgres replica (now primary)
   and the standby MinIO/Ceph-RGW endpoint. Serving + registry reads resume.
5. **Verify serving** on the standby DC (a canary inference request returns); confirm
   `platform.system=ml-pipeline` dashboards are green on the standby.

## 4. Failback

1. Restore the primary DC's Talos cluster (re-image via Cluster-API/Sidero if needed).
2. Reverse MinIO/Ceph + Postgres replication direction; verify lag < 60 s.
3. **Re-queue the training jobs** captured in step 3 above onto the primary's
   `training-default` queue (checkpoint-resume from MLflow/MinIO).
4. Cut serving back via `failover-controller` (planned failback, RTO < 15 min).

## 5. DR drill (SOC2 A1.3 evidence)

Run quarterly per the SOC2 CC-series (UK doc). The drill exercises: replication-lag
verification, a controlled `failover-controller` promotion to standby, a canary
serving request on standby, a training-job re-queue, and failback. Record the drill in
the [on-call runbook](oncall-rotation-escalation.md) tabletop log — this is the CC7.4 /
A1.3 evidence cited in the [SOC2 matrix](../compliance/soc2-control-matrix-baremetal.md).
