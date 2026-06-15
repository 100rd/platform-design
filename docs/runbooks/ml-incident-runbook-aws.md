# Runbook: ML-Platform Incident Response — AWS EKS GPU Platform

> **Scope:** ML-specific incidents on the **greenfield AWS EKS GPU ML platform**
> (ADRs 0044–0048) — model drift / accuracy regression, training-pipeline failure, and
> serving outage. This is the AWS-side companion to
> [`ml-incident-runbook.md`](ml-incident-runbook.md) (the GKE/ADR-0040 D4 runbook); the
> ML-domain decision trees are cluster-agnostic, the AWS deltas are GPU-on-EKS specifics
> (DCGM, EFA, Karpenter, Pod Identity, the Envoy + AWS WAF inference front). Follow the
> general [SRE runbook](../sre-runbook.md) and
> [on-call rotation & escalation (AWS)](oncall-rotation-escalation-aws.md) for generic
> triage, PagerDuty ACK, and comms templates.
>
> **System / owner (ADR-0028):** `platform.system = ml-monitoring` / `ml-platform`;
> `platform.owner = team-ml-platform`. Alerts carry `platform_system` so they route on
> the same Grafana `$system` axis across AWS + GCP.
>
> **Wiring (reuse, not new):** drift/accuracy alerts fire via the ADR-0038 Alertmanager
> route to the `ml-drift-pagerduty` receiver and, on `severity=critical`, to the
> `ml-retrain-webhook` (Airflow REST `dagRuns`, K8s Job fallback). The dedicated
> **`ml-platform-oncall` PagerDuty service** is the WS-E formalization (see the on-call
> doc); until provisioned, ML alerts fall back to the shared platform receiver.

## Severity definitions (ML, AWS)

| Severity | Definition | PagerDuty | ACK SLA |
|---|---|---|---|
| **SEV1** | Production model serving down / erroring behind the Envoy + WAF front; user-facing | Page `ml-platform-oncall` immediately | 5 min |
| **SEV2** | Accuracy/drift breach on a production model, or a training pipeline blocking a scheduled retrain/release | Page ML on-call | 15 min |
| **SEV3** | Drift warning trend, non-blocking pipeline failure, staging-only, single Karpenter GPU node lost | Notify Slack `#ml-incidents` | 1 h |

---

## Scenario 1 — Model drift / accuracy regression

**Trigger:** `MLDrift*` / `MLAccuracyBreach` alert (Evidently/whylogs → Prometheus,
ADR-0038) for a model `platform_system`.

1. **Confirm scope.** Grafana drift dashboard filtered to the model's `$system`. Is it
   one model/tenant (namespace-per-model isolation) or many (shared feature pipeline)?
2. **Classify drift.** Data drift (input distribution) vs concept drift (label
   relationship) vs pipeline bug (a feature went null/constant). A single feature pinned
   to a constant is usually an upstream data bug, not real drift — fix the source, do not
   retrain.
3. **Decide retrain.** SEV2 if a production model breaches its accuracy gate. The
   `ml-retrain-webhook` may have already opened an Airflow `dagRun` — confirm in the
   Airflow UI; do not double-fire.
4. **Mitigate.** If accuracy is user-impacting, roll the serving deployment back to the
   last-good MLflow model version (Kargo promotion / ArgoCD rollback) while the retrain
   runs.
5. **Recover.** Verify the retrained model passes the eval gate, is signed (cosign), and
   promotes; confirm drift metric returns to band.

## Scenario 2 — Training-pipeline failure (Airflow on EKS)

**Trigger:** Airflow DAG failure alert, or a scheduled retrain not completing.

1. **Locate the failed task.** Airflow UI → the DAG run → failed task logs.
2. **AWS-delta triage:**
   - **GPU unavailable / Karpenter not scaling:** check the GPU `NodePool` /
     `EC2NodeClass` — Capacity Block exhausted, spot interrupted mid-job (training pools
     should be off-spot, ADR R7), or per-region GPU quota hit (R4). `kubectl describe`
     the pending pod for the scheduling reason.
   - **S3 / MLflow access denied:** the workload role is `aws-ml-abac-iam` — an
     `AccessDenied` to the artifact bucket usually means the resource is **not tagged**
     with the role's `platform:system` (the ABAC tag-match fails by design). Tag the
     bucket/object or check the pod's Pod Identity association.
   - **Secrets unavailable:** MLflow RDS creds come via ESO (ADR-0008/0031) — check the
     ExternalSecret sync status and the Secrets Manager secret.
3. **Volcano gang-scheduling stuck:** a multi-pod training job stuck `Pending` is often a
   gang that cannot fully schedule (insufficient GPUs). Check the Volcano `PodGroup`.
4. **Recover.** Re-run the task once the cause is cleared; if it was a transient spot
   interruption, confirm the pool moved to on-demand/Capacity Blocks for the rerun.

## Scenario 3 — Serving outage (Envoy + Gateway API Inference Extension + AWS WAF)

**Trigger:** SEV1 — `MLServingDown` / 5xx spike / latency SLO burn behind the inference
front (ADR-0047).

1. **Front vs backend.** Is the Envoy Gateway / `InferencePool` healthy, or are the model
   pods failing? Check the gateway, the `InferencePool` endpoints, and the Endpoint
   Picker (EPP) ext-proc (separately deployed — ADR-0047) health.
2. **AWS WAF check.** A sudden 4xx/403 spike at the front may be a WAF rule in block mode
   over-matching legitimate traffic (ADR R8 says rules ship count-then-block). Inspect the
   `terraform/modules/waf` WebACL sampled requests before disabling anything.
3. **GPU node health.** DCGM exporter (`apps/infra/dcgm-exporter`) — XID errors, ECC,
   thermal throttling, or a node auto-tainted by the DCGM health check. A bad GPU node is
   drained by Karpenter; confirm a replacement scheduled.
4. **Mitigate.** Shift traffic to a healthy canary `InferencePool` / revert to `ClusterIP`
   (ADR R8 keeps it revertible); scale the serving pool; in a regional outage, trigger the
   Route 53 cross-region failover (`failover-controller`, ADR-0044 D5).
5. **Recover.** Confirm SLO back in band, WAF back to count where it over-matched, and the
   GPU node fleet healthy in the DCGM dashboard.

---

## Cross-references

- [On-call rotation & escalation (AWS)](oncall-rotation-escalation-aws.md) — rotations,
  L1→L3 timers, tabletop, comms.
- [SOC2 control matrix (AWS ML)](../compliance/soc2-control-matrix-aws-ml.md) — CC7.3/7.4.
- [ADR-0038](../adrs/0038-ml-observability-drift.md) — drift → Alertmanager → retrain.
- [ADR-0047](../adrs/0047-eks-inference-serving-front-waf.md) — Envoy + inference
  extension + AWS WAF serving front.
- [ADR-0044](../adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md) — DCGM, Karpenter,
  EFA, multi-region failover.
