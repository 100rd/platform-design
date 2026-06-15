# aws-eks-gpu-operator

> **ADR:** [0044](../../../docs/adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md) D1 (NVIDIA GPU Operator), D2 (DRA driver). Node OS per [0030](../../../docs/adrs/0030-bottlerocket-node-os.md). **WS-A.**
> **Status:** plan/validate-only, **default-OFF** (`enabled = false`). Apply-gated.

NVIDIA GPU Operator on EKS — the AWS mirror of `gke-gpu-operator`.

## What it does

- Installs the NVIDIA GPU Operator via Helm: GFD / NFD / CDI / device plugin + the **NVIDIA DRA driver** (publishes `ResourceSlice`s for typed GPU requests, ADR-0044 D2).
- **Bottlerocket delta (ADR-0044 D1):** on `node_os = bottlerocket` (ADR-0030 default) the driver/toolkit are pre-baked into the GPU AMI, so `driver_enabled` is **false**; on `al2023` the operator installs the driver (`driver_enabled = true`). Derived automatically from `node_os` unless overridden.
- **DCGM disabled** in the operator (`dcgmExporter.enabled = false`) — DCGM is owned by `aws-eks-gpu-dcgm`.

## ADR-0028 taxonomy

Kubernetes-plane labels (dotted keys): `platform.system = ml-platform`, `platform.component = gpu-operator`, plus caller `platform.*` keys.

## Tests

`terraform test` (helm/kubernetes mocked) asserts default-OFF, pinned chart version, the Bottlerocket-vs-AL2023 driver toggle, and ADR-0028 labels.
