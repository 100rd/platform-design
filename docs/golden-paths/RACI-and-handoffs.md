# RACI and Handoffs: Production Model Lifecycle

**Document scope:** the end-to-end lifecycle for a new ML model from raw data to
monitored production, covering the four engineering personas and the five lifecycle
activities. This supplements the ADR-0040 ML-incident runbooks with a day-1
ownership model.

**Related ADRs:** ADR-0037 (WS-B), ADR-0038 (WS-C), ADR-0039 (WS-D),
ADR-0040 (WS-E on-call), ADR-0041 (WS-F, this document).

---

## 1. Personas

| ID | Persona | Responsibility scope |
|----|---------|---------------------|
| DE | **Data Engineering** | Feature pipelines, Iceberg snapshot management, data quality, reference dataset curation |
| ML | **ML Engineering** | Model training, evaluation, MLflow registry, DAG authorship, adapter packaging |
| BE | **Backend / Frontend** | API integration, inference client, contract implementation, latency budgets |
| PL | **Platform / SRE** | Infrastructure, GitOps delivery, observability stack, on-call, incident command |

---

## 2. RACI matrix

**Key:** R = Responsible (does the work) · A = Accountable (owns the outcome) ·
C = Consulted (input required) · I = Informed (notified)

| Activity | DE | ML | BE | PL |
|----------|----|----|----|-----|
| **A1 — Feature pipeline: design schema** | R/A | C | C | I |
| **A2 — Feature pipeline: implement + deploy Iceberg snapshot** | R/A | C | I | C |
| **A3 — Feature pipeline: validate reference dataset quality** | R/A | C | I | I |
| **B1 — Model training: configure Airflow DAG** | C | R/A | I | C |
| **B2 — Model training: run train→eval pipeline (ml-pipeline.yml)** | I | R/A | I | C |
| **B3 — Model training: MLflow registration + cosign sign** | I | R/A | I | C |
| **B4 — Contract spec: author model-api-contract instance** | C | R/A | C | I |
| **B5 — Contract spec: sign off on instance before staging** | C | A | R (BE) | I |
| **C1 — Drift monitoring: configure drift-exporter per model (WS-C)** | I | R | I | A |
| **C2 — Drift monitoring: set alert thresholds in grafana-self-serve** | I | R | I | A |
| **C3 — Drift alert fires: acknowledge + classify** | I | R | I | A |
| **C4 — Drift alert fires: trigger retrain or escalate** | I | R/A | I | C |
| **D1 — Serving/API: implement inference client** | I | C | R/A | I |
| **D2 — Serving/API: integrate request_id / OTel tracing** | I | I | R/A | C |
| **D3 — Serving/API: validate SLO targets (p50/p99/error rate)** | I | C | R/A | C |
| **E1 — On-call: platform/infra alert fires** | I | I | I | R/A |
| **E2 — On-call: model accuracy / drift alert fires** | I | R/A | I | C |
| **E3 — On-call: incident declared (P0/P1)** | I | C | C | R/A |
| **E4 — On-call: post-incident review + runbook update** | C | C | C | R/A |

### Gap resolution rules

- **B5 sign-off blocks staging promotion.** The ml-pipeline.yml `deploy` job
  environment gate (`environment: staging`) requires the contract sign-off to
  be documented in the PR description before reviewer approval.
- **C4 retrain decision.** ML Engineering decides whether to trigger a retrain
  (`trigger_reason: drift` via the Alertmanager webhook receiver) or escalate to
  Platform if the Airflow DAG is unavailable.
- **E2 / E3 escalation.** If a model accuracy alert does not self-resolve within
  30 minutes, ML Engineering escalates to Platform for incident command per the
  ADR-0040 `ml-platform-oncall` PagerDuty service.

---

## 3. Handoff flow

The diagram below shows the artifact hand-off sequence. System boundaries match the
WS-B/C/D components.

```
Data Engineering              ML Engineering             Backend/Frontend      Platform/SRE
     |                              |                           |                    |
─── Feature pipeline ──────────────────────────────────────────────────────────────────────
     |                              |                           |                    |
[H1] Freeze Iceberg snapshot ──────>|                           |                    |
     | (airflow/dags/               |                           |                    |
     |  train_domain_adapter.py:    |                           |                    |
     |  freeze_snapshot())          |                           |                    |
     |                              |                           |                    |
─── Model training (WS-B) ─────────────────────────────────────────────────────────────────
     |                              |                           |                    |
     |                         [H2] train_domain_adapter DAG   |                    |
     |                              | (triggered by             |                    |
     |                              |  ml-pipeline.yml or       |                    |
     |                              |  drift webhook)           |                    |
     |                         [H3] eval_adapter_debate + quality gate               |
     |                              | win_rate >= 0.55          |                    |
     |                         [H4] Register model in MLflow ─────────────────────> |
     |                              | cosign sign + SBOM        |                    |
     |                              | (.github/actions/*)       |                    |
─── Contract sign-off ──────────────────────────────────────────────────────────────────────
     |                         [H5] Contract instance PR ──────>|                    |
     |                              | (docs/contracts/)         | sign off           |
─── Staging promotion ──────────────────────────────────────────────────────────────────────
     |                         [H6] Kargo: dev (auto) ─────────────────────────────>|
     |                         [H7] Kargo: staging (reviewer gate) ────────────────>|
─── Production deployment ──────────────────────────────────────────────────────────────────
     |                         [H8] Kargo: prod (manual gate) ──────────────────── >|
─── Drift monitoring (WS-C/D) ──────────────────────────────────────────────────────────────
     |                              |              WS-C drift-exporter ─────────── >|
     |                              |              (apps/infra/ml-monitoring/)      |
     |                              |                     Prometheus + Grafana       |
     |                              |                     (grafana-self-serve/)      |
─── Retrain trigger (WS-C -> WS-B) ─────────────────────────────────────────────────────────
     |                         [H9] Drift alert fires ──────────────────────────── >|
     |                              | Alertmanager webhook -> Airflow REST           |
     |                              | POST .../train_domain_adapter/dagRuns          |
     |                              | conf: {trigger_reason: "drift"}               |
     |                         [H2 repeats for retrain]         |                    |
```

### Handoff summary table

| ID | Artifact handed off | From | To | Gate / mechanism |
|----|--------------------|----|-----|-----------------|
| H1 | Iceberg snapshot (frozen, versioned) | DE | ML | Airflow `freeze_snapshot()` task; snapshot_id recorded in MLflow run |
| H2 | Trained LoRA adapter | ML | ML (eval) | Airflow `TriggerDagRunOperator` → `eval_adapter_debate` |
| H3 | Eval report (win_rate, p95_distance) | ML (eval) | ML (register) | Quality gate: `win_rate >= 0.55`; blocks promotion on failure |
| H4 | Signed model artifact + SBOM | ML | BE + PL | MLflow registry (Staging) + cosign signature + OCI image |
| H5 | Contract instance (YAML) | ML | BE | PR to `docs/contracts/`; sign-off from BE required before H6 |
| H6 | Staged deploy (dev) | ML | PL | Kargo auto-promotion; `post_deployment_smoke` DAG fires 30 min later |
| H7 | Staged deploy (staging) | ML | PL | Kargo reviewer gate; human reviewer approval required |
| H8 | Staged deploy (prod) | PL | BE/all | Kargo manual gate; platform on-call confirms readiness |
| H9 | Drift alert (Alertmanager) | PL (infra) | ML | Alertmanager webhook receiver → Airflow REST API retrain trigger |

---

## 4. On-call and escalation

This table supplements the ADR-0040 ML-incident runbooks. It covers first-response
for the alert classes emitted by WS-B/C/D.

| Alert | First paged | Ack SLA | First action | Escalate to | Escalate after |
|-------|------------|---------|--------------|-------------|----------------|
| `AirflowDagRunFailed` (any DAG) | ML on-call | 15 min | Check Airflow logs → retry DAG run | Platform if infra issue | 30 min |
| `MLModelDriftHigh` (drift > 0.4) | ML on-call | 15 min | Inspect Evidently report → trigger retrain manually if auto-trigger failed | Platform if Airflow down | 30 min |
| `MLModelAccuracyLow` (accuracy < 0.75) | ML on-call | 15 min | Check eval metrics in MLflow → consider rollback via ArgoCD | Platform for Kargo rollback | 30 min |
| `MLflowTrackingDown` | Platform on-call | 5 min | Check MLflow pod health → ArgoCD sync | Escalate to P1 if pipeline blocked | 15 min |
| `GrafanaFolderMissing` (self-serve) | Platform on-call | 30 min | ArgoCD re-sync grafana-self-serve app | n/a | n/a |
| Platform infra alert (any) | Platform on-call | 5 min | Per ADR-0040 runbooks | Incident command if P0/P1 | 15 min |

### Escalation path

```
ML alert fires
    |
    v
ML Engineering on-call  (PagerDuty: ml-platform-oncall)
    |  > 30 min unresolved OR infra cause confirmed
    v
Platform / SRE on-call  (PagerDuty: platform-oncall)
    |  P0 declared (full outage / data loss risk)
    v
Incident Commander (Platform lead or on-call manager)
    |  > 60 min OR confirmed customer impact
    v
Engineering Manager + Comms
```

---

## 5. ADR-0034 revisit criteria (Backstage)

The three conditions that must be met before Backstage (ADR-0034) is revisited:

1. GCP ML platform reaches Phase-3 stable (WS-A..E all applied and running in prod).
2. A dedicated Backstage owner (engineer or team) is assigned.
3. Three or more teams have successfully onboarded via the WS-F golden paths in
   this document.

Current status: condition 1 pending (WS-A..E are plan/validate-only);
conditions 2 and 3 not yet met.

---

## 6. References

- `docs/adrs/0037-ml-cicd-pipeline-mlflow.md` (WS-B)
- `docs/adrs/0038-ml-observability-drift.md` (WS-C)
- `docs/adrs/0039-self-serve-observability.md` (WS-D)
- `docs/adrs/0040-soc-posture-and-oncall.md` (WS-E, ML runbooks)
- `docs/adrs/0041-golden-paths-collaboration.md` (WS-F)
- `docs/contracts/model-api-contract.md` (contract spec)
- `docs/self-serve-observability.md` (WS-D onboarding guide)
- `.github/workflows/ml-pipeline.yml` (WS-B pipeline)
- `apps/infra/airflow/dags/` (WS-B DAGs)
- `apps/infra/ml-monitoring/` (WS-C drift-exporter)
- `apps/infra/grafana-self-serve/` (WS-D self-serve chart)
