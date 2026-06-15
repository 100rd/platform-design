# aws-eks-gpu-managed-nodegroup

> **ADR:** [0046](../../../docs/adrs/0046-eks-node-strategy-karpenter-spot.md) D2 (managed node group for reserved training), D4 (Capacity Blocks), [0045](../../../docs/adrs/0045-aws-efa-gpu-fabric-placement-groups.md) D3 (EFA DRA path). **WS-A.**
> **Status:** plan/validate-only, **default-OFF** (`enabled = false`). Apply-gated.

The narrow EKS managed node group for large, reserved-capacity distributed training that wants the **EFA DRA topology model** — the AWS node-strategy piece the GKE etalon got for free.

## What it does

- Creates an `aws_eks_node_group` for reserved EFA-DRA training (ADR-0046 D2). This is the **only** path to the EFA DRA driver — Karpenter cannot run it (ADR-0045 D2/D3); everything elastic stays on `aws-eks-gpu-nodepools`.
- Capacity is **ON_DEMAND** or a **Capacity Block** (ADR-0046 D4) — `SPOT` is rejected by validation (no spot mid-NCCL gang job, ADR-0046 A4).
- EFA NICs exposed via `efa_mode = dra`; pins the cluster placement group + single AZ (ADR-0045 D1). GPU + `training-reserved` taints; `ignore_changes` on `desired_size` so a running job is not disrupted.
- Optional minimal node IAM role when the caller does not pass one.

## ADR-0028 taxonomy

`platform:system = ml-platform`, `platform:component = gpu-compute`, `platform:efa-mode = dra`, `platform:capacity`, plus caller keys; dotted `platform.*` labels on nodes.

## Tests

`terraform test` (aws mocked, partition/identity mocked) asserts default-OFF, node-group creation, the SPOT rejection, Capacity Block support, and the DRA/ADR-0028 markers.
