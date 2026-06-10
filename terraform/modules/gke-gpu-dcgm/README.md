# gke-gpu-dcgm

Deploys the **NVIDIA DCGM exporter** as a DaemonSet on **GKE** GPU nodes via
`helm_release`, exposing GPU metrics (utilisation, memory, temperature, power,
XID/ECC errors) on `:9400` for **Prometheus / VictoriaMetrics** scrape. Part of
**WS-A** of the GCP ML Platform. System: `ml-infra`.

## What it creates

| Resource | Purpose |
|----------|---------|
| `kubernetes_namespace.dcgm` | Namespace for the exporter, labeled per ADR-0028. |
| `helm_release.dcgm_exporter` | DCGM exporter DaemonSet + (optionally) a ServiceMonitor. |

Both are gated by `var.enabled`.

## Metrics scrape

The chart renders a Prometheus-Operator **ServiceMonitor** when
`create_service_monitor = true` (default). The ServiceMonitor carries a `release`
label (`service_monitor_release_label`, default `victoria-metrics`) so the
Prometheus/VictoriaMetrics operator selects it. Set `create_service_monitor = false`
for backends that scrape via plain pod annotations.

The module deliberately avoids `kubernetes_manifest` (which requires a live cluster
at plan time) by rendering the ServiceMonitor through the chart's own
`serviceMonitor.enabled` value — this keeps the module fully `terraform validate`-
and `terraform test`-able with mocked providers.

## ADR-0028 labeling

Kubernetes-plane labels use **dotted** keys. The namespace and exporter pods carry:
`platform.system = ml-infra`, `platform.component = observability`,
`platform.managed-by = terragrunt`, merged with any `platform_labels` overrides.

## Usage

```hcl
module "dcgm" {
  source = "../../terraform/modules/gke-gpu-dcgm"

  enabled       = true
  chart_version = "3.6.1"

  gpu_node_selector = { "cloud.google.com/gke-accelerator" = "nvidia-l4" }

  service_monitor_release_label = "victoria-metrics"

  platform_labels = {
    "platform.env"   = "production"
    "platform.owner" = "team-data"
  }
}
```

## Testing

```bash
terraform init -backend=false
terraform test
```

Tests mock the `helm` and `kubernetes` providers — no cluster or credentials needed.

## Network isolation (follow-up)

This module creates the `gpu-monitoring` namespace but does **not** ship a NetworkPolicy. The
EKS gpu-inference stack pairs every GPU namespace with a default-deny baseline plus
scoped allow rules (see `network-policies/gpu-inference/00-default-deny.yaml`). The
GKE side needs the same: a **default-deny CiliumNetworkPolicy** for `gpu-monitoring` plus
scoped-allow policies (DNS/kube-api, metrics scrape, and the specific peers this
component talks to).

This is **required** for parity and is **deferred to the GitOps / network-policies
layer** (Dataplane V2 / Cilium), not implemented in this Terraform module. Tracking
item for the network-policies workstream.
