# SPEC-07 — Observability

> Portable reverse-engineering of the platform's observability estate: metrics, logs,
> traces, profiles, GPU/ML observability, SLOs, alerting, and cost visibility. A
> competent platform team can rebuild the same observability plane for a new client
> from this document without reading the source repository.

---

## 1. Scope & non-goals

**Scope.** This spec defines the platform's **signal plane**: how metrics, logs, traces,
continuous profiles, GPU telemetry, ML-quality signals, and cost data are collected,
stored, queried, alerted on, and presented — across a fleet of Kubernetes clusters on
AWS (EKS), GCP (GKE), and bare-metal (Talos). It covers the Prometheus/Thanos + Grafana
LGTM-aligned stack, the VictoriaMetrics variant used on the largest GPU-inference
cluster, DCGM GPU observability (including the hardened auto-taint CronJob), the
Evidently+whylogs ML-drift stack, SLOs-as-code (Pyrra), the Alertmanager routing and
on-call philosophy, self-serve per-team observability, and the CI that validates all of
it. It also documents which signals the platform treats as **load-bearing** and how the
stack scales with cluster count.

**Non-goals.** (a) The **AI-SRE system** itself — its agents, MCP servers, orchestration,
and ClickHouse analytics store — is specified in **SPEC-09**; this spec covers only its
*monitoring-integration surface* (the `ai_sre_*` metrics it exposes and how they are
scraped), and cross-references SPEC-09 for everything else. (b) The **compute/GPU
substrate** (node pools, Karpenter, EFA/InfiniBand fabric, Talos) and the **network plane**
(Cilium, DNS) are owned by **SPEC-03** (compute/GPU day-2) and **SPEC-02** (network/DNS);
here we consume their signals, not provision them. (c) **Secret delivery** (External Secrets Operator, secret
stores) is owned by **SPEC-05**; here we only name the secrets we consume. (d)
**Progressive-delivery** analysis (Argo Rollouts / Kargo) is owned by the **SPEC-04**
delivery spec; we document the two analysis queries because they read the observability
plane.

---

## 2. Architecture

### 2.1 Signal-by-signal target (LGTM-aligned)

The estate ratifies a single coherent target per signal (source: `ADR-0026 Observability
target architecture`). Every "add a new tool" decision is gated as **additive vs
rip-and-replace**:

| Signal | Chosen tool | Long-term store | Explicitly rejected (either/or) |
|---|---|---|---|
| Metrics | **Prometheus 3.x** (native histograms on) | **Thanos on S3** | **Mimir** (same tier as Thanos — rip-and-replace) |
| Metrics (GPU-inference cluster) | **VictoriaMetrics cluster** (MetricsQL) | VM `vmstorage` | kube-prometheus-stack (too heavy at 5 000 GPU nodes) |
| Logs | **Loki** (SimpleScalable) | S3 | — |
| Traces | **Tempo** (distributed) + **OBI/Beyla** eBPF trace lane | S3 | — |
| RED metrics | **exactly one** source: **Tempo metrics-generator** | (remote-write → Prometheus) | OBI metrics **and** span-metrics (double-RED = double cost) |
| Profiles | **Pyroscope** (microservices) | S3 | — (ADR-0026 says *defer*; estate ships it — see §7) |
| Pipeline hub | **OTel Collector** (gateway + agent) | — | (ADR-0026 names *Alloy*; estate ships OTel — see §7) |
| SLO engine | **Pyrra** (built-in UI) → `PrometheusRule` | — | Sloth (generator-only, no UI) |
| Dashboards | **Grafana** (dashboards-as-code via ConfigMap sidecar) | — | Perses (optional) |
| K8s cost | **OpenCost** + AWS CUR/Athena | S3/Athena | Kubecost Enterprise (day-one) |
| CloudWatch bridge | **YACE** (yet-another-cloudwatch-exporter) | (into Prometheus) | — |

### 2.2 Data-flow diagram

```
                                   ┌──────────────────────── per workload cluster ────────────────────────┐
  targets                          │                                                                      │
  ───────                          │   ServiceMonitor / PodMonitor / PrometheusRule (CRDs)                 │
  app /metrics ───────────────────►│        │  discovered by                                              │
  kube-state-metrics ─────────────►│        ▼                                                              │
  node-exporter (DaemonSet) ──────►│   ┌──────────────┐  2h local     ┌──────────────┐  S3 (1y)           │
  DCGM exporter (GPU DaemonSet) ──►│   │ Prometheus   │──sidecar──────►│   Thanos     │───► {{ORG}}-thanos │
  cAdvisor / kubelet ─────────────►│   │  3.x (×2 HA) │               │ sidecar→store │      -metrics-* S3  │
  YACE (CloudWatch) ──────────────►│   └──────┬───────┘               └──────┬───────┘                    │
  Karpenter / ArgoCD / Cilium ────►│          │ native histograms            │ downsample raw30d/5m90d/1h1y│
                                   │          │                              ▼                             │
  app OTLP / Jaeger / Zipkin ─────►│   ┌──────────────┐   traces    ┌──────────────┐  Thanos Query        │
  OBI/Beyla (eBPF, DaemonSet) ────►│   │ OTel Collector│──otlp──────►│    Tempo     │  Frontend ◄── Grafana│
                                   │   │ gateway+agent │  metrics-gen└──────┬───────┘                     │
  Fluent Bit (log DaemonSet) ─────►│   └──────┬───────┘   ──RED remote-write─┘ → Prometheus               │
                                   │          │ logs                                                       │
  pod profiles (annotated) ───────►│   ┌──────▼───────┐         ┌──────────────┐        ┌──────────────┐   │
                                   │   │     Loki     │         │  Pyroscope   │        │ Alertmanager │   │
                                   │   │ (S3, 365d)   │         │ (S3, 7d)     │        │  (×3 quorum) │   │
                                   │   └──────────────┘         └──────────────┘        └──────┬───────┘   │
                                   │                                                          │ routes     │
                                   │   Pyrra ──► SLO recording+burn-rate PrometheusRules      ▼            │
                                   │   OpenCost ──► per-namespace $ (CUR/Athena reconciled)  Slack /       │
                                   └─────────────────────────────────────────────────────── PagerDuty ────┘
                                                    │ (single pane)
                                                    ▼
                                          ┌───────────────────┐
                                          │      Grafana      │  Prometheus + Thanos + Loki + Tempo +
                                          │  (dashboards-as-  │  Pyroscope + ClickHouse-AI-SRE datasources
                                          │   code, OAuth SSO)│
                                          └───────────────────┘
```

### 2.3 GPU-inference cluster variant (VictoriaMetrics)

The largest cluster (GPU inference, up to **5 000 GPU nodes**) replaces
kube-prometheus-stack + Thanos with a **VictoriaMetrics cluster** operated by the VM
Operator, which auto-converts the same Prometheus CRDs (`ServiceMonitor → VMServiceScrape`,
`PodMonitor → VMPodScrape`, `PrometheusRule → VMRule`). Rationale: ~10× lower memory per
active series and native clustering (no Thanos sidecar) at GPU-metric cardinality.
`vmagent` scrapes → `vminsert` → `vmstorage` (30d) → `vmselect`; `vmalert` evaluates
`VMRule`s; a co-located `alertmanager` fans out. HPA reads vLLM metrics from `vmselect`
via prometheus-adapter (`custom.metrics.k8s.io`).

### 2.4 Namespaces and identity

- Charts target namespace **`observability`** (LGTM components, Pyrra) or **`monitoring`**
  (prometheus-stack ArgoCD Application, team `PrometheusRule`s). *This split is real in
  the estate and a known drift — see §7.*
- Storage-backend identity is **mixed by design**: Thanos + YACE use **EKS Pod Identity**
  (no SA role annotation); Loki + Pyroscope use **IRSA**; Tempo uses **static S3 keys via
  ESO**. A rebuild should standardize on one (Pod Identity recommended) — see §6/§7.

---

## 3. Decision record

| Decision | Rationale | Trade-off accepted | Source ADR |
|---|---|---|---|
| LGTM-aligned target, one tool per signal; gate every addition as additive-vs-replace | Stops per-signal tool sprawl and paying for two overlapping long-term tiers | Multi-component stack to pin and operate; phased rollout | `ADR-0026` |
| Prometheus **3.x** with native histograms (`native-histograms`, `scrape-native-histograms`) | Lower-cardinality, higher-fidelity latency histograms; future OTLP path | Requires kube-prometheus-stack ≥66 / appVersion ≥3.0; migration is a deliberate config step | `ADR-0026` |
| **Thanos on S3**, not Mimir | Thanos already runs; Mimir is same-tier rip-and-replace for no needed capability | Operate querier/store/compactor; downsampling to keep 1y affordable | `ADR-0026` |
| **Exactly one** RED-metric source = Tempo metrics-generator (OBI metrics off) | Two RED sources = double series + reconciliation pain | OBI is trace-only; RED depends on Tempo generator being healthy | `ADR-0026`, `ADR-0019` |
| **VictoriaMetrics** for the GPU-inference cluster | ~10× memory efficiency + native clustering at 5 000-node GPU cardinality | A second metrics TSDB to know; MetricsQL≈PromQL but not identical | (gpu-inference cluster design) |
| **Pyrra** for SLOs-as-code (over Sloth) | Built-in SLO UI + generates recording/burn-rate `PrometheusRule`s | One more operator; dashboards-as-code escaping in JSON | `ADR-0026` |
| **OpenCost + AWS CUR/Athena** for K8s cost, reconciled to amortized bill | Per-namespace/workload $ that matches the invoice on an RI/SP/Spot estate | CUR→S3→Glue→Athena→IAM plumbing; cost lags the bill | `ADR-0027` |
| **DCGM exporter** per GPU node + **hardened auto-taint CronJob** | Turn XID/ECC/thermal faults into cordon actions without a human in the loop | CronJob needs `nodes: patch`; DCGM exporter must run privileged/root | `ADR-0044`, `ADR-0049/0050` |
| **ML observability** = whylogs (drift) + Evidently (accuracy) → Prometheus, reuse Grafana/Thanos/Alertmanager | Feature drift *and* model-quality as first-class Prom metrics; no second pane | Two tools to operate; reference-dataset lifecycle; retrain-storm risk | `ADR-0038` |
| **Alertmanager → Slack (warning) + PagerDuty (critical)**; drift-critical → retrain webhook | Severity-tiered routing; automated retrain on material drift | PagerDuty/Slack are external deps; retrain de-dup needed to avoid storms | `ADR-0038`, `ADR-0040` |
| **Self-serve observability** via templated Grafana folder + dashboard + `PrometheusRule` + RBAC per team, GitOps-delivered | Team autonomy without platform tickets or blast radius; no new operator | Second dashboard still needs a PR; Grafana folder RBAC is a one-time manual step | `ADR-0039` |
| **Backstage deferred**; ship lightweight self-serve first | Avoids an abandoned portal with no owner; template PR maps 1:1 to a future scaffolder | Less polished UX until three revisit conditions are met | `ADR-0039`, `ADR-0034` |
| **ML on-call track + tested runbooks**; repo-anchored SOC2 evidence | ML incidents get a rotation; auditors resolve controls to code+CI+runtime signal | ML PagerDuty service is a follow-up; matrix must be maintained | `ADR-0040` |
| Every metric/label carries the platform taxonomy (`platform_system` etc.) | Single-pane `$system` dashboards + multi-tenant isolation via label scoping | KSM `metricLabelsAllowlist` needed; dots→underscores in PromQL | `ADR-0028` |

---

## 4. Implementation blueprint

### 4.1 Directory layout

```
apps/infra/observability/
├── prometheus-stack/            # umbrella: kube-prometheus-stack + thanos subcharts
│   ├── Chart.yaml               # chart prometheus-stack v1.2.0, appVersion v3.12.0
│   ├── Chart.lock               # kube-prometheus-stack 86.2.0, thanos 15.7.29
│   ├── values.yaml              # HA Prometheus, native histograms, Grafana, Alertmanager
│   ├── values-thanos.yaml       # Thanos querier/store/compactor/downsampling
│   ├── values-production.yaml   # prod sizing (4h/90GB, shards 2, 16CPU/128Gi)
│   ├── argocd-application.yaml   # sync-wave "10", automated prune+selfHeal
│   └── templates/
│       ├── external-secrets.yaml         # grafana admin/oauth, alertmanager slack/pagerduty
│       ├── thanos-objstore-secret.yaml   # objstore config (bucket/endpoint), auth=PodIdentity
│       └── prometheusrules/slo-rules.yaml # SLI/SLO recording + alert rules + error budget
├── loki-stack/                  # Loki SimpleScalable + Fluent Bit DaemonSet
├── tempo/                       # Tempo distributed + metrics-generator (RED source)
├── otel-collector/              # gateway (Deployment) + agent (DaemonSet)
├── obi/                         # OBI/Beyla eBPF trace lane (DaemonSet)
├── pyroscope/                   # Pyroscope microservices + agent DaemonSet
├── yace/                        # CloudWatch → Prometheus bridge
├── pyrra/                       # SLO engine: ServiceLevelObjective CRDs
└── grafana-dashboards/          # dashboards-as-code (ConfigMap sidecar) + datasources

apps/infra/dcgm-exporter/        # GPU telemetry DaemonSet (GitOps app)
apps/infra/ml-monitoring/        # Evidently drift-exporter + whylogs + retrain-trigger
apps/infra/grafana-self-serve/   # per-team folder+dashboard+PrometheusRule+RBAC chart
apps/infra/victoriametrics/      # VM cluster Helm values (gpu-inference)
apps/infra/opencost/             # K8s cost allocation (ADR-0027)

terraform/modules/
├── aws-eks-gpu-dcgm/            # DCGM exporter + hardened auto-taint CronJob (EKS)
├── gpu-inference-dcgm/         # DCGM + in-module VMRule GPU alerts + tainter
├── baremetal-gpu-dcgm/         # DCGM (Talos) — least hardened, raw manifest CronJob
├── gpu-inference-victoriametrics/  # VMCluster CR (vminsert/vmselect/vmstorage)
└── monitoring/                 # legacy grafana.tf / prometheus.tf (superseded by charts)

k8s/monitoring/                 # dns-failover PrometheusRule + ServiceMonitor
ai-sre/observability/           # ai_sre_* metric definitions (SPEC-09 integration surface)
.github/workflows/ml-monitoring-baremetal-validate.yml  # helm-lint + yamllint + tg-validate
```

### 4.2 Prometheus (load-bearing config excerpt)

```yaml
# apps/infra/observability/prometheus-stack/values.yaml (sanitized excerpt)
kube-prometheus-stack:
  prometheus:
    prometheusSpec:
      replicas: 2                     # HA, pod-anti-affinity per hostname + zone-preferred
      retention: 2h                   # local; Thanos handles long-term (prod: 4h/90GB)
      retentionSize: "45GB"
      walCompression: true
      enableFeatures: [native-histograms, scrape-native-histograms]   # ADR-0026, Prom 3.x
      shards: 1                       # raise to 2-4 above ~5M samples/s (prod: 2)
      serviceMonitorNamespaceSelector: {any: true}     # discover across all namespaces
      ruleSelector: {matchLabels: {prometheus: kube-prometheus}}
      resources:                      # sized for ~10M active series @ 5k nodes/100k pods
        requests: {cpu: 4000m, memory: 32Gi}
        limits:   {cpu: 8000m, memory: 64Gi}
      externalLabels:                 # Thanos multi-cluster keys
        cluster: '{{ .Values.global.clusterName | default "{{CLUSTER_NAME}}" }}'
        region:  '{{ .Values.global.region | default "{{PRIMARY_REGION}}" }}'
        replica: $(POD_NAME)
      thanos:
        image: quay.io/thanos/thanos:v0.36.1
        objectStorageConfig: {existingSecret: {name: thanos-objstore-secret, key: objstore.yml}}
      priorityClassName: system-cluster-critical
  kube-state-metrics:
    metricLabelsAllowlist:            # ADR-0028: expose taxonomy for PromQL joins
      - "pods=[platform.system,platform.component,platform.env,platform.owner]"
```

### 4.3 Thanos long-term tier (from `values-thanos.yaml`)

- **Query Frontend** (2→3 replicas) with memcached results/label cache, 24h split-interval.
- **Query** dedups on `replica`/`prometheus_replica`; DNS-discovers sidecars + store-gateway.
- **Store Gateway** (2→3) index-cache 2→4GB, 50→100Gi gp3.
- **Compactor** (1, leader-elected) — **downsampling ENABLED**, retention
  **raw 30d / 5m 90d / 1h 1y** (prod 1h=365d).
- **Ruler DISABLED** (rules stay in Prometheus/kube-prometheus-stack).
- Object store: `s3://{{ORG}}-thanos-metrics-{{PRIMARY_REGION}}` (prod:
  `…-prod-…`), SSE-S3, 128MB part-size; lifecycle IA@30d → Glacier-IR@90d → delete@365d;
  auth via **EKS Pod Identity** (SA `thanos`, no role annotation).

### 4.4 Alertmanager routing (the on-call spine)

```yaml
# values.yaml → alertmanager.alertmanagerSpec.config (sanitized)
route:
  receiver: 'slack-general'
  group_by: ['alertname','cluster','namespace']
  group_wait: 30s ; group_interval: 5m ; repeat_interval: 4h
  routes:
  - matchers: [severity = critical]  # → PagerDuty AND Slack (continue:true)
    receiver: 'pagerduty-critical' ; continue: true ; group_wait: 10s ; repeat_interval: 5m
  - matchers: [severity = critical]
    receiver: 'slack-critical' ; group_wait: 10s
  - matchers: [team = platform]      # team fan-out
    receiver: 'slack-platform'
  - matchers: [namespace =~ "app-.*"]
    receiver: 'slack-apps'
  - matchers: [alertname = Watchdog] # dead-man's switch → null (verifies pipeline is alive)
    receiver: 'null'
inhibit_rules:                       # critical inhibits warning/info (same ns+alertname);
  # NodeDown inhibits PodNotReady; NodeDraining inhibits NodeFilesystemAlmostOutOfSpace
replicas: 3                          # quorum; PDB minAvailable 2
```

Secrets `alertmanager-slack-secret` and `alertmanager-pagerduty-secret` are mounted from
ESO at `/etc/alertmanager/secrets/<name>/…` and read via `*_file` directives (no plaintext
in values). **Severity model:** `critical` → PagerDuty page + `#alerts-critical`; `warning`
→ Slack only; `Watchdog` → null (its *absence* is the alert). ML-drift `critical` additionally
routes to a **retrain webhook** (see §4.7).

### 4.5 GPU observability — DCGM exporter + hardened auto-taint CronJob

DCGM exporter runs as a DaemonSet on GPU nodes (**must be privileged / `runAsUser: 0`** for
NVML), exposes `:9400/metrics`, scraped every 15–30 s. It emits GPU util, framebuffer
memory, temperature, power, **XID errors**, ECC SBE/DBE, NVLink bandwidth, and clock-throttle
reasons. Per cluster type:

| | EKS (`aws-eks-gpu-dcgm`) | GPU-inference (`gpu-inference-dcgm`) | Bare-metal (`baremetal-gpu-dcgm`) |
|---|---|---|---|
| DCGM chart | `4.2.3` | `4.5.0` (+ custom metrics CSV) | `3.6.1` |
| Tainter schedule | `*/5 * * * *` | `*/2 * * * *` | `*/2 * * * *` |
| Tainter image | `bitnami/kubectl:1.34` | `bitnami/kubectl:1.30` | `{{GHCR_REGISTRY}}/gpu-health-autotaint:0.1.0` |
| securityContext on tainter | **full** (drop-ALL, RO-root, non-root, uid 65532, seccomp RuntimeDefault) | hardened (drop-ALL, RO-root, uid 65534) | **none** (raw manifest — hardening gap) |
| In-module alert rules | no (via self-serve) | **yes — VMRule** | no |
| SM release label | `kube-prometheus-stack` | `victoria-metrics` | `victoria-metrics` |

The **hardened auto-taint CronJob** (the reference pattern) reads DCGM XID metrics and
cordons faulty nodes:

```hcl
# terraform/modules/gpu-inference-dcgm/main.tf — kubernetes_cron_job_v1.gpu_health_tainter
schedule            = var.taint_cron_schedule   # "*/2 * * * *"
concurrency_policy  = "Forbid"                  # never overlap
starting_deadline_seconds = 60
# container:
image   = "bitnami/kubectl:1.30"
command = ["/bin/sh","-c"]
args    = [<<-EOT
  set -euo pipefail
  wget -qO- http://dcgm-exporter.${namespace}.svc.cluster.local:9400/metrics \
    | grep '^dcgm_xid_errors_total' \
    | ... # parse hostname="" label + value
  # taint when XID >= threshold, untaint on recovery:
  kubectl taint node "$NODE" gpu-health=unhealthy:NoSchedule --overwrite
EOT
]
security_context {                              # container
  allow_privilege_escalation = false
  read_only_root_filesystem  = true
  run_as_non_root            = true
  run_as_user                = 65534
  capabilities { drop = ["ALL"] }
}
restart_policy = "Never" ; backoff_limit = 0
node_selector  = { "kubernetes.io/os" = "linux" }   # run on NON-GPU nodes (no chicken-and-egg)
# RBAC (in-module): ClusterRole nodes[get,list,patch] + pods[get,list] + metrics.k8s.io[get,list]
```

In-module GPU alert rules (VMRule, `gpu-inference-dcgm`):

| Alert | Condition | Severity | For |
|---|---|---|---|
| `GpuXidErrorDetected` | `increase(dcgm_xid_errors_total[2m]) >= {{XID_THRESHOLD}}` (1) | critical | 0m |
| `GpuXidErrorCriticalBurst` | `increase(dcgm_xid_errors_total[5m]) >= 5` | page | 0m |
| `GpuHighTemperature` | `dcgm_gpu_temp_celsius > {{TEMP_THRESHOLD}}` (85) | warning | 5m |
| `GpuCriticalTemperature` | `dcgm_gpu_temp_celsius > 95` | critical | 1m |
| `GpuDoubleBitEccError` | `increase(dcgm_ecc_dbe_volatile_total[5m]) > 0` | critical | 0m |
| `GpuSingleBitEccErrorRate` | `rate(dcgm_ecc_sbe_volatile_total[10m])*60 > 10` | warning | 5m |
| `GpuNvLinkBandwidthLow` | `dcgm_nvlink_bandwidth_total_mbps < 100 and on(...) dcgm_gpu_utilization > 50` | warning | 10m |
| `DcgmExporterDown` | `up{job="dcgm-exporter"} == 0` | warning | 2m |
| `GpuNodeTainted` | `kube_node_spec_taint{key="gpu-health",value="unhealthy"} == 1` | critical | 0m |

### 4.6 VictoriaMetrics (GPU-inference cluster)

```hcl
# terraform/modules/gpu-inference-victoriametrics/main.tf — VMCluster "gpu-inference-metrics"
retentionPeriod = "30d"
vminsert  { replicaCount = 3 ; resources req cpu2/mem4Gi lim cpu4/mem8Gi }
vmselect  { replicaCount = 3 ; cacheMountPath = "/select-cache" }
vmstorage { replicaCount = 3 ; storage gp3 500Gi ; storageDataPath = "/vmstorage-data" }
# scrapes: VMServiceScrape dcgm-exporter (15s), cilium-agent (30s); VMNodeScrape kubelet-cadvisor
```

> **Drift:** the app-level Helm values (`apps/infra/victoriametrics/values.yaml`) declare a
> *fuller* stack — 2/2/2 replicas + `replicationFactor: 2` + `vmagent`/`vmalert`/`alertmanager`
> + 100Gi — while the Terraform module defines only the `VMCluster` (3/3/3, 500Gi, no RF).
> A rebuild must pick one source of truth (see §7).

### 4.7 ML observability (drift + accuracy + retrain trigger)

Deployed as `apps/infra/ml-monitoring/` (ArgoCD wave `20`, after prometheus-stack wave 10):

- **whylogs** inline profiler → Pushgateway → feature distributions
  (`ml_monitoring_feature_psi_score`, `…_kl_divergence`, `…_dataset_drift_score`,
  `…_drift_detected`).
- **Evidently** `drift-exporter` Deployment (`:8001/metrics`, one per `(tenant,domain)`) →
  model quality (`ml_monitoring_model_accuracy`, `…_f1_score`, `…_precision/recall/rmse`,
  `…_test_suite_result`).
- **`ml-retrain-trigger`** Deployment (`:8080/webhook`, `:9090/metrics`) — receives the
  Alertmanager webhook, de-duplicates per `(tenant,domain)` in a 15-min window, calls
  Airflow `POST /api/v1/dags/train_domain_adapter/dagRuns`, falls back to a K8s Job on
  Airflow 5xx, and records `ml_monitoring_retrain_triggers_total{outcome}`.

Default drift thresholds (Helm `driftExporter.defaultThresholds`, per-tenant overridable):

| Metric | Warning | Critical | Window |
|---|---|---|---|
| `ml_monitoring_dataset_drift_score` | > 0.20 | > 0.40 | 1h |
| `ml_monitoring_feature_psi_score` | > 0.10 | > 0.25 | 1h |
| `ml_monitoring_feature_kl_divergence` | > 0.10 | > 0.30 | 1h |
| `ml_monitoring_model_accuracy` | < 0.85 | < 0.75 | 1h rolling |
| `ml_monitoring_model_f1_score` | < 0.80 | < 0.65 | 1h rolling |
| `ml_monitoring_drift_detected` | — | == 1 sustained 15m | — |

ML Alertmanager overlay (ships as a *commented-ready patch* per cloud): two routes matching
`platform_system=ml-monitoring, severity=critical` — one to `ml-drift-pagerduty`
(`continue: true`), one to `ml-retrain-webhook` (`repeat_interval: 6h` to prevent retrain
storms) → `http://ml-retrain-trigger.ml-monitoring.svc:8080/webhook`, bearer token from ESO.
Bare-metal adds a `cluster = {{CLUSTER_NAME}}` matcher and a Vault-backed token.

### 4.8 SLOs-as-code (Pyrra)

```yaml
# apps/infra/pyrra/templates/slo-availability.yaml — pyrra.dev/v1alpha1 ServiceLevelObjective
target: "99.9" ; window: 28d       # api-availability
indicator: {ratio: {errors: http_requests_total{job="api-server",code=~"5.."},
                    total:  http_requests_total{job="api-server"}, grouping: [handler]}}
# slo-latency.yaml: api-latency-p99, target 99, 28d, le="0.5" (≤500ms)
```

Pyrra (operator "kubernetes" mode, `genericRules.enabled`) generates the recording rules
and multi-window burn-rate `PrometheusRule`s; UI on `:9099`.

### 4.9 Dashboards-as-code

Grafana persistence is **off**; every dashboard is a ConfigMap labelled `grafana_dashboard:
"1"` (datasources labelled `grafana_datasource: "1"`), picked up by the Grafana sidecar.
Provisioned datasources: **Prometheus** (default), **Thanos** (long-range), **Loki**,
**Tempo** (tracesToLogs→Loki, tracesToMetrics→Prometheus), **Pyroscope**, and
**ClickHouse-AI-SRE** (SPEC-09). SSO via Google OAuth (`allowed_domains: {{DOMAIN}}`,
Admin allow-list by email); local admin break-glass stays enabled so an OAuth
misconfiguration cannot lock everyone out.

### 4.10 Ordering / dependencies (what must exist before what)

1. **Secret stores + ESO** (SPEC-05) — Thanos objstore config, Grafana admin/OAuth,
   Alertmanager Slack/PagerDuty, Tempo/Pyroscope S3, Airflow API creds.
2. **Object storage** — S3 buckets (Thanos, Loki, Tempo, Pyroscope) + CUR/Athena for cost;
   workload identity (Pod Identity/IRSA) bound.
3. **prometheus-stack** (ArgoCD wave 10) — Prometheus operator CRDs, Prometheus, Thanos,
   Grafana, Alertmanager, KSM, node-exporter. CRDs must exist before any `ServiceMonitor`/
   `PrometheusRule`.
4. **LGTM add-ons** (wave 10) — Loki+Fluent Bit, Tempo (+metrics-generator), OTel Collector,
   OBI, Pyroscope, YACE, Pyrra, grafana-dashboards.
5. **GPU DCGM** — after GPU node pools + GPU operator; then the auto-taint CronJob (needs
   `nodes: patch`).
6. **ml-monitoring** (wave 20) — after prometheus-stack; needs reference datasets in
   object storage + Airflow endpoint.
7. **grafana-self-serve** (wave 30) — after all observability; per-team Applications.

---

## 5. Parameterization table

| Placeholder | Meaning | Default in this estate | Resize guidance |
|---|---|---|---|
| `{{ORG}}` | org slug (bucket/prefix) | — | prefixes all S3 buckets |
| `{{PRIMARY_REGION}}` | metrics/logs/traces region | `us-east-1` | co-locate buckets + clusters |
| `{{SECRETS_REGION}}` | ESO ClusterSecretStore region *(spec-local)* | `eu-central-1` | region of the secret manager backing observability secrets |
| `{{CLUSTER_NAME}}` | Prometheus `externalLabels.cluster` *(spec-local)* | `eks-prod-{{PRIMARY_REGION}}` | unique per cluster (Thanos dedup key) |
| `{{DOMAIN}}` | root DNS / Grafana OAuth domain | `example.com` | `grafana.{{DOMAIN}}`, `runbooks.{{DOMAIN}}` |
| `{{PROD_ACCOUNT_ID}}` | AWS account for ECR/ARNs | `123456789012` | ECR registry for drift-exporter image |
| `{{GCP_PROJECT}}` | GCP project for GCS reference data *(spec-local)* | `your-project` | `gs://{{GCP_PROJECT}}-ml-reference-data` |
| `{{TENANT}}` / `{{DOMAIN_SLUG}}` | ML tenant / business domain *(spec-local)* | `tenant-acme` / `hft,rtb,insurance` | one namespace per `(tenant,domain)` |
| `{{PD_ROUTING_KEY}}` | PagerDuty service key *(spec-local, secret)* | ESO-sourced | separate ML routing key = follow-up |
| `{{SLACK_WEBHOOK}}` | Slack webhook URL *(spec-local, secret)* | ESO-sourced | per-channel receivers |

**Sizing knobs (defaults → resize):**

| Knob | Default (base → prod) | Resize rule |
|---|---|---|
| Prometheus replicas | 2 | keep 2 for HA; scale vertically first |
| Prometheus shards | 1 → 2 | +1 shard per ~5M samples/s |
| Prometheus resources | 4CPU/32Gi → 8CPU/64Gi (limit 8/64 → 16/128) | ~3KB × active series (~30GB @ 10M) |
| Prometheus local retention | 2h → 4h | Thanos owns long-term; keep small |
| Thanos downsample retention | raw 30d / 5m 90d / 1h 1y (prod 1h=365d) | lengthen 1h tier for longer trend history |
| Alertmanager replicas | 3 (PDB minAvailable 2) | quorum; do not drop below 3 |
| VM cluster (gpu-inference) | vminsert/vmselect/vmstorage 3/3/3, vmstorage 500Gi, 30d | scale `vmstorage` replicas + PVC with node count |
| DCGM scrape interval | 15s (VM) / 30s (Prom) | 15s for fast XID detection on large GPU fleets |
| Auto-taint schedule | `*/2` (GPU-inference/BM) / `*/5` (EKS) | tighten to `*/1` for very large fleets |
| Loki retention | 365d (values) *(README says 30d — reconcile)* | set per compliance (e.g. PCI-DSS 10.7 = 1y) |
| Tempo retention | 14d (336h) | traces are bulky; keep short |
| Pyroscope retention | 7d (168h) | profiles are bulky; keep short |
| ML drift thresholds | see §4.7 | override per `(tenant,domain)` |

---

## 6. Best practices distilled

1. **Ratify one tool per signal and gate every addition as additive-vs-rip-and-replace.**
   *Why:* the failure mode of observability is not "missing a tool" but "running two of the
   same tier" (Thanos+Mimir, Alloy+OTel, OBI-metrics+span-metrics). A written target turns
   every new tool into an explicit decision instead of quiet cost creep.
2. **Keep Prometheus local retention tiny (2–4h) and push everything to object storage via
   Thanos with downsampling.** *Why:* Prometheus RAM scales with active series; long local
   retention is the fastest way to OOM at fleet scale. Downsampling (5m/1h) is what makes a
   1-year window affordable.
3. **Emit exactly one RED-metric source.** *Why:* span-metrics from Tempo's generator, OBI
   eBPF metrics, and OTel span-metrics processors all produce the same `http_server_*`
   series. Two sources double cost and force reconciliation; pick the generator and turn
   the others off (OBI stays a *trace* lane).
4. **Dashboards and alert rules are code, never clicked.** *Why:* Grafana persistence off +
   ConfigMap sidecar + `PrometheusRule` CRDs make the whole signal-presentation layer
   GitOps-reconciled and reviewable; a UI edit that isn't in Git is drift by definition.
5. **Carry the platform taxonomy on every metric** (`platform_system/component/env/owner`
   via KSM `metricLabelsAllowlist`). *Why:* it enables one `$system` single-pane dashboard,
   PromQL cost joins (`… * on(pod,namespace) group_left(...) kube_pod_labels`), and
   structural multi-tenant isolation — separate series → separate alerts → no cross-tenant
   false pages.
6. **Tier alert severity to route, and run a dead-man's switch.** *Why:* `critical` →
   PagerDuty page, `warning` → Slack keeps humans un-fatigued; the always-firing `Watchdog`
   routed to `null` means *absence* of Watchdog proves the whole pipeline is alive. Add
   inhibition rules (node-down inhibits pod-not-ready) to kill alert storms at the source.
7. **Turn hardware faults into actions, safely.** *Why:* an XID/ECC/thermal fault should
   cordon the node without waiting for a human. The auto-taint CronJob does this, but runs
   **on non-GPU nodes** (no chicken-and-egg), with **least-privilege RBAC** (`nodes: patch`
   only) and a **fully hardened pod** (drop-ALL, read-only root, non-root, seccomp). The
   DCGM exporter itself is the *only* component allowed to be privileged/root — because NVML
   requires it.
8. **Make ML quality a first-class Prometheus signal, not a second pane.** *Why:* feeding
   whylogs drift and Evidently accuracy into the *same* Grafana/Thanos/Alertmanager stack
   means SREs debug models with the tools they already use, and a critical drift alert can
   automatically fire a retrain — with a de-dup window + `repeat_interval` guarding against
   retrain storms.
9. **Give teams self-serve rails, not tickets — with blast-radius fences.** *Why:* a
   templated folder + dashboard + `PrometheusRule` + namespace-scoped RBAC lets a team ship
   alerts by PR without touching platform rules; alert names are prefixed with the team slug
   (`{{SLUG}}_HighErrorRate`) to prevent `alertname` collisions, and a Kyverno label policy
   stops namespace-escape via label forgery.
10. **Reconcile cost to the real bill.** *Why:* naive K8s cost tools price against on-demand
    list rates and overstate spend on an RI/SP/Spot estate. OpenCost + CUR/Athena grounds
    per-namespace $ in the amortized, discounted invoice so the numbers are trusted.
11. **Standardize workload identity for storage backends.** *Why:* the estate mixes Pod
    Identity (Thanos/YACE), IRSA (Loki/Pyroscope), and static keys (Tempo). Static S3 keys
    are the one long-lived credential the security posture forbids elsewhere — a rebuild
    should put every backend on Pod Identity (or IRSA) and delete the static-key path.
12. **Validate the whole signal plane in CI without applying it.** *Why:* `helm lint` +
    `helm template` + `yamllint` + a taxonomy `grep` + `terragrunt validate` catch broken
    dashboards, unrenderable rules, and missing labels before merge — apply stays CI/CD-only
    from `main`.

---

## 7. Known pitfalls

1. **As-built divergence — ADR-0026 says "Alloy is the single pipeline hub; no separate OTel Collector" — but the
   estate ships a full standalone OTel Collector (gateway+agent) and no Alloy at all**, with
   Fluent Bit (not Alloy) shipping logs. The intent (one hub) holds, but the *tool* diverged.
   A rebuild should pick one — either adopt Alloy as ADR-0026 states, or amend the ADR to
   ratify OTel Collector as the hub — and not run both.
2. **As-built divergence — ADR-0026 says "defer Pyroscope" — but Pyroscope is fully deployed** (microservices,
   S3, agent DaemonSet). Either the ADR is stale or the defer was overridden; reconcile the
   decision record before a client audit.
3. **As-built divergence — namespace drift:** the prometheus-stack ArgoCD Application targets `monitoring` while
   the LGTM add-ons and datasource URLs reference `observability`; the Prometheus Service is
   referenced as both `…kube-prometheus-prometheus` and `…kube-prom-prometheus`. Pick one
   namespace and one service name or datasources silently point at nothing.
4. **As-built divergence — VictoriaMetrics has two conflicting definitions** — the Terraform `VMCluster` (3/3/3,
   500Gi, no `replicationFactor`, no `vmagent`/`vmalert`/`alertmanager`) vs the app Helm
   values (2/2/2, 100Gi, RF 2, full stack). Only one can be the source of truth.
5. **As-built divergence (confirm intent) — Loki retention conflict:** `limits_config.retention_period: 8760h` (365d, cited for
   PCI-DSS 10.7) in values vs a 30-day claim in the README. Confirm the real requirement —
   a 12× storage difference.
6. **As-built divergence — bare-metal auto-taint CronJob is the least hardened** — it's a raw
   `kubernetes_manifest` with **no securityContext, no resource limits, and no in-module
   RBAC** (RBAC "granted by the GitOps layer"). Bring it up to the GPU-inference module's
   hardened pattern before production.
7. **As-built divergence — DCGM exporter image tag drift:** Terraform pins `4.5.0-4.2.3-ubuntu22.04` while the app
   Helm values use `4.5.0-4.3.3-ubuntu22.04` (different DCGM version). Pin once.
8. **As-built divergence — `observability-check` queries raw `DCGM_FI_DEV_*` metric names, but the
   gpu-inference-dcgm CSV remaps them to `dcgm_*`.** If the remap CSV is loaded, the
   validation Job's queries return empty and the check fails for the wrong reason — align
   the metric names.
9. **Retrain-storm risk:** a high-frequency drift alert can fire multiple DAG runs. The
   defenses (15-min per-`(tenant,domain)` de-dup + `repeat_interval: 6h` + Airflow
   serialization) must all be present, or a flapping model floods the training cluster.
10. **Grafana folder RBAC and folder permissions are provisioned once and not reconciled by
    ArgoCD** — a UI edit to folder permissions silently persists. Document "edit values, not
    the UI" and treat the one-time Grafana service-account/user setup as a runbook step.
11. **Cross-namespace ESO for the retrain token:** the ml-monitoring chart creates
    `alertmanager-retrain-token` in the `ml-monitoring` namespace, but Alertmanager reads it
    from *its own* namespace — a second (Cluster)ExternalSecret is required or the webhook
    auth silently fails.
12. **Thanos Ruler is disabled** — all alerting evaluates in Prometheus. That's fine, but a
    long-range (multi-hour) alert expression that outlives local retention will not evaluate;
    keep alert lookbacks inside the 2–4h window or move them to a recording rule.
13. **`kubeScheduler`/`etcd`/`kubeProxy` default rules are toggled off for EKS** (managed
    control plane). On a self-managed or bare-metal cluster these must be re-enabled or you
    go blind on the control plane.

> **Recommendation:** items 1–8 are the estate's **As-built divergences** (scaffold-vs-target
> / drift gaps); reconcile them against the ADR set — especially the two ADR-0026
> contradictions (items 1–2) — and raise them with the ADR-set owner before a client rebuild.
> The finalizer collects these into SPEC-00's recommendations.

---

## 8. Acceptance checklist

A rebuild passes when:

- [ ] `kube-prometheus-stack` reports Prometheus **3.x** with `native-histograms` +
      `scrape-native-histograms` enabled; `prometheus --version` confirms ≥3.0.
- [ ] Thanos (not Mimir) is the long-term tier; compactor shows downsampling on with
      retention raw 30d / 5m 90d / 1h ≥1y; the S3 bucket receives blocks.
- [ ] Exactly **one** RED-metric source is active (Tempo metrics-generator); OBI metrics and
      OTel span-metrics are off (no duplicate `http_server_*` series).
- [ ] Grafana loads with all datasources green (Prometheus, Thanos, Loki, Tempo, Pyroscope,
      ClickHouse-AI-SRE) and OAuth SSO works with local-admin break-glass intact.
- [ ] Alertmanager has 3 replicas; a synthetic `critical` alert pages PagerDuty **and**
      posts to `#alerts-critical`; a `warning` posts to Slack only; `Watchdog` is silenced.
- [ ] `kube_pod_labels` carries `label_platform_system/component/env/owner` (KSM allowlist)
      and the `$system` single-pane dashboard renders.
- [ ] DCGM exporter is scraped on every GPU node; `DCGM_FI_DEV_GPU_UTIL` series count =
      GPU nodes × GPUs-per-node; XID/ECC/NVLink metrics present.
- [ ] The auto-taint CronJob runs on non-GPU nodes, has `nodes: patch` (only), a hardened
      pod (drop-ALL, RO-root, non-root, seccomp), and a forced XID → cordon works end-to-end.
- [ ] SLO `PrometheusRule`s from Pyrra exist (recording + multi-window burn-rate); the SLO
      dashboard shows availability + error budget.
- [ ] ml-monitoring drift-exporter (`:8001/metrics`) and retrain-trigger are up; a forced
      critical drift alert fires the retrain webhook and Airflow (or the K8s Job fallback)
      records `ml_monitoring_retrain_triggers_total{outcome="success"}`.
- [ ] OpenCost per-namespace cost reconciles to the amortized CUR invoice (RI/SP/Spot, not
      list price).
- [ ] A new team onboards by PR (values.yaml + Application) and gets a scoped folder,
      dashboard, `PrometheusRule`, and namespace RBAC — with **zero** platform tickets.
- [ ] CI (`ml-monitoring-baremetal-validate` + terraform/helm validate) is green: `helm
      lint`/`template`, `yamllint`, taxonomy `grep`, `terragrunt validate` — no apply.
- [ ] `tests/gpu-inference/observability-check.yaml` passes: VM healthy, all DCGM families
      present, ClickHouse logs reachable with recent rows, ≥1 alert rule evaluating.

---

## 9. Metrics / alerts inventory (reference tables)

### 9.1 System SLO alerts (`prometheus-stack/…/slo-rules.yaml`)

| Alert | Condition | Severity | Runbook |
|---|---|---|---|
| `APIServerAvailabilityBelowSLO` | `apiserver:availability:sli < 0.9995` (5m) | critical | `/slo/apiserver-availability` |
| `APIServerLatencyAboveSLO` | `apiserver:latency:p99:sli > 1s` (10m) | warning | `/slo/apiserver-latency` |
| `CoreDNSSuccessRateBelowSLO` | `coredns:success_rate:sli < 0.999` (5m) | critical | `/slo/coredns-availability` |
| `CoreDNSLatencyAboveSLO` | `coredns:latency:p99:sli > 30ms` (10m) | warning | `/slo/coredns-latency` |
| `PodStartupTimeAboveSLO` | `kubelet:pod_start_duration:p99 > 60s` (10m) | warning | `/slo/pod-startup-time` |
| `NetworkErrorRateAboveSLO` | `network:error_rate:sli > 10 err/s` (10m) | warning | `/slo/network-errors` |
| `PVCProvisioningSuccessRateBelowSLO` | `< 0.99` (10m) | warning | `/slo/pvc-provisioning` |
| `PVCProvisioningLatencyAboveSLO` | `p99 > 60s` (10m) | warning | `/slo/pvc-provisioning-latency` |
| `NodeAvailabilityBelowSLO` | `node:availability:sli < 0.99` (5m) | critical | `/slo/node-availability` |
| `NodeCPUSaturationAboveSLO` | `> 0.80` (15m) | warning | `/slo/cpu-saturation` |
| `NodeMemorySaturationAboveSLO` | `> 0.80` (15m) | warning | `/slo/memory-saturation` |
| `ErrorBudgetExhausted` | apiserver/coredns 30d budget `< 0` (1h) | critical | `/slo/error-budget-exhausted` |
| `ErrorBudgetCriticallyLow` | budget `< 10%` and `> 0` (1h) | warning | `/slo/error-budget-low` |

*Plus* the kube-prometheus-stack `defaultRules` bundle (alertmanager, k8s apps/resources/
storage/system, node-exporter, network, prometheus, kubeApiserver SLOs). `etcd`,
`kubeScheduler`, `kubeProxy` histogram/scheduler rules are **disabled** for EKS.

### 9.2 ML drift / accuracy alerts (`ml-monitoring/…/ml-drift-alerts.yaml`)

| Alert | Condition | Severity | Route |
|---|---|---|---|
| `MLDatasetDriftWarning` / `Critical` | `dataset_drift_score >` 0.20 / 0.40 (30m/15m) | warning / critical | Slack / +PagerDuty+retrain |
| `MLFeaturePSIWarning` / `Critical` | `feature_psi_score >` 0.10 / 0.25 | warning / critical | Slack / +retrain |
| `MLDriftDetected` | `drift_detected == 1` (15m) | critical | PagerDuty + retrain |
| `MLModelAccuracyWarning` / `Critical` | `model_accuracy <` 0.85 / 0.75 | warning / critical | Slack / +retrain |
| `MLModelF1Warning` / `Critical` | `model_f1_score <` 0.80 / 0.65 | warning / critical | Slack / — |
| `MLDriftExporterDown` | `up{job=~"ml-drift-exporter-.*"} == 0` (5m) | critical | PagerDuty |
| `MLRetrainTriggerFailures` | `rate(retrain_triggers_total{outcome!="success"}[15m]) > 0.1` (10m) | warning | Slack |

### 9.3 GPU / EFA / ML-pipeline alerts (self-serve AWS, `aws-gpu-prometheusrule.yaml`)

| Alert (team-prefixed) | Condition | Severity | For |
|---|---|---|---|
| `{{SLUG}}_GPULowUtilisation` | `avg DCGM_FI_DEV_GPU_UTIL/100 < 0.10` | warning | 30m |
| `{{SLUG}}_GPUMemorySaturation` | `FB_USED/(FB_USED+FB_FREE) > 0.90` | critical | 10m |
| `{{SLUG}}_GPUXIDError` | `DCGM_FI_DEV_XID_ERRORS > 0` | critical | 0m |
| `{{SLUG}}_EFAReceiveSaturation` | `rate(node_network_receive_bytes_total{efa}[5m]) > 1e10` (~80% of 100Gbps) | warning | 5m |
| `{{SLUG}}_AirflowHighTaskFailureRate` | Airflow task failure ratio `> 0.10` (15m) | warning | 5m |

*(GPU-inference in-module VMRule alerts are in §4.5; bare-metal Talos/IB/BGP/Ceph/etcd
self-serve alerts are catalogued below.)*

### 9.4 Bare-metal substrate alerts (self-serve, `baremetal-prometheusrule.yaml`)

`_TalosNodeDown` (critical), `_TalosVersionSkew`, `_TalosAPIdErrors`, `_IBConstraintErrors`,
`_NVLinkBandwidthLow`, `_CiliumBGPSessionDown` (critical, `cilium_bgp_peer_state != 3`),
`_CiliumBGPPrefixCountHigh`, `_CephHealthError` (critical) / `_CephHealthWarn`, `_CephOSDDown`,
`_CephPGsDegraded`, `_EtcdNoLeader` (critical), `_EtcdHighWALFsyncLatency`,
`_EtcdLeaderChanges`, `_KubeAPIServerLatencyHigh` — all thresholds Helm-value driven, all
runbooks `runbooks.{{DOMAIN}}/baremetal/<slug>`.

### 9.5 Self-serve base alerts (`grafana-self-serve/…/prometheusrule.yaml`)

`{{SLUG}}_HighErrorRate` (critical, 5xx ratio > 5%), `{{SLUG}}_ServiceDown` (critical),
`{{SLUG}}_HighCPUSaturation` / `{{SLUG}}_HighMemorySaturation` (warning, > 80%), and when
`ml.enabled`: `{{SLUG}}_MLDriftDetected` (warning, > 0.2), `{{SLUG}}_MLAccuracyDegraded`
(critical, < 0.85). Team RBAC: namespace-scoped Role granting
`prometheusrules` `[get,list,watch,create,update,patch,delete]`.

### 9.6 DNS-failover alerts (`k8s/monitoring/prometheus-rules.yaml`)

`DNSProviderDown` (critical, health < 20), `DNSFailoverInitiated` (critical),
`DNSSyncFailed` (critical), `DNSProviderDegraded` (warning, < 70), `DNSHighQueryLatency`
(warning, p95 > 500ms).

### 9.7 AI-SRE integration surface (SPEC-09 — monitoring integration only)

The AI-SRE orchestrator exposes `:9090/metrics` (scraped by a VictoriaMetrics
`VMServiceScrape`/scrape-config keyed on `app_kubernetes_io_name` + container port
`metrics`). Metrics: `ai_sre_investigation_duration_seconds` (histogram),
`ai_sre_investigation_total`, `ai_sre_tool_calls_total`, `ai_sre_tokens_used_total`,
`ai_sre_api_cost_dollars`, `ai_sre_daily_cost_usd`, `ai_sre_errors_total`,
`ai_sre_circuit_breaker_state`, `ai_sre_accuracy_ratio`, `ai_sre_advisories_generated_total`,
`ai_sre_feedback_total`, `ai_sre_active_investigations`, `ai_sre_system_info`. Alerting
(`ai-sre/k8s/orchestrator/vmalert-rules.yaml`): `AISRESystemDown` (critical),
`AISREHighErrorRate` (>30%), `AISRECircuitBreakerOpen` (critical), `AISREHighLatency`
(p95 > 120s), `AISREDailyCostHigh` (>$80) / `AISREDailyCostExceeded` (>$100, critical),
`AISRELowAccuracy` (<60%), `AISRESlackAppDown`. Its dashboards (`ai-sre/*.json`) query the
**ClickHouse-AI-SRE** datasource, not Prometheus. **Boundary:** the agents, MCP servers,
and analytics store are **SPEC-09**; this spec only guarantees the metrics land in the
metrics tier and are scraped.

### 9.8 Dashboard catalog

| Dashboard | Covers | Datasource |
|---|---|---|
| cluster-overview | EKS single-pane health, top consumers, active alerts | Prometheus |
| node-health | per-node CPU/mem/disk/net, Karpenter, spot cost | Prometheus |
| karpenter | provisioning latency P50/95/99, spot vs on-demand, consolidation | Prometheus |
| service-golden-signals | RED + saturation, data-links to Tempo | Prometheus/Tempo |
| service-slo | availability/latency SLO, error budget, burn rate | Prometheus |
| argocd-inventory / argocd-platform-overview | ArgoCD app health, sync, reconcile queue | Prometheus |
| kubernetes-overview | node/pod/PV from node-exporter+KSM | Prometheus |
| aws-infra-overview | AWS infra via YACE (NLB/ALB/S3/EBS/RDS/DynamoDB) | Prometheus |
| platform-system-overview | ADR-0028 unified `$system` taxonomy (EKS+RDS+S3+DynamoDB) | Prometheus |
| ml-drift-accuracy (+ `-aws`, `-baremetal`) | ML model accuracy + drift per substrate | Prometheus |
| clustermesh-status / multiregion-overview | Cilium ClusterMesh + multi-region active-active | Prometheus |
| go-application | Go app RED metrics | Prometheus |
| cilium-advanced-ebpf (repo `monitoring/`) | Cilium eBPF for gpu-inference; vLLM P99 during NCCL | Prometheus |
| provider-health (repo `monitoring/`) | DNS/provider health score | Prometheus |
| ai-sre-{accuracy,agent-usage,cost-roi,findings} | AI-SRE analytics (SPEC-09) | ClickHouse-AI-SRE |
| *(imported by gnetId)* kubernetes-cluster 7249, node-exporter 1860, prometheus-stats 19105, CoreDNS 14981, Karpenter 20524, EBS-CSI 16924, Cilium 16611, Hubble 16613 | community dashboards | Prometheus |

> **Note:** the grafana-dashboards README advertises `lokiOverview`, `tempoOverview`,
> `pyroscopeOverview`, and `serviceDeepDive` that are **not** present in the ConfigMap —
> aspirational, not shipped (§7).

### 9.9 Load-bearing signals

The platform treats these as the signals whose loss = flying blind (page/act on them
first): **API-server availability + p99 latency**, **CoreDNS success rate**, **node
Ready ratio**, **error-budget burn**, **GPU XID/ECC/thermal faults** (drive auto-taint),
**Tempo metrics-generator RED** (feeds Kargo/Rollouts promotion gates + golden-signals),
**Prometheus/Thanos + VictoriaMetrics up** (the metrics tier itself), **Alertmanager
quorum + Watchdog** (the alerting pipeline itself), **ML dataset-drift + accuracy** (drive
retrain), and **AI-SRE daily cost + circuit-breaker** (budget/safety guardrails).

### 9.10 Scaling the stack per cluster count

- **1–2 clusters:** single Prometheus HA pair per cluster + shared Thanos Query reading all
  sidecars; Grafana points at Thanos for cross-cluster views. Alertmanager per cluster.
- **10s of clusters:** shard Prometheus (2–4 shards) on high-volume clusters; Thanos Store
  Gateway + Query scale horizontally; use `externalLabels.cluster`/`region` for dedup;
  Grafana federates via the single Thanos datasource. KSM sharding once objects > ~10k.
- **The GPU-inference mega-cluster (up to 5 000 GPU nodes):** do **not** use
  kube-prometheus-stack — run VictoriaMetrics cluster (scale `vmstorage` replicas + PVC
  with node count, `replicationFactor 2`), DCGM scrape 15s, auto-taint `*/2`. This is the
  documented break-point where Prometheus RAM per series stops being economical.
- **Cost:** OpenCost is per-cluster; aggregate multi-cluster cost views come from CUR/Athena
  (account-level), not from stitching OpenCost instances.

### 9.11 Client-adaptation notes (self-hosted LGTM vs managed SaaS)

- **This estate deliberately chose self-hosted, OSS, Prometheus-native** (ADR-0026/0038):
  everything lands in one Grafana pane, no per-host/per-metric SaaS billing, and no data
  egress — the last point is a hard requirement for the financial-transaction domains (PII
  risk) and is *the* reason `ADR-0038` rejected managed ML-observability SaaS (Vertex Model
  Monitoring, Arize, Fiddler).
- **When a Datadog/New-Relic/Grafana-Cloud client is preferable:** small teams without SRE
  capacity to operate Thanos/Loki/Tempo/Pyroscope; when time-to-value beats cost; when the
  client already standardizes on a SaaS pane. The trade the estate accepts by staying
  self-hosted is **operational surface** (a multi-component stack to pin, upgrade, and
  scale) in exchange for **cost predictability + data residency + single-pane control**.
- **Portable adaptation path:** because dashboards, alert rules, and SLOs are all *code*
  (ConfigMaps, `PrometheusRule`, Pyrra CRDs) and metrics carry a stable taxonomy, a client
  can point the same instrumentation at a SaaS backend (OTLP export from the OTel gateway,
  Prometheus remote-write to Grafana Cloud/Datadog) with minimal rework — the collection
  layer is backend-agnostic; only the storage/query tier swaps.

---

## 10. Dependencies on other specs

- **SPEC-00 — Platform overview:** owns the global placeholder registry (`{{ORG}}`,
  `{{DOMAIN}}`, `{{PRIMARY_REGION}}`, account IDs). Register the spec-local placeholders
  introduced here (`{{SECRETS_REGION}}`, `{{CLUSTER_NAME}}`, `{{GCP_PROJECT}}`, `{{TENANT}}`,
  `{{DOMAIN_SLUG}}`, `{{PD_ROUTING_KEY}}`, `{{SLACK_WEBHOOK}}`, `{{GHCR_REGISTRY}}`).
- **SPEC-01 — Foundation IaC:** the Terraform modules and state backing the DCGM,
  VictoriaMetrics, and CUR/Athena resources this spec deploys.
- **SPEC-02 — Network & DNS:** the Cilium/BGP and DNS-failover signals consumed here
  (source of the `k8s/monitoring` DNS alerts and the Cilium dashboards).
- **SPEC-04 — Delivery & GitOps:** owns ArgoCD sync-wave ordering (obs wave 10,
  ml-monitoring wave 20, self-serve wave 30), app-of-apps, and the Kargo/Argo-Rollouts
  analysis templates that read the Tempo-generator RED metrics as promotion gates
  (`ADR-0021`).
- **SPEC-05 — Security:** External Secrets Operator + secret stores deliver every
  observability secret (Thanos objstore, Grafana admin/OAuth, Alertmanager Slack/PagerDuty,
  Tempo/Pyroscope S3, Airflow API creds, ML retrain token); the Kyverno
  `require-platform-labels` policy enforces the taxonomy self-serve depends on; the SOC2
  matrix (`ADR-0040`) treats this observability plane as the runtime evidence store.
- **SPEC-06 — CI/CD & quality:** owns the CI framework the `ml-monitoring-baremetal-validate`
  workflow and terraform/helm validation loops run within.
- **SPEC-09 — AI-SRE:** the AI-SRE system, ClickHouse analytics store, and agents. This spec
  consumes only its `ai_sre_*` metric surface + alerting; observability *scrapes and pages
  on* AI-SRE while AI-SRE *reads* this plane (metrics MCP) — but AI-SRE internals are SPEC-09.
- **SPEC-03 — Compute/GPU day-2:** provisions GPU node pools, the GPU operator, Karpenter,
  EFA/IB fabric, and Talos; the DCGM exporter and auto-taint CronJob attach to their signals.
- **SPEC-10 — ML / GPU-inference surface:** owns the model-serving (vLLM), the training
  pipeline (Airflow `train_domain_adapter`), and the GPU-inference cluster whose signals this
  spec collects — DCGM telemetry, drift/accuracy metrics, vLLM HPA metrics, and the retrain
  trigger all attach to SPEC-10's workloads.

---

*Source ADRs cited: ADR-0019 (OBI/Beyla→Tempo), ADR-0021 (Prometheus analysis gates),
ADR-0026 (observability target architecture), ADR-0027 (OpenCost + CUR/Athena),
ADR-0028 (platform taxonomy), ADR-0034 (Backstage deferred), ADR-0038 (ML drift),
ADR-0039 (self-serve observability), ADR-0040 (SOC2 posture + ML on-call),
ADR-0044/0045 (AWS GPU/EFA), ADR-0048 (AWS ML CI/CD), ADR-0049/0050 (bare-metal GPU/Talos).*
