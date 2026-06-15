# aws-eks-gpu-scheduling

> **ADR:** [0044](../../../docs/adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md) D2 (DRA device classes), D3 (Volcano gang scheduling). **WS-A.**
> **Status:** plan/validate-only, **default-OFF** (`enabled = false`). Apply-gated.

Volcano batch scheduler + fair-share queues + DRA device classes on EKS — combines the GKE `gke-gpu-scheduling` (Volcano) and the DRA device-class half of ADR-0044 D2 into one AWS module.

## What it does

- Deploys **Volcano** as a secondary scheduler with the **gang**, **dra**, **binpack** (GPU-weighted), **proportion**, and **nodeorder** plugins — native gang scheduling for distributed NCCL training over EFA (ADR-0044 D3). Chosen over Kueue (no native gang).
- Ships **DRA `DeviceClass`** objects (typed GPU requests by `productName`: H100 / A100 / B200) and **`ResourceClaimTemplate`s** (single-GPU / island / MIG) as `kubernetes_manifest` (ADR-0044 D2).
- Training / inference / batch fair-share **Queues**.

## ADR-0028 taxonomy

Kubernetes-plane labels (dotted keys): `platform.system = ml-platform`, `platform.component = gpu-scheduling`, plus caller `platform.*` keys (also on the DRA objects).

## Tests

`terraform test` (helm/kubernetes mocked) asserts default-OFF, Volcano deploy, the 3 default DeviceClasses + 2 ResourceClaimTemplates, empty-DRA tolerance, and ADR-0028 labels.
