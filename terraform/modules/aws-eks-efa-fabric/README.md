# aws-eks-efa-fabric

> **ADR:** [0045](../../../docs/adrs/0045-aws-efa-gpu-fabric-placement-groups.md) D2 (device-plugin under Karpenter), D3 (DRA on managed node groups), D4 (the `mode` switch). Gated on node strategy [0046](../../../docs/adrs/0046-eks-node-strategy-karpenter-spot.md). **WS-A.**
> **Status:** plan/validate-only, **default-OFF** (`enabled = false`). Apply-gated.

EFA exposure for the AWS EKS GPU plane — the AWS mirror of the GKE `gke-gpu-fabric` / `gke-gpu-dranet` split, folded into one module with a `mode` switch.

## What it does

- **`mode = device-plugin`** → `aws-efa-k8s-device-plugin` DaemonSet; pods request `vpc.amazonaws.com/efa`. The **only** valid mode under Karpenter (ADR-0045 D2).
- **`mode = dra`** → EFA DRA driver + a **netdev `DeviceClass` / `ResourceClaimTemplate`** that composes with the GPU `ResourceClaim` (so Volcano gang-schedules GPU + EFA NIC as one unit). Valid **only** on managed node groups (ADR-0045 D3).
- Ships the **OFI-NCCL config** (`FI_PROVIDER=efa` …) as a ConfigMap for NCCL workloads (both modes).
- **Load-bearing guard:** a `precondition` fails the plan if `mode = dra` is paired with `provisioner = karpenter` (the EFA DRA driver is unsupported under Karpenter — ADR-0045's load-bearing constraint; ADR-0046's CI check).

## ADR-0028 taxonomy

Kubernetes-plane labels (dotted keys): `platform.system = ml-platform`, `platform.component = gpu-fabric`, plus caller keys (on every fabric object).

## Tests

`terraform test` asserts default-OFF, both modes, the DRA-under-Karpenter rejection (`expect_failures` on the guard), and ADR-0028 labels.
