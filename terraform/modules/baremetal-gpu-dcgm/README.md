# baremetal-gpu-dcgm

**NVIDIA DCGM exporter + GPU-health auto-taint** for the Talos GPU nodes. Part of **WS-A**
of the Bare-Metal ML Platform. System: `ml-infra`.

**ADRs:** [ADR-0049](../../../docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
(foundation), [ADR-0050](../../../docs/adrs/0050-talos-gpu-driver-system-extensions.md)
(GPU driver / post-update gate). ADR-0028 labels.

## What it creates (when `enabled = true`)

| Resource | Purpose |
|----------|---------|
| `kubernetes_namespace.dcgm` | Namespace, ADR-0028 labels + `monitoring=true` |
| `helm_release.dcgm_exporter` | DCGM exporter DaemonSet + ServiceMonitor (XID/temp/ECC/NVLink/power/util) |
| `kubernetes_manifest.gpu_health_autotaint` | (gated) CronJob that taints a node `NoSchedule` on an XID-error burst |

DCGM metrics flow to **VictoriaMetrics/Prometheus** via the chart's ServiceMonitor
(`release = victoria-metrics`). The **GPU-health auto-taint** CronJob ports the EKS
`gpu-inference-dcgm` behaviour and honours `ai-sre/knowledge/gpu-driver-updates.md`: a
simulated XID burst above `xid_error_threshold` taints the node out of scheduling.

## Apply-gated

`var.enabled` defaults **false**. Providers mocked at plan time — no live cluster, no Helm
install. No `terraform apply` in this repo.

## ADR-0028 labeling

Dotted keys: `platform.system = ml-infra`, `platform.component = observability`,
`platform.managed-by = terragrunt`, plus `platform_labels` overrides.

## Testing

```bash
terraform init -backend=false
terraform test
```
