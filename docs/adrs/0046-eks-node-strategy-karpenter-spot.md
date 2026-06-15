# ADR-0046: EKS GPU node strategy — Karpenter (default) + managed node groups (reserved training), spot / scale-to-zero / consolidation

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — the repo ships a generic `karpenter` +
  `karpenter-nodepools` module (used by the `gpu-analysis` video estate and the
  `gpu-inference-*` estate) but the **greenfield `aws-eks-gpu-*` ML cluster has no
  node pools defined**, no scale-to-zero GPU configuration, and no
  Karpenter-vs-managed-node-group policy. This ADR sets that policy; it provisions
  nothing.
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: WS-A "EKS GPU infrastructure parity & elasticity" (AWS ML
  Platform plan §4) — the **elasticity** sub-decision; consumed by
  [ADR-0044](0044-aws-eks-gpu-ml-foundation-multiregion.md) D5 (multi-region
  scale-to-zero secondary) and [ADR-0045](0045-aws-efa-gpu-fabric-placement-groups.md)
  D2/D3 (the EFA device-plugin-vs-DRA split is *gated on this provisioner choice*);
  risk-register R1 (multi-region GPU cost), R2 (orchestrator stability — node
  availability for Airflow).
- Supersedes: (none)
- Superseded by: (none)

## Context

The GKE etalon ([ADR-0036](0036-gke-ml-infra-parity-multiregion.md)) treats node
elasticity as **settled** — `gcp-gke-gpu-nodepools` already provides spot,
scale-to-zero (`min_node_count = 0`), and per-zone locality, so ADR-0036 explicitly
does **not** re-open it. On AWS, the equivalent primitive is **not pre-settled for
the greenfield ML cluster**: AWS offers *two* fundamentally different node
provisioners, and the choice between them is **load-bearing** because it gates the
EFA fabric exposure (ADR-0045) and the cost envelope (R1). This ADR makes that
choice explicit — it is the AWS decision that ADR-0036 got "for free" from the
pre-existing GKE module.

The two AWS provisioners:

| | **Karpenter** | **EKS managed node groups** |
|---|---|---|
| Model | Just-in-time, workload-driven node provisioning; consolidation; diverse instance types | Fixed ASG-backed groups; explicit instance types; scaled by Cluster Autoscaler or static |
| Scale-to-zero | Yes (no min; deprovisions empty nodes) | Yes (`min_size = 0`) but slower, ASG-bound |
| Spot | First-class (`spot_percentage`, capacity-type requirements) | Supported, coarser (per-group capacity type) |
| Consolidation / bin-packing | First-class (`WhenEmptyOrUnderutilized`, `consolidateAfter`) | None native (Cluster Autoscaler only) |
| **EFA DRA driver** | **NOT supported** (ADR-0045) | **Supported** |
| Capacity Blocks / reserved | Via capacity-type requirements | Native (a node group can target a Capacity Block reservation) |
| Repo support | `terraform/modules/karpenter` + `karpenter-nodepools` (already has `spot_percentage`, `consolidation_policy`, `consolidate_after`, `placement_group_name`, `availability_zone`) | not yet wrapped as a dedicated module |

The **load-bearing fact** is the EFA-DRA × Karpenter constraint from ADR-0045:
*the EFA DRA driver only works on managed node groups, not under Karpenter.* So the
node strategy is not a free choice — it co-determines whether a GPU pool can use
the topology-aware DRA fabric (managed node group) or must use the EFA device
plugin (Karpenter). This ADR resolves the tension by making the **provisioner a
property of the workload class**, not a cluster-wide either/or.

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) tags are
mandatory on every node pool, `EC2NodeClass`, and node group introduced here.
[ADR-0030](0030-bottlerocket-node-os.md) (Bottlerocket) is the node OS for all GPU
pools; [ADR-0007](0007-karpenter-over-cluster-autoscaler.md) already chose Karpenter
over Cluster Autoscaler estate-wide, which this ADR refines for the GPU/ML case.

## Decision

Adopt a **hybrid, workload-class-driven node strategy**: **Karpenter is the default
provisioner** for the ML GPU cluster, with **EKS managed node groups reserved for
the narrow case of large, reserved-capacity distributed training that wants the EFA
DRA topology model.** Five plan/validate-only sub-decisions.

### D1 — Karpenter is the default GPU provisioner (serving + bursty/elastic training)

The default node provisioner for the `aws-eks-gpu-*` cluster is **Karpenter**,
reusing the existing `karpenter` + `karpenter-nodepools` modules. This covers:

- **Inference / serving pools** — bursty, latency-driven, benefit from
  just-in-time provisioning, **scale-to-zero**, **spot**, and **consolidation**.
- **Bursty / ad-hoc training** — single-node or small multi-node jobs that don't
  need the EFA DRA topology model.

Rationale: Karpenter is already the estate default (ADR-0007), already supports
everything ADR-0036 wanted from `gcp-gke-gpu-nodepools` (spot via
`spot_percentage`, scale-to-zero via no-min + consolidation, consolidation via
`consolidation_policy = "WhenEmptyOrUnderutilized"` + `consolidate_after`), and
already supports placement-group / single-AZ pinning (`placement_group_name`,
`availability_zone`) needed by EFA (ADR-0045 D1). For EFA pools under Karpenter, the
fabric uses the **EFA device plugin** (ADR-0045 D2).

### D2 — Managed node groups for reserved, large-scale distributed training (EFA DRA path)

Provision a GPU pool as an **EKS managed node group** (a new thin
`aws-eks-gpu-managed-nodegroup` wrapper, or the upstream `eks` module's node-group
sub-resource) **only** when **all** of these hold:

- the pool runs **large multi-host distributed training** (multi-node NCCL across a
  cluster placement group), **and**
- it sits on **reserved capacity** (a **Capacity Block** or on-demand reservation —
  not spot), **and**
- it wants the **EFA DRA topology model** (ADR-0045 D3) — GPU + EFA NIC as one DRA
  `ResourceClaim` scheduled by Volcano.

This is the **only** path to the EFA DRA driver (Karpenter can't run it, ADR-0045),
and reserved training is exactly where the DRA topology model + a fixed, pinned
node group (no churn mid-job) pays for itself. Everything else stays on Karpenter
(D1).

### D3 — Spot / scale-to-zero / consolidation policy (the R1 cost guard)

- **Serving pools:** **spot-first** (`spot_percentage` high) + **scale-to-zero**
  (Karpenter deprovisions empty nodes) + **consolidation**
  (`WhenEmptyOrUnderutilized`, `consolidate_after = "30s"`-ish). PDB + the
  `failover-controller` (ADR-0044 D5) absorb spot churn. This is the direct AWS
  mirror of the GKE etalon's "secondary region = scale-to-zero + spot-first"
  (ADR-0036 D5) — and the **primary code-level R1 guard** alongside `budgets`
  (ADR-0044 D4).
- **EFA training pools:** **NOT spot by default** (ADR-0045 D5) — a spot reclaim
  mid-NCCL-job kills the gang. Use **on-demand or Capacity Blocks**; scale-to-zero
  *between* jobs is still desirable (deprovision the expensive pool when idle), but
  *within* a job the nodes are pinned.
- **Secondary region (ADR-0044 D5):** scale-to-zero GPU NodePools sized for
  failover-serving headroom, not a hot training mirror.

### D4 — Capacity Blocks as the reserved-capacity primitive for scarce families

For the scarce EFA families (P5en/P6, ADR-0045), the platform uses **EC2 Capacity
Blocks for ML** as the reservation primitive: a managed node group (D2) or a
Karpenter capacity-type requirement targets a Capacity Block reservation so a
multi-day training run has guaranteed GPUs. This is the AWS-native answer to the
GKE etalon's **R4** ("per-region GPU quota/capacity must be reserved, not assumed")
— on AWS, *reserve a Capacity Block*; on GCP, *request a per-region GPU quota*.
Capacity Block reservation IDs are an explicit per-region prerequisite before a
scarce-family pool is enabled.

### D5 — Reaffirm scope guards (locked)

- **One cluster, mixed provisioners.** Karpenter and managed node groups **coexist
  in the same EKS cluster** — the provisioner is a property of the *pool/workload
  class*, not the cluster. This avoids a cluster-per-provisioner split.
- **No EKS Auto Mode for GPU pools.** Auto Mode (like Karpenter) does **not**
  support the EFA DRA driver, and it abstracts away the node-level control
  (placement groups, EFA interfaces, Bottlerocket GPU AMI selection, NCCL tuning)
  that the GPU/fabric stack needs — the AWS analog of the GKE "Standard, not
  Autopilot" lock (ADR-0036 D6). Auto Mode is fine for non-GPU control workloads
  (see plan §7 Graviton OPEN DECISION).
- **[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) tags
  mandatory** on every `NodePool` / `EC2NodeClass` / node group.

A reviewer checks conformance by confirming: (a) serving/bursty GPU pools are
Karpenter `NodePool`s with `spot_percentage` + consolidation + scale-to-zero (D1,
D3); (b) any EFA-DRA pool is a managed node group on reserved capacity (D2); (c)
EFA training pools are not spot (D3); (d) scarce-family pools reference a Capacity
Block reservation (D4); (e) no GPU pool uses EKS Auto Mode (D5); (f) every node
resource carries the five ADR-0028 tags.

## Alternatives considered

### A1 — Karpenter-only (no managed node groups)
Use Karpenter for every GPU pool, including reserved training.
*Rejected because:* Karpenter **cannot run the EFA DRA driver** (ADR-0045), so a
Karpenter-only estate forecloses the topology-aware DRA fabric for large training —
the cleanest gang-scheduling model. Karpenter-only would force the EFA *device
plugin* even for reserved P6 UltraClusters where the DRA model is most valuable.
Karpenter remains the **default** (D1); managed node groups are the **narrow
exception** (D2), not the rule.

### A2 — Managed-node-groups-only (no Karpenter)
Use fixed ASG-backed node groups for everything.
*Rejected because:* it forfeits Karpenter's just-in-time provisioning, consolidation,
and scale-to-zero — the **primary R1 cost guards** for bursty serving — and diverges
from the estate default (ADR-0007). Managed node groups are wasteful for elastic
serving (idle ASG capacity).

### A3 — EKS Auto Mode everywhere
Let EKS Auto Mode manage all nodes.
*Rejected because:* Auto Mode does **not** support the EFA DRA driver and hides the
node-level controls (placement groups, EFA, Bottlerocket GPU AMI, NCCL env) the GPU
fabric requires — structurally incompatible with the ADR-0045 fabric, exactly as
GKE Autopilot is incompatible with the ADR-0036 GPU stack. (Auto Mode is acceptable
for non-GPU control-plane workloads — plan §7.)

### A4 — Spot for training pools too (maximise cost savings)
Run EFA training pools on spot.
*Rejected because:* a spot reclaim mid-NCCL-all-reduce kills the entire gang-scheduled
job (ADR-0045 D5) — the savings are illusory against repeated job restarts on
multi-day runs. Spot is right for **serving** (PDB + failover absorb churn), not for
gang-scheduled training. Capacity Blocks (D4) give reserved training capacity instead.

### A5 — Cluster Autoscaler instead of Karpenter
Use the classic Cluster Autoscaler on managed node groups.
*Rejected because:* ADR-0007 already chose Karpenter over Cluster Autoscaler
estate-wide for faster, bin-packed, consolidation-aware scaling; re-introducing
Cluster Autoscaler for the GPU cluster would split the scaling model and lose
consolidation. (Managed node groups in D2 are *static/reserved*, not autoscaled by
CA — they're pinned for the duration of a training run.)

## Consequences

### Positive
- **Best provisioner per workload class:** Karpenter's elasticity/consolidation/spot
  for serving (R1 win), managed node groups' EFA-DRA + reserved capacity for large
  training (fabric win) — without a cluster split.
- **Reuses existing modules:** `karpenter` + `karpenter-nodepools` already provide
  spot/scale-to-zero/consolidation/placement-group — D1/D3 are configuration, not
  new module code. The managed-node-group wrapper (D2) is the only net-new piece.
- **R1 cost guard at the node layer:** scale-to-zero + spot serving + consolidation
  is the primary code-level cost control, complementing `budgets` paging (ADR-0044).
- **R4 answered natively:** Capacity Blocks (D4) reserve scarce GPUs the way GCP
  quota does — a concrete prerequisite, not an assumption.

### Negative
- **Two provisioners to operate:** Karpenter `NodePool`s **and** managed node groups
  in one cluster means two scaling mental models — mitigated by confining managed
  node groups to the narrow reserved-training case (D2) and tagging both with
  ADR-0028.
- **EFA fabric mode is coupled to the provisioner:** an operator must pick the
  provisioner *and* the matching EFA mode (device-plugin for Karpenter, DRA for
  managed) together (ADR-0045 D4 derives `mode` from this) — a coordination point.
- **Capacity Block lifecycle:** reservations are time-boxed and must be renewed/tracked
  per region — an operational task the secondary region's scale-to-zero design
  partially relieves.

### Risks
- **R1 — GPU cost (highest).** *Mitigations (this ADR is the node-layer guard):*
  Karpenter scale-to-zero + spot serving + consolidation (D1/D3); EFA training only
  on reserved capacity when actually needed (D2); secondary region scale-to-zero
  (ADR-0044 D5); `budgets` paging (ADR-0044 D4).
- **R2 — orchestrator (Airflow) node availability.** Airflow scheduler/workers
  (ADR-0048) need stable nodes; if they land on consolidating spot GPU nodes they
  churn. *Mitigation:* Airflow control-plane on a **non-GPU on-demand/Graviton**
  Karpenter pool (plan §7 Graviton OPEN DECISION), separate from GPU pools.
- **EFA-DRA × provisioner mismatch (inherited from ADR-0045).** *Mitigation:* a CI
  check asserts EFA `mode = "dra"` only on managed-node-group pools; the stack
  derives the mode, operators don't set it independently.
- **Capacity Block exhaustion / non-renewal.** A lapsed reservation blocks a training
  run. *Mitigation:* track Capacity Block IDs as a per-region prerequisite (D4);
  alert ahead of expiry.

## Implementation notes

This ADR is **planning-only**: the PR that introduces it creates **no** node pools,
node groups, or Capacity Block reservations. Implementation is **apply-gated**.

**Conventions to match (verified against the repo):** `aws ~> 6.0`, Terraform
`~> 1.11`; reuse `terraform/modules/karpenter` + `karpenter-nodepools` (fields
`spot_percentage`, `consolidation_policy`, `consolidate_after`, `placement_group_name`,
`availability_zone` already exist); ADR-0007 (Karpenter), ADR-0030 (Bottlerocket).

### Module interface contracts (for the parallel module build)

**`aws-eks-gpu-nodepools` (greenfield, wraps `karpenter-nodepools` for GPU)** —
the Karpenter GPU pools (D1/D3).
- Per-pool config map keyed by pool name; each: `instance_families` (e.g.
  `["p5", "p4d"]` serving; `["g6", "g5"]` cheap inference), `spot_percentage`
  (serving high; training 0), `consolidation_policy`, `consolidate_after`,
  `placement_group_name` (EFA, ADR-0045 D1), `availability_zone` (EFA single-AZ),
  `enable_efa` (→ ADR-0045 device-plugin mode), `min`/`max`, `tags`.
- The scale-to-zero + spot + consolidation behaviour is inherited from
  `karpenter-nodepools`; this wrapper adds GPU-specific defaults + the ADR-0045
  EFA wiring.

**`aws-eks-gpu-managed-nodegroup` (new, narrow — D2)** — reserved EFA-DRA training.
- Inputs: `cluster_name`, `instance_type` (e.g. `p6-b200.48xlarge`), `desired_size`
  (pinned for a run), `capacity_block_reservation_id` (D4), `placement_group_name`
  (cluster PG), `availability_zone`, `enable_efa = true` + `efa_mode = "dra"`
  (→ ADR-0045 D3), `bottlerocket_gpu_ami`, `taints` (GPU + training), `labels`/`tags`.
- Outputs: `node_group_name`, `node_role_arn`, `capacity_block_reservation_id`.

**`budgets` (reuse) + Capacity Block tracking:** the per-region Capacity Block
reservation IDs are a documented prerequisite (a `region.hcl` local), not a Terraform
resource this platform creates.

**Multi-region wiring (ADR-0044 D5):** primary region runs Karpenter serving pools +
(optionally) a reserved managed-node-group training pool; secondary region runs
**scale-to-zero Karpenter serving pools only** (no hot training mirror). Pin module
refs (`?ref=vX.Y.Z`).

- Effort: **M** (a GPU Karpenter-nodepools wrapper + a narrow managed-node-group
  wrapper + Capacity Block prerequisite tracking; most behaviour is reused).
- Rollback: pools are independently revertible; the existing estates' node strategy
  is untouched.

## Revisit trigger

Re-open this decision if any of the following hold:
- **Karpenter / EKS Auto Mode gains EFA DRA support** — collapse D2 into Karpenter
  (D1); managed node groups for training become unnecessary. (Couples to ADR-0045's
  same trigger.)
- **A managed-node-group-only or Auto-Mode mandate appears** (org standardisation) —
  revisit D1/A2/A3.
- **Spot becomes safe for gang training** (e.g. checkpoint/restart fast enough, or a
  spot-aware gang scheduler) — revisit D3/D4/A4.
- **Capacity Blocks are deprecated or replaced** by another reservation primitive —
  revisit D4.
- **R1 envelope is breached** despite scale-to-zero + spot + consolidation + budgets —
  tighten the secondary-region model (cold standby) or narrow training families.

## References

- AWS EKS AI/ML compute & autoscaling best practices (Karpenter, node strategy,
  Capacity Blocks): <https://docs.aws.amazon.com/eks/latest/best-practices/aiml-compute.html>
- Karpenter (consolidation, spot, scale-to-zero, NodePool/EC2NodeClass):
  <https://karpenter.sh/docs/>
- The Ultimate Guide to GPU Scaling with Karpenter (EFA, distributed training):
  <https://cloudnativenow.com/contributed-content/the-ultimate-guide-to-gpu-scaling-with-karpenter/>
- EC2 Capacity Blocks for ML: <https://aws.amazon.com/ec2/capacityblocks/>
- Manage EFA devices on Amazon EKS (EFA DRA driver not supported with Karpenter /
  Auto Mode): <https://docs.aws.amazon.com/eks/latest/userguide/device-management-efa.html>
- In-repo: `terraform/modules/karpenter`, `terraform/modules/karpenter-nodepools`,
  `terraform/modules/placement-group`.
- Related ADRs: [ADR-0007](0007-karpenter-over-cluster-autoscaler.md) (Karpenter
  estate-wide — this refines it for GPU/ML); [ADR-0030](0030-bottlerocket-node-os.md)
  (Bottlerocket GPU AMI); [ADR-0044](0044-aws-eks-gpu-ml-foundation-multiregion.md)
  (foundation — consumes this for D5 scale-to-zero secondary);
  [ADR-0045](0045-aws-efa-gpu-fabric-placement-groups.md) (EFA fabric — its
  device-plugin-vs-DRA split is gated on this provisioner choice);
  [ADR-0036](0036-gke-ml-infra-parity-multiregion.md) (GKE etalon — where node
  elasticity was pre-settled by `gcp-gke-gpu-nodepools`);
  [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (taxonomy —
  mandatory).

---
*Doc-verified 2026-06-15 against official AWS EKS compute best-practices, Karpenter,
EC2 Capacity Blocks, and EKS EFA device-management documentation. AWS node-strategy
decision the GKE etalon got for free from `gcp-gke-gpu-nodepools`. Planning-only ADR
— proposed, not yet implemented in platform-design. WS-A elasticity sub-decision;
implementation apply-gated.*
