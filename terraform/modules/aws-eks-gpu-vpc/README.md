# aws-eks-gpu-vpc

> **ADRs:** [0044](../../../docs/adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md) D5 (multi-region), [0045](../../../docs/adrs/0045-aws-efa-gpu-fabric-placement-groups.md) D1 (jumbo frames + EFA SG). Part of **WS-A** of the AWS ML platform.
> **Status:** plan/validate-only, **default-OFF** (`enabled = false`). Apply-gated — nothing is provisioned until a human flips the toggle on `main`.

Greenfield GPU VPC for the AWS EKS GPU ML platform — the AWS mirror of `gcp-gpu-vpc`.

## What it does

- A dedicated VPC (via `terraform-aws-modules/vpc`) with multi-AZ private subnets and **GPU/EFA interconnect subnets** modeled as intra subnets.
- **Jumbo frames (MTU 9001)** intent on the GPU subnets — the in-VPC AWS maximum and the documented setting for EFA / GPUDirect RDMA (ADR-0045 D1).
- A **single-AZ GPU subnet** pin for EFA cluster placement groups (which cannot span AZs).
- A **self-referencing all-traffic EFA security group** so all GPU nodes in a cluster placement group can speak EFA/RDMA to one another (ADR-0045 D1/D4).
- Karpenter/ELB discovery subnet tags so `aws-eks-gpu-nodepools` can find subnets.

## ADR-0028 taxonomy

Every resource carries the `platform:*` tags via `var.tags`, with module defaults `platform:system = ml-platform`, `platform:component = gpu-network`.

## Reuse, not reinvention

Wraps the upstream `terraform-aws-modules/vpc` (as `gpu-inference-vpc` does); the EFA SG is the only net-new fabric primitive. The `placement-group` module (reused by `aws-eks-gpu-nodepools`) provides the cluster placement group that pins instances to one spine.

## Inputs / outputs

See `variables.tf` / `outputs.tf`. Key outputs: `vpc_id`, `gpu_subnet_ids`, `efa_gpu_subnet_id`, `efa_security_group_id`, `mtu`.

## Tests

`terraform test` (providers mocked) asserts default-OFF, MTU 9001, EFA SG wiring, single-AZ pin, and ADR-0028 tags.
