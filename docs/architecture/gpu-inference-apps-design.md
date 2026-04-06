# GPU Inference Cluster -- Apps & ArgoCD Alignment Design

**Status**: Approved
**Author**: Solution Architect
**Date**: 2026-04-06

---

## 1. Context

The platform has a new `gpu-inference` cluster (EKS 1.35, p5.48xlarge H100 nodes) that diverges
from the standard cluster design in several key areas:

| Concern | Standard Clusters | GPU Inference Cluster |
|---------|-------------------|-----------------------|
| CNI mode | Cilium ENI (VPC-routable IPs) | Cilium native routing + BGP + WireGuard |
| Monitoring | kube-prometheus-stack + Thanos | VictoriaMetrics Operator v0.68 |
| Logging | Loki stack | Vector + ClickHouse (out of scope for this PR) |
| GPU scheduling | N/A | Volcano v1.8 + DRA |
| GPU drivers | N/A | NVIDIA GPU Operator v26.3 + DRA driver |
| GPU metrics | N/A | NVIDIA DCGM Exporter v4.5 |

The existing `argocd/applicationset.yaml` deploys `apps/infra/*` to every cluster with a single
values file per chart. The gpu-inference cluster requires:

1. **Different values** for shared charts (Cilium)
2. **New charts** not needed on standard clusters (gpu-operator, volcano, dcgm-exporter)
3. **Replacement charts** for the observability stack (VictoriaMetrics instead of Prometheus)

## 2. Design Decisions

### 2.1 Cluster Identification

The gpu-inference cluster is identified by the ArgoCD cluster label:

```yaml
cluster-type: gpu-inference
```

All selectors in ApplicationSets use this label for inclusion/exclusion.

### 2.2 Existing ApplicationSet Modification

**`argocd/applicationset.yaml` (platform-infra)**:

The existing ApplicationSet deploys all `apps/infra/*` charts. We add a `matchExpressions` filter
to exclude `gpu-inference` clusters:

```yaml
clusters:
  selector:
    matchExpressions:
      - key: cluster-type
        operator: NotIn
        values:
          - gpu-inference
```

This means the gpu-inference cluster does NOT receive the standard infra apps via this
ApplicationSet. Instead, it gets its own dedicated ApplicationSet.

**Rationale**: The gpu-inference cluster has fundamentally different observability and networking
stacks. Trying to conditionally template every chart via `ignoreMissingValueFiles` would be fragile
and hard to audit. A separate ApplicationSet is cleaner.

### 2.3 New ApplicationSet: `applicationset-gpu-inference.yaml`

A dedicated ApplicationSet targets only `cluster-type: gpu-inference` clusters. It uses a matrix
generator combining:

- **Git directories generator**: scans `apps/infra/*` for charts
- **Cluster generator**: selects only gpu-inference clusters
- **Helm value override**: loads `values-gpu-inference.yaml` alongside `values.yaml`

The template uses `ignoreMissingValueFiles: true` so charts without a gpu-inference override file
still deploy with their defaults.

### 2.4 Chart Strategy

| Chart | Action | Notes |
|-------|--------|-------|
| `cilium` | Add `values-gpu-inference.yaml` | Native routing + BGP + WireGuard overlay |
| `gpu-operator` | New chart | Wraps NVIDIA GPU Operator v26.3 upstream |
| `victoriametrics` | New chart | Replaces prometheus-stack on gpu-inference |
| `volcano` | New chart | Gang scheduling + DRA integration |
| `dcgm-exporter` | New chart | GPU health metrics + auto-taint |
| `cert-manager` | No change | Deploys as-is (shared infra) |
| `external-dns` | No change | Deploys as-is (shared infra) |
| `external-secrets` | No change | Deploys as-is (shared infra) |
| `gatekeeper` | No change | Deploys as-is (shared infra) |
| `kyverno` | No change | Deploys as-is (shared infra) |
| `velero` | No change | Deploys as-is (shared infra) |
| `otel-operator` | No change | Deploys as-is (shared infra) |
| `rabbitmq-operator` | No change | Deploys as-is (shared infra) |
| `kargo` | No change | Deploys as-is (shared infra) |
| `observability/*` | Excluded | gpu-inference uses VictoriaMetrics, not Prometheus/Loki |

### 2.5 Observability Exclusion

The `apps/infra/observability/*` subdirectory (prometheus-stack, loki-stack, grafana-dashboards,
otel-collector, pyroscope, tempo) is **excluded** from the gpu-inference ApplicationSet. The
gpu-inference cluster uses VictoriaMetrics + Vector + ClickHouse instead.

The gpu-inference ApplicationSet explicitly lists only `apps/infra/*` (one level) and does NOT
include `apps/infra/observability/*`.

### 2.6 Values File Convention

For charts that need gpu-inference-specific configuration:

```
apps/infra/{chart}/
  Chart.yaml
  values.yaml                    # Standard cluster values (unchanged)
  values-gpu-inference.yaml      # GPU inference cluster overrides
  README.md
```

The ApplicationSet template loads both files in order:
1. `values.yaml` (base)
2. `values-gpu-inference.yaml` (override, merged on top)

This means `values-gpu-inference.yaml` only needs to contain the **delta** from the base values.

## 3. New Chart Specifications

### 3.1 gpu-operator

- **Upstream**: `nvidia/gpu-operator` from `https://helm.ngc.nvidia.com/nvidia`
- **Version**: 26.3.x (appVersion matches GPU Operator v26.3)
- **Key config**: DRA driver enabled, MIG strategy `mixed`, device plugin and DCGM integration
- **Node selector**: `node.kubernetes.io/instance-type` matching p5 family
- **Tolerations**: Tolerates `nvidia.com/gpu` taint

### 3.2 victoriametrics

- **Upstream**: `victoria-metrics-operator` from `https://victoriametrics.github.io/helm-charts`
- **Version**: 0.68.x
- **Key config**: VMCluster (storage + select + insert), VMAgent for scraping, VMAlert for rules
- **Replaces**: kube-prometheus-stack on gpu-inference clusters
- **Retention**: 30 days local, S3 for long-term via VMBackup

### 3.3 volcano

- **Upstream**: `volcano` from `https://volcano-sh.github.io/helm-charts`
- **Version**: 1.8.x
- **Key config**: Gang scheduling, DRA integration, GPU-aware queue policies
- **Queue**: `gpu-inference` queue with guaranteed GPU resources

### 3.4 dcgm-exporter

- **Upstream**: `dcgm-exporter` from `https://nvidia.github.io/dcgm-exporter/helm-charts`
- **Version**: 4.5.x
- **Key config**: All 7 DCGM metric families, health auto-taint via sidecar
- **Integration**: ServiceMonitor for VictoriaMetrics scraping

## 4. ApplicationSet Topology

```
argocd/
  applicationset.yaml               # Standard clusters (excludes gpu-inference)
  applicationset-gpu-inference.yaml  # GPU inference cluster only
  applicationset-multicluster.yaml   # Multi-cluster staging (unchanged)
  applicationset-workloads.yaml      # Team workloads (unchanged)
```

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| GPU Operator CRDs conflict with existing cluster CRDs | gpu-operator only deploys to gpu-inference clusters |
| Cilium BGP misconfiguration breaks pod networking | values-gpu-inference.yaml tested in dev cluster first |
| VictoriaMetrics missing Prometheus-compatible rules | VM Operator supports PrometheusRule CRD natively |
| Volcano scheduler conflicts with default scheduler | Volcano is additional scheduler, not replacement |
| DCGM auto-taint false positives | Configurable thresholds, starts in warn-only mode |

## 6. Future Work

- Vector + ClickHouse logging charts (separate PR)
- Crossplane + ArgoCD hub-and-spoke fleet management charts
- Kata Containers runtime class configuration
- vLLM inference deployment charts (workload-level, not infra)
- GPU cluster autoscaling with Karpenter NodePool for p5 instances
