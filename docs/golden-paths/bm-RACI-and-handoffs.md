# RACI and Handoffs: Bare-Metal Production Model Lifecycle

**Document scope:** end-to-end lifecycle for a new ML model (or pipeline, dashboard,
or tenant) from raw data to monitored production on the **owned bare-metal UK DC
cluster** (Talos Linux, two DCs, ADR-0049..0054). This is the bare-metal supplement
to `docs/golden-paths/RACI-and-handoffs.md` — read both. Where they differ, this
document takes precedence for bare-metal deployments.

**Related ADRs:** ADR-0041 (WS-F golden paths), ADR-0037 (WS-B ML CI/CD + MLflow
re-targeted at MinIO/Ceph-RGW), ADR-0038 (WS-C drift monitoring, reused), ADR-0039
(WS-D self-serve observability, reused + BM panels), ADR-0040 (WS-E SOC posture +
on-call, reused), ADR-0049..0054 (BM foundation).

**MOCK/emulation repo — apply-gated.** Nothing in this document implies a live
`helm install`, `terraform apply`, `talosctl apply-config`, or cluster mutation
without explicit human approval and blast-radius review.

---

## 1. Personas

| ID | Persona | Responsibility scope (bare-metal additions in italics) |
|----|---------|------------------------------------------------------|
| DE | **Data Engineering** | Feature pipelines, Iceberg snapshot management, data quality, reference dataset curation; UK data residency checks (ADR-0052) |
| ML | **ML Engineering** | Model training, evaluation, MLflow registry (CloudNativePG + MinIO/Ceph-RGW backend), DAG authorship, VolcanoJob queue selection, adapter packaging |
| BE | **Backend / Frontend** | API integration, inference client, contract implementation, latency budgets, BM addendum sign-off |
| PL | **Platform / SRE** | Infrastructure GitOps, observability stack, on-call, incident command, Talos cluster lifecycle, etcd backups, BGP fabric, Ceph health, Vault KMS |

---

## 2. RACI matrix

**Key:** R = Responsible . A = Accountable . C = Consulted . I = Informed

### 2a. Feature pipeline and data

| Activity | DE | ML | BE | PL |
|----------|----|----|----|-----|
| A1 Feature pipeline: design schema + Iceberg namespace | R/A | C | C | I |
| A2 Feature pipeline: implement + deploy snapshot | R/A | C | I | C |
| A3 Feature pipeline: verify UK data residency (MinIO/Ceph-RGW, no external S3) | R/A | C | I | C |
| A4 Feature pipeline: validate reference dataset quality | R/A | C | I | I |

### 2b. Model training and registration (BM-specific: VolcanoJob + MinIO backend)

| Activity | DE | ML | BE | PL |
|----------|----|----|----|-----|
| B1 Configure Airflow DAG; select Volcano queue (H100/H200 taxonomy) | C | R/A | I | C |
| B2 Run `ml-pipeline-baremetal.yml` (VolcanoJob on selected queue) | I | R/A | I | C |
| B3 MLflow registration + cosign sign (artifact_uri s3:// in-DC) | I | R/A | I | C |
| B4 Author model contract instance (base + BM addendum, ADR-0052/0053) | C | R/A | C | I |
| B5 Contract sign-off: all four personas before staging promotion | C | A | R (BE) | C (PL) |

### 2c. Drift and accuracy monitoring (WS-C, cluster-agnostic reuse)

| Activity | DE | ML | BE | PL |
|----------|----|----|----|-----|
| C1 Configure drift-exporter with in-DC s3Endpoint (MinIO/Ceph-RGW) | I | R | I | A |
| C2 Set drift alert thresholds (`bm-new-model-service` values) | I | R | I | A |
| C3 Drift alert fires: acknowledge + classify | I | R | I | A |
| C4 Drift alert fires: trigger retrain or escalate | I | R/A | I | C |

### 2d. Serving and API

| Activity | DE | ML | BE | PL |
|----------|----|----|----|-----|
| D1 Implement inference client (target: Cilium BGP VIP, ADR-0051) | I | C | R/A | I |
| D2 Integrate request_id / OTel tracing | I | I | R/A | C |
| D3 Validate SLO targets (p50/p99/error rate + NCCL floor, BM addendum) | I | C | R/A | C |

### 2e. On-call: bare-metal additions (Talos / etcd / fabric / Ceph / BGP)

| Activity | DE | ML | BE | PL |
|----------|----|----|----|-----|
| E1 Platform infra alert fires (any: node/etcd/BGP/Ceph/DCGM) | I | I | I | R/A |
| E2 Model accuracy/drift alert fires | I | R/A | I | C |
| E3 Incident declared (P0/P1) | I | C | C | R/A |
| E4 Post-incident review + runbook update | C | C | C | R/A |
| E5 Talos node lifecycle event (re-image, upgrade, MachineConfig change) | I | I | I | R/A |
| E6 etcd health check + snapshot before control-plane change | I | I | I | R/A |
| E7 BGP session flap: hold-timer / max-prefix triage (ADR-0051) | I | I | I | R/A |
| E8 Ceph HEALTH_WARN/HEALTH_ERR triage + OSD rebalance | I | I | I | R/A |
| E9 NCCL all-reduce bandwidth drops below contract floor | I | R/A | I | C |

### 2f. Tenant onboarding (bare-metal only, no GCP/AWS equivalent)

| Activity | DE | ML | BE | PL |
|----------|----|----|----|-----|
| F1 New tenant: request with metadata (tier, queues, Iceberg prefixes) | C | C | C | R/A |
| F2 New tenant: `bm-new-tenant` golden path PR (helm-values.yaml) | I | I | I | R/A |
| F3 New tenant: first `helm upgrade --install charts/tenant-bootstrap/` (apply-gated) | I | I | I | R/A |
| F4 New tenant: verify Vault KMS key, Gatekeeper constraints, Kafka ACLs | I | I | I | R/A |
| F5 New tenant: hand over namespace + credentials to requesting team | I | I | I | R/A |

### Gap resolution rules

- **B5 sign-off blocks staging promotion.** The `ml-pipeline-baremetal.yml` `deploy`
  job environment gate (`environment: staging`) requires the contract sign-off (base +
  BM addendum) to be documented in the PR description before reviewer approval.
  Platform/SRE must confirm the Vault KMS key at `dataResidency.kmsKeyRef` exists.
- **C4 retrain decision.** ML Engineering decides whether to trigger a retrain
  (`trigger_reason: drift`) or escalate to Platform if the in-DC Airflow is
  unreachable. Platform/SRE checks the Airflow pod on the CPU pool.
- **E5 Talos lifecycle gating.** Every control-plane `MachineConfig` change or Talos
  upgrade requires: (a) etcd snapshot + verify, (b) quorum check, (c) stage on
  standby DC first. Platform/SRE owns this gate; no other persona may initiate it.
- **E9 NCCL floor breach.** If the NCCL all-reduce bandwidth test falls below the
  contract floor (`gpuFabric.nccAllReduceMinBandwidthGbs`), training jobs must NOT
  be promoted to the `training-urgent` queue. ML Engineering and Platform/SRE
  co-own the gate per `ai-sre/knowledge/nccl-troubleshooting.md`.

---

## 3. Handoff flow (bare-metal substrate)

Key differences from the GCP/cloud handoff in `RACI-and-handoffs.md`:
- `ml-pipeline-baremetal.yml` replaces `ml-pipeline.yml`
- VolcanoJob (H100/H200 queue) replaces KubernetesPodOperator / GKE pod
- `artifact_uri: s3://` (MinIO/Ceph-RGW in-DC) replaces `gs://`
- BM contract addendum sign-off is an additional gate at H5
- Talos lifecycle gates (etcd snapshot, quorum check) added at T1/T2

```
Data Engineering              ML Engineering             Backend/Frontend      Platform/SRE
     |                              |                           |                    |
─── Feature pipeline ──────────────────────────────────────────────────────────────────────
     |                              |                           |                    |
[H1] Freeze Iceberg snapshot ──────>|                           |                    |
     | (train_domain_adapter.py:    |                           |                    |
     |  freeze_snapshot() +         |                           |                    |
     |  verify UK residency --      |                           |                    |
     |  s3:// in-DC only)           |                           |                    |
─── Tenant provisioned (bm-new-tenant) ─────────────────────────────────────────────────
     |                              |                           |              [F3] helm install
     |                              |                           |              charts/tenant-bootstrap/
     |                              |                           |              (apply-gated; PL only)
─── Model training -- bare-metal (WS-B) ────────────────────────────────────────────────
     |                         [H2] ml-pipeline-baremetal.yml  |                    |
     |                              | POST Airflow              |                    |
     |                              |  train_domain_adapter/    |                    |
     |                              |  dagRuns                  |                    |
     |                              | VolcanoJob on H100 queue  |                    |
     |                              | (training-default /       |                    |
     |                              |  training-urgent etc.)    |                    |
     |                         [H3] eval_adapter_debate VolcanoJob (eval-judge H200) |
     |                              | win_rate >= 0.55 gate     |                    |
     |                         [H4] Register in MLflow ──────────────────────────── >|
     |                              | artifact_uri: s3://       |                    |
     |                              |  ml-artifacts-<tenant>/   |                    |
     |                              |  <model>/<git-sha>        |                    |
     |                              | cosign sign + SBOM        |                    |
─── Contract sign-off (BM addendum required) ──────────────────────────────────────────
     |                         [H5] Contract instance PR ──────>| BE sign-off       |
     |                              | base contract +           |                    | PL sign-off
     |                              | bm addendum (volcanoQueue |                    | (Vault KMS
     |                              | gpuFabric, dataResidency) |                    |  confirmed)
─── Staging promotion ─────────────────────────────────────────────────────────────────
     |                         [H6] Kargo: dev (auto) ─────────────────────────────>|
     |                         [H7] Kargo: staging (reviewer gate) ────────────────>|
─── Production deployment ─────────────────────────────────────────────────────────────
     |                         [H8] Kargo: prod (manual gate) ─────────────────────>|
─── Drift monitoring (WS-C/D) ──────────────────────────────────────────────────────────
     |                              |              WS-C drift-exporter               |
     |                              |              s3Endpoint: in-DC MinIO/Ceph-RGW  |
     |                              |              cluster_substrate="baremetal-uk"  |
─── Retrain trigger (WS-C -> WS-B) ─────────────────────────────────────────────────────
     |                         [H9] Drift alert fires ──────────────────────────── >|
     |                              | Alertmanager -> Airflow REST                   |
     |                              | POST train_domain_adapter/dagRuns              |
     |                              | conf: {trigger_reason: "drift"}               |
─── Talos lifecycle gates (bare-metal only) ────────────────────────────────────────────
     |                              |                           |             [T1] etcd snapshot
     |                              |                           |             + verify (before
     |                              |                           |             MachineConfig/upgrade)
     |                              |                           |             [T2] Stage standby DC
     |                              |                           |             before primary
```

### Handoff summary table

| ID | Artifact handed off | From | To | Gate / mechanism |
|----|--------------------|----|-----|-----------------|
| H1 | Iceberg snapshot (frozen, UK-resident, s3:// in-DC) | DE | ML | `freeze_snapshot()` task; s3Endpoint validated |
| H2 | VolcanoJob training run (H100 queue) | ML | ML (eval) | Airflow `TriggerDagRunOperator`; queue per contract |
| H3 | Eval report (win_rate, p95_distance) | ML (eval) | ML (register) | Quality gate: `win_rate >= 0.55` |
| H4 | Signed model artifact + SBOM (s3:// in-DC) | ML | BE + PL | MLflow registry (Staging) + cosign; artifact in MinIO/Ceph-RGW |
| H5 | Contract instance YAML (base + BM addendum) | ML | BE + PL | PR to `docs/contracts/`; BE + PL sign-off; Vault KMS confirmed |
| H6 | Staged deploy (dev) | ML | PL | Kargo auto-promotion |
| H7 | Staged deploy (staging) | ML | PL | Kargo reviewer gate |
| H8 | Staged deploy (prod) | PL | BE/all | Kargo manual gate; PL confirms BM cluster health |
| H9 | Drift alert (Alertmanager) | PL (infra) | ML | Alertmanager webhook -> Airflow REST; `trigger_reason: drift` |
| T1 | etcd snapshot + verify | PL | PL | Gate before any control-plane MachineConfig or Talos upgrade |
| T2 | Standby DC smoke test | PL | PL | Stage on standby before primary; per `uk-dc-failover-baremetal.md` |

---

## 4. On-call and escalation (bare-metal additions)

Supplements `docs/runbooks/ml-incident-runbook-baremetal.md` and
`docs/runbooks/uk-dc-failover-baremetal.md` (both WS-E deliverables).

### Alert routing table

| Alert | First paged | Ack SLA | First action | Escalate to | Escalate after |
|-------|------------|---------|--------------|-------------|----------------|
| `AirflowDagRunFailed` | ML on-call | 15 min | Check Airflow pod (CPU pool) -> retry DAG | PL if pod down | 30 min |
| `MLModelDriftHigh` (drift > 0.4) | ML on-call | 15 min | Evidently report -> trigger retrain | PL if Airflow down | 30 min |
| `MLModelAccuracyLow` (< 0.75) | ML on-call | 15 min | MLflow eval metrics -> ArgoCD rollback | PL for Kargo rollback | 30 min |
| `MLflowTrackingDown` | PL on-call | 5 min | MLflow pod + CloudNativePG -> ArgoCD sync | P1 if pipeline blocked | 15 min |
| `NcclBandwidthBelowFloor` | PL on-call | 5 min | `nccl-troubleshooting.md` pre-flight; pause training-urgent queue | Incident if all H100 affected | 15 min |
| `TalosNodeUnhealthy` | PL on-call | 5 min | `talosctl health`; DCGM auto-taint check | Incident if >1 node | 10 min |
| `EtcdLeaderElection` | PL on-call | 5 min | Check etcd logs; verify quorum; pause control-plane changes | P0 if quorum lost | 5 min |
| `CiliumBgpSessionDown` | PL on-call | 5 min | `cilium-bgp-issues.md`; hold-timer + ToR peer | Incident if VIPs unreachable | 10 min |
| `CephHealthWarn` | PL on-call | 10 min | `ceph status`; OSD rebalance watch | Incident if HEALTH_ERR | 15 min |
| `CephHealthError` | PL on-call | 5 min | OSD repair; Rook-Ceph mgr | P0 if data unavailable | 5 min |
| `DCPrimaryDown` | PL on-call | 5 min | `uk-dc-failover-baremetal.md`; failover-controller promote standby | P0 (auto if health-check fails) | 5 min |

### Escalation path

```
BM platform alert fires
    |
    v
Platform / SRE on-call  (PagerDuty: platform-oncall)
    |  > 15 min unresolved OR customer impact confirmed
    v
Incident Commander (Platform lead or on-call manager)
    |  P0 declared (full outage / data loss / DC failover)
    v
Engineering Manager + Comms + (if DC failover) DC operations contact

ML alert fires
    |
    v
ML Engineering on-call  (PagerDuty: ml-platform-oncall)
    |  > 30 min unresolved OR infra cause confirmed
    v
Platform / SRE on-call
    |  P0 declared
    v
Incident Commander
```

---

## 5. Golden-path selection guide

| Task | Golden path | Key gate |
|------|------------|---------|
| Onboard a new tenant (namespace, Vault KMS, Kafka ACLs, MinIO bucket) | `bm-new-tenant` | Platform lead approval (apply-gated F3) |
| Register a new ML model service (train->eval->register->deploy) | `bm-new-model-service` | B5 contract sign-off (base + BM addendum) |
| Add a new Airflow DAG / batch pipeline (non-canonical) | `bm-new-ml-pipeline` | B5 contract sign-off if model involved; PL for Volcano quota |
| Onboard a team to self-serve observability (Grafana folder + alerts) | `bm-new-dashboard` | PL review of PrometheusRule RBAC |
| Any of the above on GCP or AWS | `templates/golden-paths/new-*` (non-BM paths) | Per `docs/golden-paths/RACI-and-handoffs.md` |

---

## 6. ADR-0034 revisit criteria (Backstage, bare-metal)

Backstage (ADR-0034 deferred) revisit conditions for the bare-metal track:

1. BM ML platform (WS-A..E applied and stable in the primary UK DC).
2. A dedicated Backstage owner assigned with BM cluster knowledge.
3. Three or more tenants onboarded via `bm-new-tenant` + at least one via
   `bm-new-model-service`.
4. The `bm-RACI-and-handoffs.md` process exercised in at least one tabletop DR
   drill per ADR-0040 + WS-E quarterly-DR requirement.

Current status: all four conditions pending (BM cluster is plan/validate-only;
WS-A..E are design-only at this stage).

---

## 7. References

- `docs/golden-paths/RACI-and-handoffs.md` (GCP/cloud base RACI)
- `docs/adrs/0041-golden-paths-collaboration.md` (WS-F decision of record)
- `docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md` (BM foundation)
- `docs/adrs/0050-talos-gpu-driver-system-extensions.md` (GPU driver)
- `docs/adrs/0051-baremetal-networking-cilium-lb-bgp.md` (Cilium BGP LB)
- `docs/adrs/0052-baremetal-storage-rook-ceph.md` (MinIO/Ceph-RGW)
- `docs/adrs/0053-baremetal-gpu-fabric-roce-infiniband.md` (IB fabric SLO)
- `docs/adrs/0054-baremetal-elasticity-node-lifecycle.md` (Volcano queues)
- `docs/adrs/0037-ml-cicd-pipeline-mlflow.md` (WS-B, re-targeted at BM)
- `docs/adrs/0038-ml-observability-drift.md` (WS-C, reused)
- `docs/adrs/0039-self-serve-observability.md` (WS-D, reused + BM panels)
- `docs/adrs/0040-soc-posture-and-oncall.md` (WS-E, on-call + Vault KMS)
- `docs/contracts/model-api-contract.md` (base contract spec)
- `docs/contracts/bm-model-api-contract-addendum.md` (BM addendum)
- `docs/runbooks/ml-incident-runbook-baremetal.md` (WS-E)
- `docs/runbooks/uk-dc-failover-baremetal.md` (WS-E)
- `docs/transaction-analytics/06-uk-datacenters.md` (UK DC design fiction)
- `ai-sre/knowledge/nccl-troubleshooting.md` (NCCL all-reduce acceptance gate)
- `ai-sre/knowledge/cilium-bgp-issues.md` (BGP session triage)
- `ai-sre/knowledge/gpu-driver-updates.md` (GPU driver update checklist)
- `charts/tenant-bootstrap/` (Helm chart for bm-new-tenant)
- `templates/golden-paths/bm-new-model-service/` (model service golden path)
- `templates/golden-paths/bm-new-ml-pipeline/` (Airflow DAG golden path)
- `templates/golden-paths/bm-new-dashboard/` (team dashboard golden path)
- `templates/golden-paths/bm-new-tenant/` (tenant onboarding golden path)
- `.claude/rules/critical-decisions.md` (apply-gated approval gates)
