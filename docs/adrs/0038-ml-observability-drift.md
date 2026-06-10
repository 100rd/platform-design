# ADR-0038: ML Observability — Drift Detection, Accuracy Monitoring, and Retrain Trigger

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — no `apps/infra/ml-monitoring` yet deployed,
  no drift metrics flowing into Prometheus, no retrain webhook wired.
- Date: 2026-06-10
- Authors: platform-team (devops-engineer), ml-platform
- Related issues: WS-C "Model & ML Observability" (GCP ML Platform plan §4 WS-C);
  risk-register R3 (Evidently multi-tenant isolation), R2 (Airflow stability).
- Supersedes: (none)
- Superseded by: (none)

## Context

The platform has a strong **system observability** layer (Prometheus 3.x / Thanos,
Grafana, Loki, Tempo, Alertmanager → PagerDuty, OTel Collector — all in
`apps/infra/observability/`). What is entirely absent is **ML observability**:
there are no metrics for feature drift, data distribution shift, prediction
accuracy degradation, or model-serving quality in the Prometheus/Grafana stack.

The `docs/transaction-analytics/04-training-pipeline.md` documents three retrain
triggers: a label-threshold trigger, a **drift trigger** (KL divergence over a
rolling window), and a manual trigger. The drift trigger is described at the
pipeline-design level — there is no deployed monitor, no Prometheus metrics, and
no automated path from "drift detected" to "retrain fires". The gap is confirmed
by the implementation plan §2 row #3 ("gap — no Evidently/whylogs deployed").

Two OSS-native candidates exist:

| Tool | Architecture | Prometheus export | Strengths | Weaknesses |
|------|-------------|-------------------|-----------|------------|
| **Evidently AI** | Python SDK + optional server, reports + monitors | Native `PrometheusLogger` / `/metrics` HTTP endpoint; every test result is a gauge/counter | Rich test suite (PSI, KL, chi², EMD), model-quality tests (accuracy, precision, recall, F1, MAE, RMSE); presets for classification/regression/ranking; active development | Server adds ops overhead; Python-heavy; large image |
| **whylogs** | Lightweight Python SDK + WhyLabs SaaS (optional) | `whylogs.core.metrics` → Prometheus pushgateway or `/metrics`; `prom_metrics_handler` in whylogs ≥ 1.3 | Tiny footprint, designed for high-throughput streaming, columnar profile (approximate histograms, frequent items), runs inline in serving pods | Fewer ready-made ML-quality tests vs Evidently; accuracy/classification metrics require extra instrumentation; WhyLabs SaaS needed for full dashboarding unless hand-rolled |

**Decision driver:** the platform owns Grafana, Thanos, and Alertmanager — it
needs metrics that feed existing PromQL dashboards and alert rules. Both tools
can export to Prometheus. The key differentiator is **test depth**: the
transaction-analytics domain runs LLM adapters for HFT/RTB/insurance and needs
both **feature-distribution drift** (KL, PSI) *and* **model-quality scores**
(classification accuracy, RMSE, debate-eval pass rate) as Prometheus metrics.
Evidently provides both in a single cohesive test runner. whylogs provides
lightweight distribution profiling but requires more bespoke work for
model-quality tests.

**Multi-tenancy:** the platform serves multiple (tenant, domain) pairs
(`docs/transaction-analytics/00-domains.md`). Each pair has its own training
window, reference distribution, and accuracy profile. Namespace-per-model
isolation (risk R3 from the plan) is the natural fence.

## Decision

**Use both tools with a clear role split**, deployed as a single
`ml-monitoring` service in `apps/infra/ml-monitoring/`:

| Role | Tool | Why |
|------|------|-----|
| **Feature drift + data distribution shift** (KL divergence, PSI, chi-squared, EMD) | **whylogs** (sidecar/inline profiler) | Minimal overhead, runs inside or adjacent to the serving pod, continuous per-batch profiling, Prometheus push or pull endpoint |
| **Model accuracy / quality tests** (classification accuracy, precision/recall/F1, RMSE, MAE, debate-eval pass rate) | **Evidently** (dedicated `drift-exporter` Deployment) | Rich test battery, computes against a held-out reference dataset, exports a `/metrics` Prometheus endpoint natively |
| **Prometheus scrape** | Single ServiceMonitor per namespace | Scrapes both the Evidently `/metrics` endpoint and the whylogs Pushgateway |
| **Alert routing** | Existing Alertmanager + PagerDuty path | Reuse existing `pagerduty-critical` receiver; add ML-specific route and retrain webhook receiver |
| **Retrain trigger** | Alertmanager webhook receiver → Airflow REST API | Primary: `POST /api/v1/dags/train_domain_adapter/dagRuns`; fallback: K8s Job CRD |

### D1 — Metric export architecture

```
Serving pod (per-namespace)
  ├── whylogs inline profiler  ──push──►  Pushgateway :9091
  │   (feature distributions)             (or pull /metrics)
  └── Evidently drift-exporter  ──pull──►  ServiceMonitor /metrics :8001
      (accuracy, test suite)
                                                │
                                   Prometheus / Thanos scrape
                                                │
                                   Grafana dashboards  +  Alertmanager
```

**Metric namespace:** all metrics are prefixed `ml_monitoring_` and carry these
labels on every series to satisfy ADR-0028 and enable multi-tenant isolation:

| Label | Value | Rationale |
|-------|-------|-----------|
| `platform_system` | `ml-monitoring` | ADR-0028 mandatory key (K8s dotted form becomes underscore in PromQL) |
| `model_name` | e.g. `domain-adapter-hft` | Identifies the model |
| `tenant` | e.g. `tenant-acme` | Tenant isolation (R3) |
| `domain` | e.g. `hft`, `rtb`, `insurance` | Domain isolation |
| `namespace` | K8s namespace | Matches namespace-per-model |
| `environment` | `production`, `staging` | From external label |

**Core metric families exported:**

```
# whylogs — distribution profiles
ml_monitoring_feature_psi_score{feature, model_name, tenant, domain}            gauge
ml_monitoring_feature_kl_divergence{feature, model_name, tenant, domain}        gauge
ml_monitoring_feature_missing_rate{feature, model_name, tenant, domain}         gauge
ml_monitoring_feature_zero_rate{feature, model_name, tenant, domain}            gauge
ml_monitoring_dataset_drift_score{model_name, tenant, domain}                   gauge
ml_monitoring_drift_detected{model_name, tenant, domain}                        gauge  # 1/0
ml_monitoring_dataset_rows_total{model_name, tenant, domain}                    counter

# Evidently — model quality / accuracy tests
ml_monitoring_model_accuracy{model_name, tenant, domain}                        gauge
ml_monitoring_model_precision{model_name, tenant, domain}                       gauge
ml_monitoring_model_recall{model_name, tenant, domain}                          gauge
ml_monitoring_model_f1_score{model_name, tenant, domain}                        gauge
ml_monitoring_model_rmse{model_name, tenant, domain}                            gauge  # regression
ml_monitoring_test_suite_result{test_name, status, model_name, tenant, domain}  gauge  # 1=pass 0=fail
ml_monitoring_column_drift_score{column, stat_test, model_name, tenant, domain} gauge
ml_monitoring_prediction_drift{model_name, tenant, domain}                      gauge
ml_monitoring_exporter_errors_total{model_name, tenant, domain}                 counter

# Retrain trigger accounting
ml_monitoring_retrain_triggers_total{trigger, tenant, domain, outcome}          counter
```

### D2 — Drift alert thresholds

Thresholds are defaults; per-tenant override via Helm values or a ConfigMap:

| Metric | Warning | Critical | Window | Note |
|--------|---------|----------|--------|------|
| `ml_monitoring_dataset_drift_score` | > 0.2 | > 0.4 | 1h | Combined drift score |
| `ml_monitoring_feature_psi_score` | > 0.1 | > 0.25 | 1h | PSI moderate/severe |
| `ml_monitoring_feature_kl_divergence` | > 0.1 | > 0.3 | 1h | KL divergence |
| `ml_monitoring_model_accuracy` | < 0.85 | < 0.75 | 1h rolling | Classification accuracy |
| `ml_monitoring_model_f1_score` | < 0.80 | < 0.65 | 1h rolling | F1 score |
| `ml_monitoring_drift_detected` | — | = 1 sustained 15m | — | Binary drift flag |

Critical alerts → PagerDuty + retrain trigger. Warning alerts → Slack only.

### D3 — Drift → Alertmanager → PagerDuty route

New Alertmanager route entries added via the Helm overlay in
`apps/infra/ml-monitoring/templates/prometheusrules/ml-alertmanager-routes.yaml`:

```yaml
# Route: ML drift/accuracy alerts → PagerDuty + retrain webhook
routes:
- matchers:
  - platform_system = ml-monitoring
  receiver: ml-drift-pagerduty
  continue: true
  group_by: [model_name, tenant, domain, alertname]
  group_wait: 5m
  repeat_interval: 2h

- matchers:
  - platform_system = ml-monitoring
  - severity = critical
  receiver: ml-retrain-webhook
  group_by: [model_name, tenant, domain]
  group_wait: 5m
  repeat_interval: 6h   # Prevent retrain storm
```

The `ml-drift-pagerduty` receiver uses the existing
`alertmanager-pagerduty-secret` mount (same Secret already in the
prometheus-stack `alertmanagerSpec.secrets` list). A dedicated ML PagerDuty
service/routing key is the follow-up recommended by WS-E (SOC posture), not
required for WS-C launch.

The `ml-retrain-webhook` receiver:

```yaml
- name: ml-retrain-webhook
  webhook_configs:
  - url: 'http://ml-retrain-trigger.ml-monitoring.svc:8080/webhook'
    send_resolved: false
    http_config:
      bearer_token_file: '/etc/alertmanager/secrets/alertmanager-retrain-token/token'
    max_alerts: 10
```

The bearer token is sourced from an ExternalSecret (`alertmanager-retrain-token`)
mounted via ESO (ADR-0008 pattern), matching the existing `alertmanager-slack-secret`
and `alertmanager-pagerduty-secret` pattern in the prometheus-stack values.

### D4 — Retrain trigger mechanism

The retrain-trigger is a webhook receiver called `ml-retrain-webhook` whose URL
is the `ml-retrain-trigger` Deployment in the `ml-monitoring` namespace.

**Primary path — Airflow REST API:**

```
Alertmanager (critical drift alert)
  │
  └──► POST http://ml-retrain-trigger.ml-monitoring.svc:8080/webhook
             (Alertmanager webhook format)
                │
                ▼ translate + de-duplicate (15-min window per tenant/domain)
             POST http://airflow-webserver.airflow.svc:8080/api/v1/dags/train_domain_adapter/dagRuns
             Headers: Authorization: Basic <ESO-sourced base64 user:pass>
             Body: {
               "conf": {
                 "tenant":  "<Labels.tenant>",
                 "domain":  "<Labels.domain>",
                 "trigger": "drift",
                 "model":   "<Labels.model_name>",
                 "alert":   "<Labels.alertname>"
               }
             }
```

The trigger proxy is a lightweight Deployment (`ml-retrain-trigger`) in the
`ml-monitoring` namespace. It:
1. Receives the Alertmanager `POST /webhook` payload (JSON array of firing alerts).
2. De-duplicates by `(tenant, domain)` within a configurable window
   (default 15 minutes) to prevent a single alert group from firing multiple
   DAG runs during the `repeat_interval`.
3. Calls the Airflow REST API `POST /api/v1/dags/train_domain_adapter/dagRuns`.
4. On Airflow 4xx/5xx → creates a K8s Job fallback (see below).
5. Records all outcomes as `ml_monitoring_retrain_triggers_total{outcome="success"|"airflow_error"|"fallback_job_created"}`.

**Fallback path — K8s Job CRD:**

When Airflow is unavailable (WS-B not yet deployed, or Airflow returns 5xx), the
trigger service creates a K8s Job from a template ConfigMap:

```yaml
# Stored in ConfigMap ml-retrain-job-template in ml-monitoring namespace
apiVersion: batch/v1
kind: Job
metadata:
  generateName: retrain-domain-adapter-
  namespace: ml-monitoring
  labels:
    platform.system: ml-monitoring
    platform.component: retrain-trigger
    platform.env: production
    platform.owner: team-ml-platform
    platform.managed-by: argocd
    trigger: drift-fallback
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      serviceAccountName: ml-retrain-trigger
      containers:
      - name: trigger
        image: gcr.io/your-project/ml-retrain-trigger:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          curl -s -X POST \
            -H "Authorization: Basic $(cat /var/run/secrets/airflow/credentials | base64)" \
            -H "Content-Type: application/json" \
            -d "{\"conf\":{\"tenant\":\"$TENANT\",\"domain\":\"$DOMAIN\",\"trigger\":\"drift-fallback\"}}" \
            http://airflow-webserver.airflow.svc:8080/api/v1/dags/train_domain_adapter/dagRuns
        env:
        - name: TENANT
          value: "$(TENANT)"
        - name: DOMAIN
          value: "$(DOMAIN)"
```

The K8s Job path requires the `ml-retrain-trigger` ServiceAccount to have
`jobs/create` permission in the `ml-monitoring` namespace (the Job runs
in-namespace and calls Airflow via HTTP). The ClusterRole / RoleBinding are
templated in `apps/infra/ml-monitoring/templates/`.

**Airflow REST API compatibility note:** Airflow 2.x and 3.x both expose
`POST /api/v1/dags/{dag_id}/dagRuns` (stable REST API v1, doc-verified 2026-06-10).
The `conf` dict passes `tenant`, `domain`, and `trigger` key to the
`train_domain_adapter` DAG as DAG run config, matching the three-trigger design
in `docs/transaction-analytics/04-training-pipeline.md`. The DAG reads
`dag_run.conf["tenant"]` and `dag_run.conf["domain"]` for its `(tenant, domain)`
scoping; the `conf["trigger"] = "drift"` value distinguishes this from the
threshold and manual triggers in the same DAG.

### D5 — Multi-tenant isolation (risk R3)

Each `(model_name, tenant, domain)` combination is deployed in its own Kubernetes
namespace (`ml-<tenant>-<domain>`). The Evidently drift-exporter Deployment and
the whylogs Pushgateway run per namespace. The ServiceMonitor's
`namespaceSelector` is set to the owning namespace, and the metric label
`platform_system=ml-monitoring` is injected via relabeling at scrape time.

Cross-tenant false positive alerting is structurally impossible: separate
Prometheus series, separate alert instances, separate route group keys ensure
a drift event in `tenant-acme/hft` does not trigger a retrain for
`tenant-beta/insurance`.

Grafana dashboards use `$model_name`, `$tenant`, `$domain` template variables
(query-driven from `label_values()`) so each tenant sees only their own series
without requiring Grafana row-level access control (a follow-up WS-D item).

### D6 — NetworkPolicy (implemented, toggle default-off)

Portable K8s NetworkPolicies are **implemented** in
`apps/infra/ml-monitoring/templates/networkpolicies/network-policies.yaml`
(closes WS-A security HIGH-3): default-deny + DNS, scoped ingress to
`ml-drift-exporter`/`ml-retrain-trigger` from the monitoring namespace, and
egress to GCS/Airflow. They are CNI-enforced regardless of the Cilium policy
mode (ADR-0019). `networkPolicy.enabled` defaults to **`false`** so the
default-deny does not cut off co-components (pushgateway / whylogs profiler)
before their allow-rules are verified; flip to `true` after that check.
Critical rules:
- Ingress to `ml-retrain-trigger` from Alertmanager pods only (namespace selector).
- Egress from `ml-retrain-trigger` to `airflow-webserver` in `airflow` namespace,
  and to `kube-apiserver` for Job creation.
- Egress from Evidently drift-exporter to GCS/S3 reference-dataset bucket
  (via GKE Workload Identity — no node-level credentials).
- All ML monitoring pods: deny egress to `10.0.0.0/8` except the above paths.

### D7 — ADR-0028 label compliance

Every resource in `apps/infra/ml-monitoring/` carries the five ADR-0028 keys:

| Key (K8s label) | Value |
|-----------------|-------|
| `platform.system` | `ml-monitoring` |
| `platform.component` | `drift-exporter` (Evidently) / `distribution-profiler` (whylogs) / `retrain-trigger` |
| `platform.env` | `production` / `staging` (parameterised per ArgoCD environment) |
| `platform.owner` | `team-ml-platform` |
| `platform.managed-by` | `argocd` |

Prometheus metric labels follow the `platform_system` (underscore) form as
required by PromQL (dots are not valid in PromQL label names). The
`relabelings` stanza in each ServiceMonitor injects `platform_system=ml-monitoring`
on all scraped series.

A reviewer can confirm compliance by: (a) `grep -r "platform.system" apps/infra/ml-monitoring/templates/` returning a hit in every resource template; (b) `helm lint apps/infra/ml-monitoring/` passing; (c) `kubeconform` reporting no schema violations.

## Alternatives considered

### A1 — Evidently only (no whylogs)

Deploy only Evidently for all monitoring.
*Rejected because:* Evidently's server-side report computation requires batch
window alignment and is not optimised for high-throughput streaming feature
profiling (e.g. 100k+ transactions/minute in the RTB domain). whylogs runs
inline as a profiler and costs orders of magnitude less compute for distribution
tracking. Using Evidently for everything forces the per-batch scheduling problem
onto every model, including those that only need lightweight drift detection.

### A2 — whylogs only (no Evidently)

Deploy only whylogs for all monitoring.
*Rejected because:* whylogs' Prometheus integration (≥ 1.3 `prom_metrics_handler`)
is focused on distribution profiles. Computing model accuracy (F1, RMSE) against
a held-out reference requires either WhyLabs SaaS (external dependency, not
OSS-only) or significant bespoke instrumentation that duplicates Evidently's
test-suite batteries. Evidently's `TestSuite` runs arbitrary quality checks with
a single Python class; replacing that with whylogs-only means writing quality-gate
logic from scratch.

### A3 — Managed ML observability (Vertex AI Model Monitoring, Arize, Fiddler)

Use a managed SaaS drift/accuracy service instead of OSS.
*Rejected because:* the WS-C scope decision is explicitly "OSS, Prometheus-native
— reuses the existing Grafana/Thanos/Alertmanager stack" (implementation plan §7
decision #3). Managed services introduce external data egress (PII risk for
financial transactions), recurring SaaS cost, and a second observability pane
outside Grafana — all contradicting the platform's single-pane-of-glass design
(ADR-0026, ADR-0028).

### A4 — Custom Prometheus exporter (no Evidently/whylogs)

Write a bespoke drift-exporter that computes KL divergence / PSI directly.
*Rejected because:* it re-invents a non-trivial numerical library (statistical
distribution tests, column-level profiling). Both Evidently and whylogs are
battle-tested OSS libraries with Prometheus integration; building equivalent
functionality from scratch is a maintenance liability and delays WS-C.

### A5 — Alertmanager webhook directly to Airflow (no proxy)

Send the raw Alertmanager webhook payload directly to the Airflow REST API.
*Rejected because:* Alertmanager's webhook payload (Prometheus alerting format)
is not the Airflow `dagRuns` JSON format. A translation layer is required in all
cases. The proxy also provides de-duplication (prevents retrain storms during
alert `repeat_interval`), circuit-breaking against Airflow unavailability, and
the K8s Job fallback — none of which are possible in a direct webhook to Airflow.

## Consequences

### Positive
- **ML drift and accuracy gap closed:** feature drift (PSI, KL), data distribution
  shift, model accuracy, and model quality tests all appear as Prometheus metrics
  in the existing Grafana/Thanos stack — zero new observability infrastructure
  required.
- **Automated retrain trigger:** a material drift event in production automatically
  fires `train_domain_adapter` via Airflow REST, with a K8s Job fallback, reducing
  mean time to retrain.
- **Multi-tenant safe (R3 mitigated):** namespace-per-model + `(tenant, domain)`
  label scoping makes cross-tenant interference structurally impossible.
- **Reuses existing stack:** no new alert routing infrastructure; the existing
  Alertmanager → PagerDuty path gains ML-specific matchers and a webhook receiver.
- **ADR-0028 compliant:** every resource carries the five platform taxonomy keys;
  the `$system=ml-monitoring` Grafana variable slots into the existing
  `platform_system` single-pane dashboards.

### Negative
- **Two tools to operate:** SREs need familiarity with both Evidently's
  `TestSuite` configuration and whylogs' `DatasetProfileView` schema.
- **Reference dataset management:** Evidently requires a stable reference dataset
  per `(model_name, tenant, domain)`. This must be versioned, refreshed after
  every retrain, and stored in GCS/S3 (fetched by the drift-exporter at startup).
- **Retrain storm risk:** multiple concurrent tenant alerts can fire multiple DAG
  runs. The 15-minute de-duplication window and 6-hour `repeat_interval` on the
  retrain route are the primary guards.
- **NetworkPolicy follow-up:** ML monitoring pods have broader egress than ideal
  until the Cilium policy layer (ADR-0019) is enabled in enforce mode.

### Risks
- **R3 — Multi-tenant drift isolation (Low).** Mitigation: namespace-per-model +
  per-`(tenant, domain)` metric labels + independent alert instances.
- **Airflow unavailability during WS-B ramp-up.** Mitigation: K8s Job fallback
  in the trigger proxy; Job path is independently tested.
- **Reference data staleness.** Mitigation: `promote_to_edge` DAG writes a
  reference-updated marker to GCS; drift-exporter watches and reloads. Tracked
  as a WS-B/WS-C integration acceptance criterion.
- **High-frequency alert → retrain storm.** Mitigation: `repeat_interval: 6h`
  on the retrain webhook route + 15-minute per-`(tenant, domain)` de-duplication
  in the proxy + Airflow serialises overlapping runs for the same `(tenant, domain)`.

## Implementation notes

This ADR is **planning-only.** The PR introduces:
- `apps/infra/ml-monitoring/` (ArgoCD Application + Helm chart for the
  drift-exporter and retrain-trigger)
- `apps/infra/observability/grafana-dashboards/templates/configmap-ml-drift.yaml`
  (new dashboard ConfigMap, following the `configmap-dashboards.yaml` convention)
- This ADR + `docs/adrs/README.md` update

No GCP resources are created. The drift-exporter and trigger-proxy are in-cluster
K8s workloads; GCS access for reference datasets uses GKE Workload Identity
(already present on `gcp-gke-gpu-nodepools`, reaffirmed ADR-0036 D6).

**Helm chart conventions (matching the repo):**
- Chart type: `application`; `apiVersion: v2`
- All resources carry the five ADR-0028 label keys in `metadata.labels`
- `values.yaml` parameterises image, resources, modelNamespaces
  (list of `{namespace, modelName, tenant, domain}`), drift thresholds,
  Airflow endpoint, and secret names
- ArgoCD Application: wave annotation `"20"` (after prometheus-stack wave 10),
  `automated: {prune: true, selfHeal: true}`, `syncOptions: [CreateNamespace=true]`
- `helm lint` and `kubeconform` validation required before merge

**Airflow REST API (doc-verified 2026-06-10):**
`POST /api/v1/dags/{dag_id}/dagRuns` is stable in Airflow 2.x and 3.x.
The proxy uses Basic auth from a K8s Secret mounted via ESO (ADR-0008 pattern).
Credentials reference: `airflow-api-credentials` ExternalSecret in the
`ml-monitoring` namespace.

- Effort: **M** (chart skeleton + two new Helm templates + Alertmanager route overlay)
- Rollback: the ArgoCD Application is independently revertible; removing the
  Alertmanager overlay stops ML-specific routing and the retrain webhook immediately
  without touching the main prometheus-stack.

## Revisit trigger

- **Evidently or whylogs ship a joint Prometheus-native SDK** covering both
  distribution profiling and model quality tests — collapse the two-tool split.
- **A managed drift-monitoring service on GCP** becomes Prometheus-federated
  without data egress — re-evaluate alternative A3.
- **Airflow REST API changes incompatibly** (Airflow 4.x deprecates `/api/v1/`)
  — update the trigger proxy endpoint; K8s Job fallback continues regardless.
- **More than 50 model namespaces** — evaluate whether per-namespace ServiceMonitors
  scale or require a federated aggregation approach.

## References

- Evidently AI Prometheus integration: <https://docs.evidentlyai.com/user-guide/monitoring/collector_service>
- whylogs Prometheus export (`prom_metrics_handler`):
  <https://whylogs.readthedocs.io/en/latest/integrations/prometheus.html>
- PSI thresholds (> 0.1 moderate, > 0.25 severe): industry standard
- Airflow REST API — `POST /api/v1/dags/{dag_id}/dagRuns`:
  <https://airflow.apache.org/docs/apache-airflow/stable/stable-rest-api-ref.html>
- Alertmanager webhook receiver: <https://prometheus.io/docs/alerting/latest/configuration/#webhook_config>
- `train_domain_adapter` DAG: `docs/transaction-analytics/04-training-pipeline.md`
- ADR-0028 (platform taxonomy — mandatory): [0028-unified-platform-tagging-and-labeling-taxonomy.md](0028-unified-platform-tagging-and-labeling-taxonomy.md)
- ADR-0026 (observability target architecture): [0026-observability-target-architecture.md](0026-observability-target-architecture.md)
- ADR-0036 (GKE ML infra, GKE Standard + Workload Identity): [0036-gke-ml-infra-parity-multiregion.md](0036-gke-ml-infra-parity-multiregion.md)
- ADR-0003 (Cilium CNI): [0003-cilium-over-aws-vpc-cni.md](0003-cilium-over-aws-vpc-cni.md)
- ADR-0008 (ESO for secrets): [0008-external-secrets-operator.md](0008-external-secrets-operator.md)
- In-repo: `apps/infra/observability/prometheus-stack/values.yaml` (Alertmanager
  baseline), `apps/infra/observability/grafana-dashboards/` (dashboard convention),
  `apps/infra/opencost/` (ArgoCD Application shape)

---
*Doc-verified 2026-06-10 against Evidently AI, whylogs, and Airflow REST API
documentation. Planning-only ADR — proposed, not yet implemented in
platform-design. WS-C "Model & ML Observability"; implementation apply-gated.*
