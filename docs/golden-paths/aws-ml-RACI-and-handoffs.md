# AWS ML RACI and Handoffs: Production Model Lifecycle

> **Platform:** AWS EKS GPU ML cluster (ADR-0044 / ADR-0048)
> **ADR gates:** ADR-0041 (WS-F), ADR-0048 (AWS backends)
> **GCP etalon:** `docs/golden-paths/RACI-and-handoffs.md` (GCP/GKE variant)
>
> This is the **AWS-flavoured** RACI and handoff document. The lifecycle
> activities, personas, RACI assignments, escalation path, and ADR-0034 revisit
> criteria are **identical** to the GCP etalon. Only the AWS-specific backend
> and identity references differ: S3 (not GCS), ECR (not GCR), EKS Pod Identity
> (not GKE Workload Identity), RDS (not Cloud SQL), AWS Secrets Manager (not GCP).

**Document scope:** the end-to-end lifecycle for a new ML model from raw data to
monitored production on the **AWS EKS ML cluster**, covering the four engineering
personas and the five lifecycle activities. This supplements the ADR-0040
ML-incident runbooks with a day-1 ownership model.

**Related ADRs:** ADR-0044 (AWS EKS foundation), ADR-0048 (AWS ML backends),
ADR-0039 (WS-D self-serve), ADR-0040 (WS-E on-call), ADR-0041 (WS-F, this document).

---

## 1. Personas

| ID | Persona | Responsibility scope |
|----|---------|---------------------|
| DE | **Data Engineering** | Feature pipelines, Iceberg-on-S3 snapshot management, data quality, reference dataset curation (S3) |
| ML | **ML Engineering** | Model training, evaluation, MLflow registry (RDS + S3), DAG authorship, adapter packaging (ECR) |
| BE | **Backend / Frontend** | API integration, inference client, contract implementation, latency budgets |
| PL | **Platform / SRE** | AWS EKS GPU infrastructure, GitOps delivery (ArgoCD), observability stack, on-call, incident command, Pod Identity / IAM |

---

## 2. RACI matrix

**Key:** R = Responsible (does the work) - A = Accountable (owns the outcome) -
C = Consulted (input required) - I = Informed (notified)

| Activity | DE | ML | BE | PL |
|----------|----|----|----|-----|
| **A1 -- Feature pipeline: design schema** | R/A | C | C | I |
| **A2 -- Feature pipeline: implement + deploy Iceberg snapshot (S3)** | R/A | C | I | C |
| **A3 -- Feature pipeline: validate reference dataset quality (S3 path)** | R/A | C | I | I |
| **A4 -- AWS: provision Pod Identity binding for data-pipeline SA** | I | I | I | R/A |
| **B1 -- Model training: configure Airflow DAG (aws-ml-new-pipeline template)** | C | R/A | I | C |
| **B2 -- Model training: run train->eval pipeline (ml-pipeline.yml, ECR)** | I | R/A | I | C |
| **B3 -- Model training: MLflow registration + cosign sign (S3 + RDS)** | I | R/A | I | C |
| **B4 -- Contract spec: author aws-ml-model-api-contract instance** | C | R/A | C | I |
| **B5 -- Contract spec: sign off on instance (base + AWS addendum) before staging** | C | A | R (BE) | I |
| **B6 -- AWS: confirm artifact in S3 + ECR image URI in MLflow run** | I | R/A | I | C |
| **C1 -- Drift monitoring: configure drift-exporter per model (WS-C, S3 ref dataset)** | I | R | I | A |
| **C2 -- Drift monitoring: set alert thresholds in grafana-self-serve** | I | R | I | A |
| **C3 -- AWS: provision Pod Identity binding for drift-exporter SA** | I | I | I | R/A |
| **C4 -- Drift alert fires: acknowledge + classify** | I | R | I | A |
| **C5 -- Drift alert fires: trigger retrain or escalate** | I | R/A | I | C |
| **D1 -- Serving/API: implement inference client (aws-ml-new-model-service)** | I | C | R/A | I |
| **D2 -- Serving/API: integrate request_id / OTel tracing** | I | I | R/A | C |
| **D3 -- Serving/API: validate SLO targets (p50/p99/error rate)** | I | C | R/A | C |
| **D4 -- AWS: configure InferenceObjective + EPP on Envoy Gateway (ADR-0047)** | I | C | I | R/A |
| **E1 -- On-call: platform/infra alert fires (EKS/Karpenter/Volcano)** | I | I | I | R/A |
| **E2 -- On-call: model accuracy / drift alert fires** | I | R/A | I | C |
| **E3 -- On-call: incident declared (P0/P1)** | I | C | C | R/A |
| **E4 -- On-call: post-incident review + runbook update** | C | C | C | R/A |

### Gap resolution rules

- **A4 + C3 (Pod Identity):** Platform/SRE owns IAM + Pod Identity associations.
  ML Engineering must provide the ServiceAccount name + namespace; Platform
  creates the association and documents the role ARN in the ArgoCD Application
  annotation before the model is deployed.
- **B5 sign-off blocks staging promotion.** The `ml-pipeline.yml` deploy job
  environment gate (`environment: staging`) requires the contract sign-off (both
  `docs/contracts/model-api-contract.md` base AND
  `docs/contracts/aws-ml-model-api-contract.md` addendum) to be documented in
  the PR description before reviewer approval.
- **B6 verification:** ML Engineering confirms the S3 artifact URI and ECR image
  URI are recorded in the MLflow run before declaring training complete.
- **C5 retrain decision:** ML Engineering decides whether to trigger a retrain
  (`trigger_reason: drift` via the Alertmanager webhook receiver) or escalate to
  Platform if the Airflow DAG is unavailable on EKS.
- **D4 (InferenceObjective):** Platform/SRE owns the Envoy Gateway
  `InferenceObjective` + EPP deployment (ADR-0047). Backend provides the model
  endpoint spec; Platform wires it to the inference gateway.
- **E2 / E3 escalation:** If a model accuracy alert does not self-resolve within
  30 minutes, ML Engineering escalates to Platform for incident command per the
  ADR-0040 `ml-platform-oncall` PagerDuty service.

---

## 3. Handoff flow

The diagram below shows the artifact hand-off sequence on the AWS EKS ML cluster.
System boundaries match the WS-B/C/D components.

```
Data Engineering              ML Engineering             Backend/Frontend      Platform/SRE
     |                              |                           |                    |
--- Feature pipeline -------------------------------------------------------------------------
     |                              |                           |                    |
[H1] Freeze Iceberg snapshot (S3) ->|                          |                    |
     | (airflow/dags/               |                           |                    |
     |  train_domain_adapter.py:    |                           |                    |
     |  freeze_snapshot() -> S3)    |                           |                    |
     |                              |                           |                    |
--- Model training (WS-B, AWS) ---------------------------------------------------------------
     |                              |                           |                    |
     |                         [H2] train_domain_adapter DAG   |                    |
     |                              | (ml-pipeline.yml or       |                    |
     |                              |  drift webhook -> Airflow)|                    |
     |                         [H3] eval_adapter_debate + quality gate               |
     |                              | win_rate >= 0.55          |                    |
     |                         [H4] Register model in MLflow (RDS + S3) ----------->|
     |                              | cosign sign + SBOM (ECR)  |                    |
     |                              | (.github/actions/*)       |                    |
--- Contract sign-off (base + AWS addendum) --------------------------------------------------
     |                         [H5] Contract instance PR ------>|                    |
     |                              | (docs/contracts/          | sign off           |
     |                              |  aws-ml-model-api-        | (base + addendum)  |
     |                              |  contract.md addendum)    |                    |
--- Staging promotion ------------------------------------------------------------------------
     |                         [H6] Kargo: dev (auto) -------------------------------->|
     |                         [H7] Kargo: staging (reviewer gate) ------------------>|
--- Production deployment -------------------------------------------------------------------
     |                         [H8] Kargo: prod (manual gate) ----------------------->|
     |                              |                           | InferenceObjective  |
     |                              |                           | + EPP wired [D4]   |
--- Drift monitoring (WS-C/D, AWS) ----------------------------------------------------------
     |                              |              WS-C drift-exporter (S3 ref) ---->|
     |                              |              (apps/infra/ml-monitoring/)        |
     |                              |              Prometheus -> Alertmanager         |
     |                              |              Grafana (grafana-self-serve)       |
--- Retrain trigger (WS-C -> WS-B) ----------------------------------------------------------
     |                         [H9] Drift alert fires ------------------------------>|
     |                              | Alertmanager webhook -> Airflow REST            |
     |                              | POST .../train_domain_adapter/dagRuns           |
     |                              | conf: {trigger_reason: "drift"}                |
     |                         [H2 repeats for retrain]         |                    |
```

### Handoff summary table

| ID | Artifact handed off | From | To | Gate / mechanism |
|----|--------------------|----|-----|-----------------|
| H1 | Iceberg snapshot (frozen, versioned on S3) | DE | ML | Airflow `freeze_snapshot()` task; snapshot_id recorded in MLflow run |
| H2 | Trained LoRA adapter (weights on S3) | ML | ML (eval) | Airflow `TriggerDagRunOperator` -> `eval_adapter_debate` |
| H3 | Eval report (win_rate, p95_distance) | ML (eval) | ML (register) | Quality gate: `win_rate >= 0.55`; blocks promotion on failure |
| H4 | Signed model artifact (S3) + SBOM (ECR) | ML | BE + PL | MLflow registry (Staging) + cosign signature + OCI image in ECR |
| H5 | Contract instance (YAML, base + AWS addendum) | ML | BE | PR to `docs/contracts/`; sign-off from BE required before H6 |
| H6 | Staged deploy (dev) | ML | PL | Kargo auto-promotion; `post_deployment_smoke` DAG fires 30 min later |
| H7 | Staged deploy (staging) | ML | PL | Kargo reviewer gate; human reviewer approval required |
| H8 | Staged deploy (prod) | PL | BE/all | Kargo manual gate; platform on-call confirms InferenceObjective + EPP wired (ADR-0047) |
| H9 | Drift alert (Alertmanager) | PL (infra) | ML | Alertmanager webhook receiver -> Airflow REST API retrain trigger |

---

## 4. On-call and escalation

This table supplements the ADR-0040 ML-incident runbooks for the **AWS EKS ML cluster**.

| Alert | First paged | Ack SLA | First action | Escalate to | Escalate after |
|-------|------------|---------|--------------|-------------|----------------|
| `AirflowDagRunFailed` | ML on-call | 15 min | Check Airflow logs -> retry DAG run; check Volcano job status on EKS | Platform if EKS/Karpenter issue | 30 min |
| `MLModelDriftHigh` (drift > 0.4) | ML on-call | 15 min | Inspect Evidently report (S3 ref dataset OK?) -> trigger retrain if auto-trigger failed | Platform if Airflow down or S3 access error | 30 min |
| `MLModelAccuracyLow` (accuracy < 0.75) | ML on-call | 15 min | Check eval metrics in MLflow (RDS) -> consider rollback via ArgoCD / Kargo | Platform for Kargo rollback | 30 min |
| `MLflowTrackingDown` | Platform on-call | 5 min | Check MLflow pod health (RDS connection? ESO ExternalSecret Ready?) -> ArgoCD sync | Escalate to P1 if pipeline blocked | 15 min |
| `S3AccessDenied` (ml-pipeline) | Platform on-call | 15 min | Check Pod Identity association + ABAC tags on bucket -> restore IAM binding | Escalate to P1 if training blocked | 30 min |
| `ECRPullFailed` (pipeline image) | Platform on-call | 15 min | Check ECR pull-through cache (ADR-0029) + node IAM role | Escalate if widespread | 30 min |
| `GrafanaFolderMissing` (self-serve) | Platform on-call | 30 min | ArgoCD re-sync grafana-self-serve app | n/a | n/a |
| Platform infra alert (EKS/Karpenter) | Platform on-call | 5 min | Per ADR-0040 runbooks | Incident command if P0/P1 | 15 min |

### Escalation path

```
ML alert fires
    |
    v
ML Engineering on-call  (PagerDuty: ml-platform-oncall)
    |  > 30 min unresolved OR infra/IAM/S3 cause confirmed
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

## 5. AWS identity sign-off checklist

Before promoting a new model to staging, Platform/SRE must confirm:

```
[ ] Pod Identity association exists for the MLflow ServiceAccount
    IAM role ARN documented in apps/infra/mlflow/templates/external-secret.yaml
[ ] Pod Identity association exists for the drift-exporter ServiceAccount
    IAM role ARN documented in the model's ArgoCD Application annotation
    (platform.aws/drift-exporter-pod-identity-role)
[ ] S3 bucket carries all five ADR-0028 tags:
    platform:system, platform:component, platform:env, platform:owner,
    platform:managed-by
[ ] ABAC condition confirmed on S3 bucket IAM policy:
    aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system
[ ] ECR repository exists and cosign admission policy is in effect (Kyverno)
[ ] ESO ExternalSecret for MLflow RDS creds is Ready in the mlflow namespace
```

---

## 6. ADR-0034 revisit criteria (Backstage)

The three conditions that must be met before Backstage (ADR-0034) is revisited:

1. AWS ML platform reaches Phase-4 stable (WS-A..E all applied and running in prod
   on the `aws-eks-gpu-*` cluster).
2. A dedicated Backstage owner (engineer or team) is assigned.
3. Three or more teams have successfully onboarded via the WS-F AWS golden paths
   (`aws-ml-new-model-service`, `aws-ml-new-pipeline`, or `aws-ml-new-dashboard`).

Current status: Phase-4 pending (WS-A..E are plan/validate-only);
conditions 2 and 3 not yet met.

---

## 7. References

- GCP etalon RACI: `docs/golden-paths/RACI-and-handoffs.md`
- ADR-0044: AWS EKS GPU ML foundation
- ADR-0048: AWS ML CI/CD + MLflow backends (S3, RDS, ECR)
- ADR-0039: WS-D self-serve observability (grafana-self-serve)
- ADR-0040: WS-E SOC posture + ML on-call runbooks
- ADR-0041: WS-F golden-path templates + contracts (this document)
- ADR-0028: platform taxonomy tags + ABAC
- ADR-0018: EKS Pod Identity
- ADR-0047: Envoy Gateway + InferenceObjective (serving front)
- `docs/contracts/model-api-contract.md` (base contract spec)
- `docs/contracts/aws-ml-model-api-contract.md` (AWS-specific addendum)
- `.github/workflows/ml-pipeline.yml` (WS-B pipeline)
- `apps/infra/airflow/dags/` (WS-B DAGs)
- `apps/infra/ml-monitoring/` (WS-C drift-exporter)
- `apps/infra/grafana-self-serve/` (WS-D self-serve chart)
- `templates/golden-paths/aws-ml-new-model-service/` (golden path)
- `templates/golden-paths/aws-ml-new-pipeline/` (golden path)
- `templates/golden-paths/aws-ml-new-dashboard/` (golden path)
