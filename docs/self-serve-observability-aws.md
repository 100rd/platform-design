# Self-Serve Observability — AWS ML Platform Onboarding

> **ADR reference:** [ADR-0039](adrs/0039-self-serve-observability.md) (cluster-agnostic;
> this doc is the AWS-specific companion to [docs/self-serve-observability.md](self-serve-observability.md))
> **Scope:** WS-D of the AWS ML Platform plan (`docs/aws-ml-platform/IMPLEMENTATION_PLAN.md`).
> **Backstage:** explicitly deferred — see ADR-0034 and the revisit conditions in ADR-0039.
> **Platform taxonomy:** ADR-0028 — every resource carries `platform:system = observability`.

AWS ML Platform teams (GPU training, inference serving, model pipeline, data, SRE)
follow the same self-serve path as GCP teams. This document covers the **AWS-specific
extension**: the `team-ml-platform-aws` example values, the GPU + EFA + Karpenter +
ML-pipeline dashboard panels, and the GPU alert rules.

---

## What you get (AWS extension)

In addition to the base self-serve resources (Grafana folder + starter dashboard +
base PrometheusRule + RBAC), AWS ML Platform teams with `aws.gpuPanels.enabled: true`
get:

| Resource | Kind | Namespace | Source ADR |
|---|---|---|---|
| `<team-slug>-grafana-aws-gpu` | ConfigMap (Grafana dashboard) | `observability` | ADR-0039/0044/0045/0046/0048 |
| `<team-slug>-aws-gpu-alerts` | PrometheusRule | Your workload namespace | ADR-0039/0044/0045/0048 |

### Dashboard panels (by section)

| Section | Panels | Metric source |
|---|---|---|
| GPU Compute | GPU Utilisation %, Framebuffer Memory used/free, Power Draw (W), XID Errors table | DCGM Exporter (ADR-0044 D2) |
| EFA Fabric (`efaPanels.enabled: true`) | Network throughput Rx/Tx (Bps), Packet rate Rx/Tx (pps) | `node_exporter` on EFA interface (ADR-0045) |
| Karpenter GPU Pool (`karpenterPanels.enabled: true`) | GPU Capacity vs Requests, Spot Disruptions (pods/hr) | Karpenter controller metrics (ADR-0046) |
| ML Pipeline (`mlPipelinePanels.enabled: true`) | Airflow DAG Run Duration P50/P95, Task Instances created vs failed | Airflow StatsD/OpenMetrics exporter (ADR-0048) |
| ML Observability (`ml.enabled: true`) | Dataset Drift Score, Model Accuracy, Retrain Triggers | Evidently / whylogs drift-exporter (ADR-0038/0048) |

### Alert rules (by group)

| Group | Alert | Severity | Condition |
|---|---|---|---|
| `<slug>-gpu-compute` | `<PREFIX>_GPULowUtilisation` | warning | GPU util < 10% for 30 min |
| `<slug>-gpu-compute` | `<PREFIX>_GPUMemorySaturation` | critical | GPU FB memory fill > 90% for 10 min |
| `<slug>-gpu-compute` | `<PREFIX>_GPUXIDError` | critical | XID error count > 0 (immediate) |
| `<slug>-efa-fabric` | `<PREFIX>_EFAReceiveSaturation` | warning | EFA Rx > ~80% of 100 Gbps for 5 min |
| `<slug>-ml-pipeline` | `<PREFIX>_AirflowHighTaskFailureRate` | warning | Airflow task failure rate > 10% for 5 min |

Thresholds are overridable in your team `values.yaml` via the `alerts.*` keys.

---

## Prerequisites

Before raising a PR, satisfy all base prerequisites from
[docs/self-serve-observability.md](self-serve-observability.md#prerequisites), plus:

4. **`aws-eks-gpu-*` cluster deployed (WS-A).** The DCGM Exporter DaemonSet
   (`apps/infra/dcgm-exporter`) must be running on the GPU NodePool. GPU panels
   show "No data" until the DCGM exporter is scraped by Prometheus.

5. **EFA interface name confirmed.** Check the interface name on your GPU instances:
   ```bash
   kubectl debug node/<node-name> -it --image=nicolaka/netshoot -- ip link show
   ```
   Default is `eth0`; override `aws.efaPanels.efaInterface` if your AMI differs.

6. **Airflow/MLflow deployed (WS-B).** Panels in the ML Pipeline section query
   `airflow_task_instance_*` metrics from the Airflow StatsD exporter. Set
   `aws.mlPipelinePanels.enabled: false` if WS-B is not yet deployed.

7. **Namespace exists.** The `ml-platform` namespace (for the `team-ml-platform-aws`
   example) is created by WS-B. For a new team, bootstrap the namespace in a
   separate PR first with ADR-0028 labels on the Namespace object.

---

## Step-by-step: raise a template PR

### 1. Copy the AWS example directory

```bash
cp -r apps/infra/grafana-self-serve/example-teams/team-ml-platform-aws \
       apps/infra/grafana-self-serve/example-teams/<your-team-slug>
```

### 2. Edit `values.yaml`

Fill in every required base field (see
[docs/self-serve-observability.md](self-serve-observability.md#2-edit-valuesyaml)),
then configure the AWS extensions:

```yaml
team:
  name: "Your Team Name"
  slug: "team-your-slug"          # lowercase, hyphens only
  namespace: "your-namespace"     # must already exist
  system: "your-system"           # ADR-0028 platform:system value
  owner: "team-your-slug"
  env: "production"
  grafanaServiceAccount: ""
  ciServiceAccount: "your-ci-sa"

ml:
  enabled: true                   # Set false until ml-monitoring (WS-C) is deployed
  modelName: ""                   # optional label filter
  tenant: ""                      # optional label filter

aws:
  gpuPanels:
    enabled: true                 # Set false for non-GPU AWS teams
    nodePoolLabel: "aws-eks-gpu"  # must match karpenter.sh/nodepool label (ADR-0046)
    dcgmMetricPrefix: "DCGM_FI_DEV"

  efaPanels:
    enabled: true                 # Set false if not on EFA pools (ADR-0045)
    efaInterface: "eth0"          # EFA interface name on GPU instances

  karpenterPanels:
    enabled: true
    gpuNodePoolName: "aws-eks-gpu-spot"  # Karpenter NodePool name (ADR-0046)

  mlPipelinePanels:
    enabled: true                 # Set false until Airflow/MLflow (WS-B) is deployed
    airflowNamespace: "ml-pipeline"
    mlflowNamespace: "ml-pipeline"

alerts:
  errorRateThreshold: "0.02"
  cpuSaturationThreshold: "0.85"
  memorySaturationThreshold: "0.90"
  availabilityFor: "5m"
  saturationFor: "10m"
  mlDriftThreshold: "0.2"
  mlAccuracyThreshold: "0.85"
  mlAlertFor: "10m"
  # GPU thresholds — override per your team's GPU SLOs.
  gpuUtilLowThreshold: "0.10"
  gpuMemSaturationThreshold: "0.90"
  gpuXidErrorThreshold: "0"
```

### 3. Edit `argocd-application.yaml`

Replace all `team-ml-platform-aws` references with your slug, and update
`spec.destination.namespace`:

```yaml
metadata:
  name: grafana-self-serve-<your-team-slug>
  labels:
    platform.owner: "<your-team-slug>"
spec:
  source:
    helm:
      valueFiles:
        - values.yaml
        - example-teams/<your-team-slug>/values.yaml
  destination:
    namespace: <your-namespace>
```

### 4. Raise the PR

```bash
git checkout -b feat/grafana-self-serve-<your-team-slug>
git add apps/infra/grafana-self-serve/example-teams/<your-team-slug>/
git commit -m "feat(observability): self-serve dashboards + alerts for <your-team-slug> (ADR-0039)"
gh pr create \
  --base main \
  --title "feat(observability): self-serve onboarding <your-team-slug>" \
  --body "ADR-0039 template PR. Team: <your-team-slug>. AWS GPU panels: yes/no. ml.enabled: yes/no."
```

### 5. Post-merge: apply ArgoCD Application

```bash
# Dry-run first (plan-only gate — apply is human-approved):
kubectl apply --dry-run=server \
  -f apps/infra/grafana-self-serve/example-teams/<your-team-slug>/argocd-application.yaml

# After human approval:
kubectl apply \
  -f apps/infra/grafana-self-serve/example-teams/<your-team-slug>/argocd-application.yaml
```

ArgoCD syncs at wave 30 (after all observability components at wave 10-20).

---

## Verify your onboarding

After the ArgoCD Application syncs:

1. **Dashboards visible in Grafana:**
   Navigate to **Dashboards > team-`<your-slug>`**. You should see:
   - `<your-slug>-starter.json` — base RED metrics + resource saturation
   - `<your-slug>-aws-gpu.json` — GPU + EFA + Karpenter + ML pipeline (if enabled)

2. **PrometheusRules loaded:**
   ```bash
   kubectl get prometheusrule -n <your-namespace>
   # Expect: <your-slug>-alerts  AND  <your-slug>-aws-gpu-alerts
   ```

3. **GPU metrics in Prometheus:**
   In Grafana Explore:
   ```promql
   DCGM_FI_DEV_GPU_UTIL{kubernetes_node=~".*aws-eks-gpu.*"}
   ```
   Should return time-series if DCGM Exporter is running.

4. **Alertmanager routing:**
   ```bash
   kubectl exec -n observability deploy/alertmanager -- \
     amtool alert query --alertname=TEAM_<YOUR_SLUG_UPPER>
   ```

---

## Troubleshooting

### GPU panels show "No data"

1. Check DCGM Exporter: `kubectl get ds -n gpu-monitoring dcgm-exporter`
2. Verify Prometheus scrapes it: query `DCGM_FI_DEV_GPU_UTIL` in Grafana Explore.
3. Verify `aws.gpuPanels.nodePoolLabel` matches the actual `karpenter.sh/nodepool`
   label on your nodes: `kubectl get node -l karpenter.sh/nodepool=<your-pool> -o name`.
4. Confirm WS-A is deployed and the cluster is healthy.

### EFA panels show "No data"

1. Verify `aws.efaPanels.efaInterface` matches the EFA interface name on your
   GPU instances.
2. Check node_exporter scrape configuration includes network interfaces.

### Karpenter panels show "No data"

1. Verify Karpenter metrics endpoint: `kubectl get svc -n karpenter karpenter -o yaml | grep metrics`.
2. Verify `aws.karpenterPanels.gpuNodePoolName` matches your NodePool:
   `kubectl get nodepools`.

### Airflow panels show "No data"

1. Confirm WS-B (`apps/infra/airflow`) is deployed in `aws.mlPipelinePanels.airflowNamespace`.
2. Check the Airflow StatsD exporter: `kubectl get svc -n ml-pipeline | grep statsd`.
3. Set `aws.mlPipelinePanels.enabled: false` if WS-B is not yet deployed.

---

## Reference

- [ADR-0039](adrs/0039-self-serve-observability.md) — self-serve observability decision
- [ADR-0034](adrs/0034-backstage-idp.md) — Backstage deferred (revisit criteria)
- [ADR-0028](adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md) — platform taxonomy
- [ADR-0044](adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md) — EKS GPU ML foundation (DCGM)
- [ADR-0045](adrs/0045-aws-efa-gpu-fabric-placement-groups.md) — EFA fabric
- [ADR-0046](adrs/0046-eks-node-strategy-karpenter-spot.md) — node strategy / Karpenter pools
- [ADR-0048](adrs/0048-aws-ml-cicd-registry-drift.md) — AWS ML CI/CD (Airflow/MLflow)
- [ADR-0026](adrs/0026-observability-target-architecture.md) — observability stack
- [ADR-0038](adrs/0038-ml-observability-drift.md) — ML drift/accuracy metrics
- [docs/self-serve-observability.md](self-serve-observability.md) — base onboarding runbook
- Chart: `apps/infra/grafana-self-serve/`
- AWS example: `apps/infra/grafana-self-serve/example-teams/team-ml-platform-aws/`
- AWS templates: `apps/infra/grafana-self-serve/templates/aws-gpu-dashboard.yaml`,
  `apps/infra/grafana-self-serve/templates/aws-gpu-prometheusrule.yaml`
- AWS ML Platform plan: `docs/aws-ml-platform/IMPLEMENTATION_PLAN.md` §4 WS-D
