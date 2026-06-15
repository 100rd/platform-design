# ADR-0045: AWS EFA high-performance GPU fabric (GPUDirect RDMA + cluster placement groups) for EKS — per-family device-plugin vs DRA path

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — the foundation ADR
  [ADR-0044](0044-aws-eks-gpu-ml-foundation-multiregion.md) brings the EKS GPU
  plane to **compute** parity (Operator + GPU-compute DRA + Volcano + DCGM) but
  **deliberately leaves the data path untouched**: no EFA on the GPU node pools, no
  cluster placement group wiring for the ML cluster, no GPUDirect RDMA, and a naive
  serving front (deferred to [ADR-0047](0047-eks-inference-serving-front-waf.md)).
  The repo's `placement-group` module exists but is unwired to any `aws-eks-gpu-*`
  pool; no `aws-eks-efa-fabric` module exists.
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: extends WS-A "EKS GPU infrastructure parity & elasticity" (AWS ML
  Platform plan §4) on the **networking/fabric** axis that ADR-0044 scoped out;
  mirrors the **fabric half** of [ADR-0042](0042-gpu-inference-networking-serving-uplift.md)
  (the GKE etalon); risk-register R1 (multi-region GPU cost), R4 (per-region GPU /
  Capacity Block availability).
- Supersedes: (none)
- Superseded by: (none)

## Context

[ADR-0044](0044-aws-eks-gpu-ml-foundation-multiregion.md) brought the EKS GPU
plane to **compute parity** with GKE — NVIDIA GPU Operator, DCGM, **DRA for GPU
compute**, Volcano gang scheduling, a reused AWS budget, and multi-region
topology. It **explicitly did not touch the data path**: the GPU↔GPU network
fabric, multi-NIC pods, GPUDirect/RDMA, or where the NCCL collective traffic
flows. Those are the gaps this ADR closes — it is the AWS mirror of the **fabric
half** of [ADR-0042](0042-gpu-inference-networking-serving-uplift.md) (the GKE
"networking & serving uplift"). The **serving front** half of ADR-0042 (the GKE
Inference Gateway + Cloud Armor) maps to a separate AWS ADR,
[ADR-0047](0047-eks-inference-serving-front-waf.md), because on AWS the serving
front has three viable implementations that warrant their own decision.

**The fabric is the bottleneck for large models.** Tensor- and pipeline-parallel
serving and any multi-host distributed training of large LLMs is dominated by NCCL
collective traffic between GPUs. Without a high-performance fabric, multi-GPU /
multi-host jobs are capped at standard-ENA throughput over the default VPC MTU,
and inter-node latency starves the NCCL all-reduce — the single largest avoidable
cost on large jobs.

On AWS, the high-performance GPU fabric is **Elastic Fabric Adapter (EFA)** coupled
with **NVIDIA GPUDirect RDMA** and an EC2 **cluster placement group**. This is the
direct analog of GCP's GPUDirect-TCPX/TCPXO/RoCE story in ADR-0042 — but where GCP
splits across *three* mechanisms per machine family (gVNIC-only / TCPX·TCPXO /
DRANET-RoCE), AWS has a more uniform primitive (EFA) that nonetheless **splits on a
different axis**: **how EFA devices are exposed to pods** (DRA driver vs device
plugin), which is gated by the node provisioner.

The target accelerator fleet (mirroring the GCP ADR-0042 mixed A100/H100/H200/B200
fleet) maps to these EC2 families:

| Accelerator | EC2 family | EFA bandwidth | GPUDirect RDMA | Notes |
|---|---|---|---|---|
| **A100 80GB** | `p4d` / `p4de` | up to 400 Gbps | yes (P4d) | the classic GPUDirect-RDMA EKS path |
| **H100 80GB** | `p5` | up to 3,200 Gbps (EFAv2) | yes | 8× H100, NVLink + EFA |
| **H200 141GB** | `p5en` | up to 3,200 Gbps (**EFAv3**) | yes | newest EFA generation; H200 |
| **B200** | `p6` (P6-B200) | up to 3,200 Gbps | yes | Blackwell; DRA-on-EKS reference family |
| **Trainium2** | `trn2` | up to 3,200 Gbps | NeuronLink (not GPUDirect) | non-NVIDIA — out of scope (NVIDIA-only estate) |

The **load-bearing constraint** — the AWS analog of GCP's "DRANET GA floor" — is:

> **The EFA DRA driver is *not supported* with Karpenter or EKS Auto Mode.**
> EKS exposes EFA to pods two ways: (1) the **EFA device plugin**
> (`vpc.amazonaws.com/efa` extended resource) and (2) the **EFA DRA driver**
> (DRANET-style, a `ResourceClaim` for the NIC). The DRA path is the cleaner,
> topology-aware model — **but it only works on managed node groups / self-managed
> nodes, not under Karpenter or Auto Mode** (as of mid-2026).

This forces a **per-provisioner split** that is *exactly* parallel to GCP's
per-family split (D2 vs D3 in ADR-0042): just as GCP must use the legacy
`GKENetworkParamSet` path for H100 (because DRANET GA doesn't reach A3 High/Mega)
and the managed DRANET path for H200/B200, **AWS must use the EFA device-plugin
path under Karpenter** and **may use the EFA DRA driver only on managed node
groups**. The decision below makes that split explicit and ties it to the node
strategy in [ADR-0046](0046-eks-node-strategy-karpenter-spot.md).

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) labels are
mandatory on every VPC, subnet, security group, placement group, and node-pool
resource introduced here, exactly as in ADR-0044/0042.

## Decision

Add a **per-family EFA high-performance fabric** to the EKS GPU plane, gated by
node provisioner, in five plan/validate-only sub-decisions. Nothing here applies
without passing the apply gate. This ADR **extends, and does not re-open,**
ADR-0044 (Operator / GPU-compute DRA / Volcano / DCGM / multi-region) — those
decisions stand. The **serving front** is ADR-0047.

### D1 — Jumbo frames (MTU 9001) + cluster placement group as the universal GPU-network baseline

Set the GPU VPC/subnets to **9001-byte jumbo frames** (the AWS maximum within a
VPC) and require every multi-node GPU pool to launch into an EC2 **`cluster`
placement group** (reusing the existing `placement-group` module, strategy
`cluster`). This is the **floor for all GPU families**:

- Jumbo frames cut packet count on bulk tensor / NCCL transfers; 9001 is the
  in-VPC AWS maximum and the documented setting for EFA / GPUDirect workloads.
- A **cluster placement group** packs instances onto the same high-bisection
  spine, minimising inter-node latency — the AWS analog of GCP's compact placement
  / same-island requirement and a hard prerequisite for low-latency NCCL.
- The existing `karpenter-nodepools` module **already** supports
  `placement_group_name` (→ `EC2NodeClass spec.placement.placementGroupName`) and
  `availability_zone` single-AZ pinning, so D1's placement-group attach is a
  *wiring* change on the new `aws-eks-gpu` node pools, not new module code.

This is the smallest, lowest-risk, highest-reach change and is the prerequisite
for D2/D3 (mirrors ADR-0042 D1).

### D2 — Karpenter-provisioned GPU pools: EFA via the **device plugin** (`vpc.amazonaws.com/efa`)

For GPU pools provisioned by **Karpenter** (the default node strategy for elastic
serving and bursty training — ADR-0046), expose EFA through the **EFA device
plugin**, not the DRA driver:

- Deploy the **`aws-efa-k8s-device-plugin`** DaemonSet on EFA-capable pools; pods
  request the `vpc.amazonaws.com/efa` extended resource (one per EFA interface).
- The `EC2NodeClass` enables EFA interfaces; the node pool pins a **single AZ** +
  the **cluster placement group** (D1). Karpenter consolidation/spot (ADR-0046)
  applies, but EFA pools are typically **on-demand or Capacity-Block** for
  training (spot eviction mid-NCCL-job is destructive — see ADR-0046).
- The NCCL workload sets `FI_PROVIDER=efa` + the AWS OFI NCCL plugin (pre-baked in
  the AWS Deep Learning / Bottlerocket GPU AMI variant or installed via an
  init-container).

This is deliberately the **device-plugin mechanism** (not DRA) because **the EFA
DRA driver does not work under Karpenter** — the exact structural parallel to
ADR-0042 D2 keeping H100 on the legacy `GKENetworkParamSet` path because DRANET GA
doesn't reach it. Recorded as a revisit trigger: collapse D2 into D3 if/when the
EFA DRA driver gains Karpenter support.

### D3 — Managed-node-group GPU pools: EFA via the **EFA DRA driver** (optional, topology-aware)

For GPU pools provisioned as **EKS managed node groups** (the choice for *static,
reserved, large distributed-training* clusters — e.g. a P6-B200 UltraCluster
reservation, ADR-0046), EFA **may** be exposed through the **EFA DRA driver**:

- Enable the **EFA DRA driver** on the cluster (EKS ≥1.33, the same DRA floor
  ADR-0044 D2 sets); EFA NICs become a **`netdev`-style `ResourceClaim`** that a
  pod references **alongside** the GPU-compute `ResourceClaim` from ADR-0044.
- This keeps **one DRA mental model** across compute and network (the AWS analog of
  ADR-0042 D3's "RoCE fabric is a DRA `netdev` claim"), and lets **Volcano** (which
  already runs the DRA plugin, ADR-0044 D3) schedule **GPU + EFA NIC as one unit** —
  the cleanest path for gang-scheduled multi-host training.

D3 is **optional and gated on the node strategy**: it is available *only* where the
pool is a managed node group (not Karpenter). The decision of which pools are
managed node groups vs Karpenter is **owned by [ADR-0046](0046-eks-node-strategy-karpenter-spot.md)**;
this ADR only states that *if* a pool is a managed node group *and* wants the
topology-aware DRA model, D3 is the path, otherwise D2 (device plugin) applies. Most
of the estate will be D2 (Karpenter); D3 is reserved for the reserved-capacity
training clusters where the DRA topology model pays for itself.

### D4 — `aws-eks-efa-fabric` module (the fabric wiring), per-family

A new **`aws-eks-efa-fabric`** module encapsulates the fabric plumbing so node
pools stay thin (mirrors the GKE `gke-gpu-fabric` / `gke-gpu-dranet` split, folded
into one AWS module with a `mode` switch):

- `mode = "device-plugin"` → installs `aws-efa-k8s-device-plugin` DaemonSet +
  the OFI-NCCL config (D2 path).
- `mode = "dra"` → enables the EFA DRA driver + ships the `netdev` `DeviceClass` /
  `ResourceClaimTemplate` (D3 path), composing with ADR-0044's GPU `ResourceClaim`.
- Both modes assume the pool already has EFA interfaces enabled + the cluster
  placement group + jumbo frames (D1) and carry the ADR-0028 `tags`/labels.

### D5 — Reaffirm scope guards (locked)

- **NVIDIA-only.** Trainium2/NeuronLink is a parallel, non-reused universe (the
  estate is committed to NVIDIA GPU Operator / DCGM / NVIDIA DRA driver) — out of
  scope (revisit trigger). Mirrors ADR-0042 D6 "No TPU".
- **Spot is not the default for EFA training pools.** A spot eviction mid-NCCL-job
  kills the whole gang; EFA *training* pools default to on-demand / Capacity
  Blocks. EFA *serving* pools may use spot with PDB + drain handling. (The spot /
  Capacity-Block policy is owned by ADR-0046; restated here as a fabric constraint.)
- **Disaggregated prefill/decode is deferred** to a follow-up ADR (depends on D2/D3
  + the ADR-0047 serving front landing first). Mirrors ADR-0042 D6.
- **[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) labels are
  mandatory** on every VPC, subnet, security group, placement group, DaemonSet, and
  DRA object here.

A reviewer checks conformance by confirming: (a) the GPU VPC/subnets set MTU 9001
and every multi-node GPU pool attaches a `cluster` placement group (D1); (b)
Karpenter GPU pools expose EFA via `aws-efa-k8s-device-plugin` /
`vpc.amazonaws.com/efa` (D2); (c) any managed-node-group pool using the DRA fabric
runs EKS ≥1.33 with the EFA DRA driver + a `netdev` `ResourceClaimTemplate` (D3);
(d) `aws-eks-efa-fabric` exists with the `mode` switch (D4); (e) EFA training pools
are not spot by default (D5); (f) every new resource carries the five ADR-0028
tags.

## Alternatives considered

### A1 — No EFA / default MTU (do nothing on the fabric)
Leave GPU pools on standard ENA + default VPC MTU.
*Rejected because:* it caps multi-GPU/multi-host NCCL at standard-ENA throughput
and starves large-model training/serving — the dominant avoidable cost. D1 is a
VPC/subnet MTU setting + a placement-group attach the `karpenter-nodepools` module
already supports; the cost of inaction far exceeds the change. (Mirrors ADR-0042
A1.)

### A2 — One uniform EFA exposure for all pools (DRA everywhere, or device-plugin everywhere)
Pick a single EFA-to-pod mechanism fleet-wide.
*Rejected because:* it is **not currently possible** to use the EFA DRA driver
under Karpenter / Auto Mode, and the estate wants Karpenter for elastic serving
(ADR-0046). A per-provisioner split (device-plugin under Karpenter, DRA on managed
node groups) is **forced by the platform**, not a preference — the precise mirror
of ADR-0042 A2 ("one uniform fabric setting is technically impossible"). The split
axis differs (provisioner on AWS vs machine-family on GCP) but the shape is
identical.

### A3 — EFA DRA driver under Karpenter anyway (force it)
Run the EFA DRA driver and provision EFA pools with Karpenter.
*Rejected because:* it is **unsupported** today — the EFA DRA driver requires
managed node groups / self-managed nodes. Forcing it yields nodes with no working
EFA fabric. (For managed-node-group pools, the reverse is true — DRA is the better
model — hence D3 keeps it *only* where it works, exactly as ADR-0042 D2/D3 keep
each path where it works.)

### A4 — Skip placement groups, rely on AZ pinning alone
Pin pods to one AZ but skip the cluster placement group.
*Rejected because:* AZ pinning bounds latency to "same AZ" but a **cluster
placement group** is what packs instances onto the same high-bisection spine for
the lowest inter-node latency EFA needs; AWS documents it as the requirement for
tightly-coupled HPC/NCCL. AZ pinning is necessary (EFA is single-subnet) but not
sufficient.

### A5 — Use the `gpu-inference-tgw-connect` / existing inference fabric instead
Reuse the existing `gpu-inference-*` networking (TGW-connect) for the ML platform
fabric.
*Rejected because:* the platform is **greenfield** (ADR-0044 D6/A1) and the
inference estate's networking is scoped to that cluster's east-west connectivity
(Transit Gateway), not GPU↔GPU RDMA. EFA is an intra-placement-group, single-subnet
data-plane concern; TGW-connect is inter-VPC routing — different layer. We reuse the
`placement-group` *module* (generic), not the inference *wiring*.

## Consequences

### Positive
- **Fabric matched to hardware:** each family runs EFA + GPUDirect RDMA on a
  cluster placement group instead of standard-ENA/default-MTU — the multi-GPU /
  multi-host throughput unlock (P4d 400 Gbps → P5/P5en/P6 3,200 Gbps).
- **One DRA model end-to-end where it works:** on managed-node-group training
  clusters, the EFA fabric is a DRA `netdev` claim that composes with the GPU
  claim ADR-0044 schedules via Volcano — no second paradigm for reserved training.
- **Reuses existing primitives:** the `placement-group` module and the
  `karpenter-nodepools` `placement_group_name` field already exist — D1 is wiring,
  not new module code.
- **D1 is near-free and fleet-wide:** jumbo frames + placement group benefit every
  family at trivial change cost (mirrors ADR-0042 D1).

### Negative
- **Per-provisioner fabric complexity:** the fabric module must express two EFA
  exposure shapes (device-plugin under Karpenter; DRA on managed node groups) —
  more conditional surface than a single uniform pool.
- **EFA pools are single-AZ + placement-group-bound:** this constrains capacity
  (a cluster placement group cannot span AZs) and interacts with the multi-region
  topology (ADR-0044 D5) — each region's training pool is AZ-pinned.
- **AMI / NCCL plugin coupling:** the OFI-NCCL plugin + EFA driver + GPU Operator +
  NCCL version must be co-validated; a mismatch silently degrades EFA to TCP.

### Risks
- **R1 — multi-region GPU cost (highest, inherited).** EFA families (P5/P5en/P6)
  are the most expensive instances and are typically on-demand/Capacity-Block for
  training. *Mitigations:* EFA only where multi-host NCCL needs it; A100/P4d remains
  the cheaper default; serving EFA pools may use spot; `budgets` 80/100/120% paging
  (ADR-0044 D4) unchanged; ADR-0028 tags attribute fabric cost per `$system`.
- **R4 — per-region GPU / Capacity Block availability (inherited).** P5en/P6 supply
  is region-, quota-, and Capacity-Block-constrained and thinner than P4d.
  *Mitigation:* treat per-family, per-region GPU **and** Capacity Block reservations
  as explicit prerequisites before enabling a family in a region; prefer P4d/P5
  where P5en/P6 is unavailable.
- **EFA-DRA × Karpenter (the load-bearing constraint).** Choosing the wrong
  exposure for the provisioner yields a broken or absent fabric. *Mitigation:* the
  `aws-eks-efa-fabric` `mode` is **derived from** the pool's provisioner (ADR-0046),
  not set independently; a CI check asserts `mode = "dra"` only on managed-node-group
  pools.
- **Spot eviction mid-job.** A spot reclaim during an NCCL all-reduce kills the gang.
  *Mitigation:* EFA training pools default to on-demand / Capacity Blocks (D5);
  Volcano gang + re-queue on the surviving capacity.
- **NCCL/EFA misconfig silently degrades to TCP.** *Mitigation:* an **NCCL
  all-reduce bandwidth test** is an acceptance gate for every EFA pool (the AWS
  analog of ADR-0042's RoCE NCCL bandwidth gate).

## Implementation notes

This ADR is **planning-only**: the PR that introduces it creates **no** AWS
resources, **no** `aws-eks-efa-fabric` module, and changes **no** node pool, VPC,
or placement group. Implementation is **apply-gated** and lands as separate,
plan/validate-only PRs.

**Conventions to match (verified against the repo):** `aws ~> 6.0`, Terraform
`~> 1.11`; the `placement-group` module's `placement_groups` map + the
`karpenter-nodepools` `placement_group_name` / `availability_zone` fields are the
reuse surface; every new resource takes `tags` (map(string)) with the five ADR-0028
keys.

### Module interface contracts (for the parallel module build)

**`gpu-vpc` for the ML cluster (greenfield, mirrors `gcp-gpu-vpc` extend)** — jumbo
frames + EFA-ready subnets.
- Inputs: `mtu = 9001` on the GPU subnets; `single_az_gpu_subnet` (bool — EFA pools
  are single-subnet); EFA security group (self-referencing all-traffic SG that EFA
  requires); `tags`.
- Outputs: `gpu_subnet_id`, `efa_security_group_id`.

**`aws-eks-gpu-nodepools` / `karpenter-nodepools` (reuse + thin extend)** —
placement group + EFA attach.
- Wire (existing fields): `placement_group_name` (→ the D1 cluster PG),
  `availability_zone` (single-AZ pin). New per-pool fields: `enable_efa` (bool,
  default `false`), `efa_interface_count` (per instance type),
  `capacity_type` (`on-demand` | `spot` | `capacity-block` — EFA training defaults
  off-spot, D5).
- **Does not touch** the ADR-0044 GPU-compute DRA model or the scale-to-zero /
  consolidation behaviour (ADR-0046) — fabric layers on top.

**`aws-eks-efa-fabric` (new)** — EFA exposure, per-provisioner (D2/D3/D4).
- Inputs: `mode` (`"device-plugin"` | `"dra"`), `cluster_name`, `gpu_node_selector`,
  `efa_device_plugin_version` (device-plugin mode), `efa_dra_driver_version` +
  `device_class_name` (default `efa-netdev`) + `claim_template_name` (default
  `efa-all-nics`) (dra mode), `ofi_nccl_config`, `namespace`, `tags`.
- Outputs: `mode`, `efa_resource_name` (`vpc.amazonaws.com/efa` or the DRA claim),
  `device_class_name` (dra mode), `fabric_enabled`.
- **Provisioner coupling (D2/D3):** `mode = "dra"` is valid **only** on
  managed-node-group pools; `mode = "device-plugin"` on Karpenter pools. The
  `aws-gpu-analysis` stack derives `mode` from the pool's provisioner (ADR-0046),
  not independently.

**Multi-region wiring (interacts with ADR-0044 D5):** the EFA VPC/subnet/SG +
placement group + `aws-eks-efa-fabric` unit are added to the **per-region
`aws-gpu-analysis` Terragrunt stack**, gated on per-region EFA-family availability
+ Capacity Block reservations. Each region's training pool is AZ-pinned to its
cluster placement group. Pin every chart/plugin ref (`?ref=vX.Y.Z`, no `main`).

- Effort: **L** (VPC/subnet jumbo-frame + EFA SG + placement-group wiring + a new
  fabric module with two modes + per-region/per-family wiring + an NCCL bandwidth
  acceptance gate).
- Rollback: each piece is independently revertible; the GPU plane (ADR-0044) and
  the existing estates remain authoritative; EFA can be disabled per pool without
  touching compute.

## Revisit trigger

Re-open this decision if any of the following hold:
- **The EFA DRA driver gains Karpenter / EKS Auto Mode support** — collapse D2's
  device-plugin path into the unified DRA model (D3) and simplify `aws-eks-efa-fabric`
  to a single mode. (Direct analog of ADR-0042's "DRANET GA extends down to A3
  High/Mega" trigger.)
- **Trainium / NeuronLink enters scope** (a non-NVIDIA fabric mandate) — revisit
  D5/A and the Operator/DCGM/DRA-compute assumptions.
- **Disaggregated prefill/decode is prioritised** — open a follow-up ADR building on
  the EFA fabric + the ADR-0047 serving front (separate prefill/decode pools +
  KV-cache transfer).
- **R1 cost envelope is breached** by EFA-family spend — narrow the families enabled
  per region or restrict P5en/P6 to training-only.
- **A cross-AZ EFA capability appears** (placement groups span AZs) — revisit the
  single-AZ constraint (D1/Negative).

## References

- Manage EFA devices on Amazon EKS (EFA device plugin **and** EFA DRA driver; **EFA
  DRA driver not supported with Karpenter or EKS Auto Mode**):
  <https://docs.aws.amazon.com/eks/latest/userguide/device-management-efa.html>
- Kubernetes DRA for Elastic Fabric Adapter (AWS Builder Center):
  <https://builder.aws.com/content/3DiiFA8QxbNSF3BAoe56kOGIbFt/announcing-kubernetes-dynamic-resource-allocation-for-elastic-fabric-adapter>
- Elastic Fabric Adapter (EFA) + GPUDirect RDMA (P6-B200, P5en, P5e, P5, P4d
  bandwidths; cluster placement group requirement):
  <https://aws.amazon.com/hpc/efa/>, <https://aws.amazon.com/ec2/ultraclusters/>
- Deploying managed P4d instances on EKS with NVIDIA GPUDirect RDMA:
  <https://aws.amazon.com/blogs/containers/deploying-managed-p4d-instances-in-amazon-elastic-kubernetes-service/>
- New EC2 P5en (H200) instances with EFAv3:
  <https://aws.amazon.com/blogs/aws/new-amazon-ec2-p5en-instances-with-nvidia-h200-tensor-core-gpus-and-efav3-networking/>
- DRA on EKS (P6e-GB200, ComputeDomain, ResourceClaims):
  <https://aws.amazon.com/blogs/containers/unlocking-next-generation-ai-performance-with-dynamic-resource-allocation-on-amazon-eks-and-amazon-ec2-p6e-gb200/>
- Karpenter GPU scaling (EFA + distributed training):
  <https://cloudnativenow.com/contributed-content/the-ultimate-guide-to-gpu-scaling-with-karpenter/>
- In-repo: `terraform/modules/placement-group`,
  `terraform/modules/karpenter-nodepools`, `terraform/modules/gpu-inference-tgw-connect`
  (reference only), `failover-controller/`, `catalog/stacks/gpu-analysis`.
- Related ADRs: [ADR-0042](0042-gpu-inference-networking-serving-uplift.md) (the GKE
  fabric/serving etalon — this mirrors its **fabric half**);
  [ADR-0044](0044-aws-eks-gpu-ml-foundation-multiregion.md) (EKS GPU compute parity +
  multi-region — this extends it on the fabric axis);
  [ADR-0046](0046-eks-node-strategy-karpenter-spot.md) (node strategy — owns the
  Karpenter-vs-managed-node-group split this ADR's D2/D3 depend on);
  [ADR-0047](0047-eks-inference-serving-front-waf.md) (serving front — the other
  half of ADR-0042); [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md)
  (taxonomy — mandatory).

---
*Doc-verified 2026-06-15 against official AWS EKS EFA device-management, EFA +
GPUDirect-RDMA, EC2 accelerator-instance, and DRA-on-EKS documentation. Greenfield
AWS mirror of the fabric half of the GKE etalon ADR-0042. Planning-only ADR —
proposed, not yet implemented in platform-design. Extends WS-A on the fabric axis;
implementation apply-gated.*
