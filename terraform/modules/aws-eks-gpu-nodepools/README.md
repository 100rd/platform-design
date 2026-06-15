# aws-eks-gpu-nodepools

> **ADR:** [0046](../../../docs/adrs/0046-eks-node-strategy-karpenter-spot.md) D1/D3 (Karpenter default, spot/scale-to-zero/consolidation), [0045](../../../docs/adrs/0045-aws-efa-gpu-fabric-placement-groups.md) D1/D2 (placement group, EFA device plugin). Reuses [`karpenter-nodepools`](../karpenter-nodepools). **WS-A.**
> **Status:** plan/validate-only, **default-OFF** (`enabled = false`). Apply-gated.

Karpenter GPU pools for the AWS EKS GPU ML cluster — a thin GPU-defaults wrapper over the existing `karpenter-nodepools` module (ADR-0046: D1/D3 are configuration, not new module code).

## What it does

- Builds GPU `NodePool` / `EC2NodeClass` configs with **GPU taints** (`nvidia.com/gpu`) + GPU labels.
- **Serving pools:** spot-first + scale-to-zero + consolidation (`WhenEmptyOrUnderutilized`) — the primary node-layer R1 cost guard (ADR-0046 D1/D3).
- **EFA training pools:** `spot_percentage = 0` (no spot mid-NCCL, ADR-0046 D3 / ADR-0045 D5), `enable_efa = true` pinning a **cluster placement group + single AZ** (ADR-0045 D1) and running the EFA **device plugin** (Karpenter cannot run the EFA DRA driver, ADR-0045 D2 — the load-bearing constraint).
- GPU pools stay **x86** (NVIDIA); non-GPU control workloads use Graviton elsewhere (plan §7 #7).

## ADR-0028 taxonomy

Node tags `platform:system = ml-platform`, `platform:component = gpu-compute`, plus caller keys; pool labels carry the dotted `platform.*` equivalents.

## Tests

`terraform test` (kubernetes mocked) asserts default-OFF, the serving-vs-EFA spot split, consolidation, the GPU taint, EFA labeling, and ADR-0028 tags.
