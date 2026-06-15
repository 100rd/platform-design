# aws-eks-gpu-dcgm

> **ADR:** [0044](../../../docs/adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md) D1 (DCGM telemetry + auto-taint). Metrics stack per ADR-0026. **WS-A.**
> **Status:** plan/validate-only, **default-OFF** (`enabled = false`). Apply-gated.

DCGM Exporter + GPU-health auto-taint on EKS — the AWS mirror of `gke-gpu-dcgm` / `gpu-inference-dcgm`.

## What it does

- Deploys the NVIDIA **DCGM exporter** DaemonSet (utilisation / memory / temperature / power / XID / ECC) on GPU nodes.
- Renders a **ServiceMonitor** (chart-side, no `kubernetes_manifest`) so the region's Prometheus/VictoriaMetrics stack (ADR-0026) scrapes it; selected by the `release` label.
- Deploys an optional **GPU-health auto-taint CronJob** (ServiceAccount + node-patch RBAC) that taints nodes hitting XID/ECC/temperature thresholds (ADR-0044 D1).

## ADR-0028 taxonomy

Kubernetes-plane labels (dotted keys): `platform.system = ml-platform`, `platform.component = gpu-dcgm`, plus caller `platform.*` keys.

## Tests

`terraform test` (helm/kubernetes mocked) asserts default-OFF, exporter + auto-taint deploy, the auto-taint toggle, and ADR-0028 labels.
