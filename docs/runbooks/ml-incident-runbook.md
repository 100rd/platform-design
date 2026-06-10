# Runbook: ML-Platform Incident Response

> **Scope:** ML-specific incidents on the GKE ML platform — model drift / accuracy
> regression, training-pipeline failure, and serving outage. This runbook **extends**
> the general [SRE runbook](../sre-runbook.md) and
> [on-call rotation & escalation](oncall-rotation-escalation.md); follow those for
> generic triage, PagerDuty acknowledgement, and comms templates. Here we cover the
> ML-domain decision trees only.
>
> **System / owner (ADR-0028):** `platform.system = ml-monitoring` /
> `ml-platform`; `platform.owner = team-ml-platform`. All alerts referenced below
> carry `platform_system` so they route on the same Grafana `$system` axis.
>
> **Wiring:** drift/accuracy alerts fire via the ADR-0038 Alertmanager route
> (`apps/infra/ml-monitoring/templates/prometheusrules/ml-drift-alerts.yaml`) to the
> `ml-drift-pagerduty` receiver and, on `severity=critical`, to the
> `ml-retrain-webhook`. The dedicated **ML PagerDuty service** is the WS-E
> formalization called out as a follow-up in ADR-0038 D3.

## Severity definitions (ML)

| Severity | Definition | PagerDuty | ACK SLA |
|---|---|---|---|
| **SEV1** | Serving down or returning errors for a production model; user-facing impact | Page ML on-call immediately | 5 min |
| **SEV2** | Accuracy/drift breach on a production model, or training pipeline blocking a scheduled retrain/release | Page ML on-call | 15 min |
| **SEV3** | Drift warning trend, non-blocking pipeline failure, staging-only issue | Notify Slack `#ml-incidents` | 1 h |

---

## Scenario 1 — Model drift / accuracy regression

**Symptoms / alerts:** `MLDriftDetected`, `MLAccuracyBelowThreshold`,
`MLPredictionDistributionShift` (Evidently / whylogs exporters, ADR-0038). PagerDuty
incident on the `ml-drift-pagerduty` service.

### Triage

1. **Acknowledge** in PagerDuty (stops escalation timer).
2. **Identify the model + tenant + domain** from alert labels:
   ```promql
   # Which model/tenant is drifting and by how much?
   ml_drift_score{platform_system="ml-monitoring"} > on(model_name) group_left
     ml_drift_threshold{platform_system="ml-monitoring"}
   ```
3. **Classify the drift** (Grafana ML-observability dashboard):
   - **Data drift** (input distribution shifted) vs **concept drift** (input→label
     relationship shifted) vs **accuracy-only** (ground-truth labels regressed).
   - Check whether drift correlates with a recent **upstream data change** (new
     source, schema change) or a **model deploy** (`mlflow` model-version bump).

### Decision tree

| Finding | Action |
|---|---|
| Drift is **data-quality** (bad/late upstream batch) | Do **not** retrain on poisoned data. Quarantine the batch, fix upstream, re-run feature pipeline. Suppress the retrain webhook (see "Stop a retrain storm" below). |
| Drift is **genuine concept drift**, model still serving safely | Allow the **automated retrain trigger** (ADR-0038 D4) to proceed; monitor the retrain job. Confirm the new candidate beats the incumbent in the MLflow eval gate before promotion. |
| **Accuracy below SLA** and user-impacting | Treat as **SEV1/2**: roll back to the last-good MLflow model version (Scenario 3 rollback), THEN retrain offline. |
| Drift is a **false positive** (threshold too tight) | Tune the threshold in the PrometheusRule; record in postmortem. Do not silence permanently without owner sign-off. |

### Stop a retrain storm

The `ml-retrain-webhook` has `repeat_interval: 6h` (ADR-0038 D3) to bound retrain
frequency. To pause retraining during an incident:
```bash
# Silence the critical route that fires the retrain webhook (NOT the pager route).
amtool silence add platform_system=ml-monitoring severity=critical \
  --duration=4h --comment="INC-XXXX: drift from bad upstream batch, retrain paused" \
  --author="$ONCALL"
```
> A retrain on poisoned data is worse than no retrain. Always confirm data integrity
> before letting the model relearn.

### Recovery / exit

- New model version passes the MLflow eval gate and drift score returns under
  threshold for 2 consecutive evaluation windows.
- Document root cause (data vs concept vs threshold) in the postmortem.

---

## Scenario 2 — Training-pipeline failure

**Symptoms / alerts:** Airflow DAG failure (ADR-0037 orchestrator), `MLRetrainJobFailed`,
MLflow run marked `FAILED`, or the retrain webhook returning non-2xx.

### Triage

1. **Acknowledge**; classify SEV (blocking a scheduled release = SEV2, else SEV3).
2. **Locate the failed task** in Airflow:
   ```bash
   kubectl -n ml-platform logs -l platform.system=ml-platform,platform.component=airflow-worker --tail=200
   # Or via the Airflow UI: DAGs → ml_retrain → failed task → logs
   ```
3. **Bucket the failure:**

| Failure class | Signal | First action |
|---|---|---|
| **Data/feature** | Feature pipeline empty/schema mismatch | Validate upstream source + feature store; do not auto-retry blindly |
| **Resource** | GPU `Pending` / OOMKilled / quota | Check Volcano queue + GPU capacity (ADR-0036); check `gcp-billing-budget` did not throttle; bump request or wait for spot capacity |
| **Artifact store** | GCS write denied / Cloud SQL unreachable | Check org-policy did not block (CMEK / public-IP); check MLflow backend Cloud SQL health (ADR-0037) |
| **Code/dependency** | Import/version error | Likely a bad model-code change; revert the offending commit, re-trigger |
| **Transient** | Network blip, preemption | Re-trigger the DAG run; if it passes, log as transient |

### Resource-exhaustion sub-procedure (most common)

```bash
# GPU schedulability (Volcano gang scheduling, ADR-0036)
kubectl get pods -n ml-platform -o wide | grep -E "Pending|OOMKilled"
kubectl describe podgroup -n ml-platform | grep -A3 "Unschedulable"

# Is the GPU node pool scaled to zero / out of spot capacity?
kubectl get nodes -l cloud.google.com/gke-accelerator --show-labels
```
- If spot capacity is unavailable, fall back to on-demand for the retrain (cost
  trade-off; note it in the incident — ties to `gcp-billing-budget` alerts).

### Recovery / exit

- DAG run succeeds end-to-end; MLflow run `FINISHED`; model registered.
- If the failure blocked a release, confirm the downstream serving deploy is
  unblocked. Record the failure class in the postmortem.

---

## Scenario 3 — Serving outage (SEV1)

**Symptoms / alerts:** `MLServingDown`, `MLServingHighErrorRate`,
`MLServingHighLatency`, 5xx from the inference gateway, or a model endpoint failing
health checks.

### Triage (first 5 minutes)

1. **Acknowledge** (5-min SLA). Open an incident channel (`#ml-incidents`) using the
   template in the [on-call doc](oncall-rotation-escalation.md).
2. **Confirm blast radius:**
   ```bash
   # Serving pods healthy?
   kubectl get pods -n ml-serving -l platform.system=ml-platform -o wide
   # Error rate + latency by model — Grafana: ML Serving SLO dashboard
   ```
   ```promql
   sum(rate(ml_serving_requests_total{platform_system="ml-platform",code=~"5.."}[5m]))
     / sum(rate(ml_serving_requests_total{platform_system="ml-platform"}[5m]))
   ```
3. **Is it one model or cluster-wide?** One model → likely a bad model version.
   Cluster-wide → likely infra (node pool, GPU driver, gateway, region).

### Decision tree

| Finding | Action |
|---|---|
| **Single model**, error rate spiked after a deploy | **Roll back** to last-good MLflow model version (below). Fastest path to recovery. |
| **GPU/driver** issue (DCGM XID errors, node NotReady) | Cordon/drain the bad node; DCGM auto-taint (ADR-0036) should evict; verify GPU operator health |
| **Region-wide** outage | Initiate **cross-region serving failover** (ADR-0036 D5; see DNS/health failover runbooks under `docs/multi-region/runbooks/`) |
| **Gateway/ingress** | Check Gateway API / Envoy (ADR-0009); not ML-specific — hand to platform on-call |
| **Capacity** (HPA maxed, queue backing up) | Scale serving replicas / GPU pool; check KEDA triggers (ADR-0036) |

### Roll back a model version (fastest SEV1 mitigation)

```bash
# Identify current vs last-good version in the MLflow registry (ADR-0037)
# Promote the previous version back to the serving alias, then restart serving.
mlflow models ...                                   # set serving alias to prior version
kubectl -n ml-serving rollout restart deployment/<model-serving-deploy>
kubectl -n ml-serving rollout status  deployment/<model-serving-deploy>
```
> Roll back **first**, root-cause **second**. A SEV1 serving outage is mitigated by
> reverting to a known-good model version, not by debugging the new one live.

### Cross-region failover (region-wide outage)

Follow `docs/multi-region/runbooks/failover-manual.md` (manual) /
`failover-auto.md` (health-check driven). ML serving runs as independent regional
deployments (ADR-0036 D5) — failover is DNS/health-based, no shared GPU pool.

### Recovery / exit

- Error rate < SLO and latency normal for 15 min; SLO budget burn arrested.
- If rolled back: schedule offline investigation of the bad model version before
  any re-promotion (links to Scenario 1 if drift-related).

---

## Postmortem (all SEV1/SEV2)

Use the blameless postmortem template in the [SRE runbook](../sre-runbook.md).
ML-specific fields to capture:

- Model name / version / tenant / domain.
- Drift vs pipeline vs serving classification.
- Whether the automated retrain trigger helped or hurt (feeds ADR-0038 threshold
  tuning).
- Evidence pointers for the SOC2 matrix (CC7.3/CC7.4): incident timeline, PagerDuty
  record, the alert that fired, the remediation commit/PR.

## Tabletop (acceptance for WS-E)

The on-call rotation is validated by a **tabletop exercise** (see the
[on-call doc](oncall-rotation-escalation.md)) that walks one scenario from each
class above (drift → pipeline → serving) without touching production. Record the
exercise date + participants as CC1.4 / A1.3 evidence.
