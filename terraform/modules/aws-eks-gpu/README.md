# aws-eks-gpu

> **ADR:** [0044](../../../docs/adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md) D1/D2/D6 (greenfield EKS GPU foundation, DRA floor, scope guards). Reuses EKS Pod Identity ([0018](../../../docs/adrs/0018-eks-pod-identity-as-default-workload-identity.md)). **WS-A.**
> **Status:** plan/validate-only, **default-OFF** (`enabled = false`). Apply-gated.

The control-plane half of the greenfield AWS EKS GPU ML cluster — the AWS mirror of the GKE `gcp-gpu-gke`.

## What it does

- Stands up an EKS cluster via upstream `terraform-aws-modules/eks ~> 21.15` (same as the repo's `eks-cluster`).
- **Pins Kubernetes >= 1.33** (validated) so **DRA is GA on EKS** (ADR-0044 D2); default `1.34` where DRA is the upstream-GA default. Carries a `platform:dra-feature-gate` conformance tag.
- EKS **Pod Identity** auth mode (ADR-0018), secrets envelope encryption (KMS CMK), full control-plane logging.
- **No GPU node groups here** — GPU nodes come from `aws-eks-gpu-nodepools` (Karpenter, ADR-0046 D1) and `aws-eks-gpu-managed-nodegroup` (reserved EFA-DRA training, ADR-0046 D2). Bottlerocket GPU AMIs (ADR-0030) are selected on the node pools.

## ADR-0028 taxonomy

`platform:system = ml-platform`, `platform:component = gpu-compute`, plus caller `platform:*` keys.

## Tests

`terraform test` asserts default-OFF, the DRA version floor (`expect_failures` on 1.30), and ADR-0028 tags + DRA marker.
