# ADR-0044: AWS EKS GPU ML-platform foundation (GPU Operator, DCGM, DRA, batch scheduling) + multi-region EKS & AWS cost guardrail

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — this is a **greenfield** AWS GPU ML
  platform. The repo already ships AWS GPU *building blocks*
  (`terraform/modules/gpu-eks`, `karpenter`, `karpenter-nodepools`,
  `placement-group`, `budgets`) and a separate `gpu-inference-*` estate, but
  **none** of the net-new `aws-eks-gpu-*` day-2 ML modules
  (`aws-eks-gpu-operator`, `aws-eks-gpu-dcgm`, `aws-eks-gpu-scheduling`) exist,
  there is no `aws-gpu-analysis` multi-region stack, and the existing
  `gpu-inference-*` modules are **explicitly not consolidated into** this design
  (greenfield was chosen — see A1 and the plan §7).
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: WS-A "EKS GPU infrastructure parity & elasticity" (AWS ML
  Platform plan, `docs/aws-ml-platform/IMPLEMENTATION_PLAN.md` §4); mirrors
  [ADR-0036](0036-gke-ml-infra-parity-multiregion.md) (the GKE etalon);
  risk-register R1 (multi-region GPU cost), R4 (per-region GPU quota / Capacity
  Block availability).
- Supersedes: (none)
- Superseded by: (none)

## Context

This ADR establishes the **greenfield AWS EKS GPU ML platform** as a structural
mirror of the GKE platform that [ADR-0036](0036-gke-ml-infra-parity-multiregion.md)
defines. The user chose **greenfield over consolidation**: rather than extend the
existing `gpu-inference-*` AWS estate (a separately-scoped inference cluster), we
build a clean, parallel `aws-eks-gpu-*` module set whose shape corresponds
one-to-one to the GCP `gke-gpu-*` set, so the two clouds share one operating
model, one ADR-0028 `$system` observability surface, and diff-able module
contracts. The existing AWS modules are **read for patterns and reused where they
are already generic** (node lifecycle, placement groups, budgets), not folded in
as the ML cluster.

GPU compute on AWS in this repo today is a set of **generic building blocks**, not
an assembled ML cluster:

| Building block | What it gives us | Where (reference) |
|---|---|---|
| `karpenter` + `karpenter-nodepools` | Karpenter controller + `NodePool`/`EC2NodeClass` with `spot_percentage`, `consolidation_policy` (`WhenEmptyOrUnderutilized`), `consolidate_after`, optional `placement_group_name` / `availability_zone` pinning | `terraform/modules/karpenter*` |
| `placement-group` | EC2 `cluster`/`spread`/`partition` placement groups (HPC low-latency) | `terraform/modules/placement-group` |
| `gpu-eks` / `gpu-vpc` | A GPU EKS cluster + VPC (the `gpu-analysis` video estate) | `terraform/modules/gpu-eks`, `catalog/stacks/gpu-analysis` |
| `budgets` | `aws_budgets_budget` — ACTUAL thresholds (default 50/80/100%) + FORECASTED, per-account / per-service budgets, SNS + email sinks | `terraform/modules/budgets` |

What does **not** exist as an assembled, ML-grade GPU cluster is the **day-2 ML
stack** — the operational surface that turns raw GPU nodes into an ML platform.
The GKE etalon names exactly four pieces; this ADR builds their AWS analogs:

| Concern | GKE module (ADR-0036, etalon) | **AWS module (this ADR)** |
|---|---|---|
| GPU operator + driver | `gke-gpu-operator` (NVIDIA GPU Operator: GFD/NFD/CDI/toolkit + NVIDIA DRA driver) | **`aws-eks-gpu-operator`** |
| GPU telemetry + health | `gke-gpu-dcgm` (DCGM Exporter, XID/ECC/temp rules, auto-taint CronJob) | **`aws-eks-gpu-dcgm`** |
| DRA device classes | folded into `gke-gpu-scheduling` | folded into **`aws-eks-gpu-scheduling`** |
| Batch scheduling | `gke-gpu-scheduling` (**Volcano** gang + DRA + binpack + topology) | **`aws-eks-gpu-scheduling`** |
| Serving elasticity | KEDA + HPA (reused) | KEDA + HPA (reused) — see ADR-0047 |
| Cost guardrail | **`gcp-billing-budget`** (`google_billing_budget`) | **reuse `budgets`** (`aws_budgets_budget`) + CUR/OpenCost (ADR-0027) |

Three forces shape the decisions below:

1. **AWS has a *native* cost-budget primitive already in-repo.** Where the GKE
   side had to *build* `gcp-billing-budget` because no GCP analog existed, the AWS
   side **reuses the existing `budgets` module** (`aws_budgets_budget`) — the
   asymmetry is deliberate and is the AWS-correct mirror of the GCP D4 decision
   (D4 below).
2. **DRA on EKS is GA from EKS Kubernetes 1.33** (beta upstream behind the
   `DynamicResourceAllocation` feature gate; the NVIDIA DRA driver publishes
   `ResourceSlice`s and is the eventual device-plugin replacement). This is the
   AWS analog of the GKE DRA floor — it sets the cluster K8s-version floor and the
   GPU-request model (D1/D2). The node strategy that DRA composes with (Karpenter
   vs managed node groups) is **decided separately in
   [ADR-0046](0046-eks-node-strategy-karpenter-spot.md)** because EFA + DRA
   interacts sharply with Karpenter (see ADR-0045).
3. **Multi-region is required.** WS-A asks for **regional EKS in ≥2 AWS regions**
   with **cross-region serving failover** — the same topology the GKE etalon
   adopts (D5), landing on risk-register **R1** (multi-region GPU cost) and **R4**
   (per-region GPU / Capacity Block availability).

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (the unified
`platform:system` / `platform.system` taxonomy) is mandatory on every resource
introduced here — AWS-tag form on the Terraform plane, K8s-label form on the
workload plane — and is enforced at plan time by
`tests/opa/platform_tags.rego` (which already runs in CI). IAM for the ML data
plane (S3 artifact store, KMS, Secrets) uses the **ABAC condition pattern**
(`aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system`,
[ADR-0018](0018-eks-pod-identity-as-default-workload-identity.md) Pod Identity).

## Decision

Build a **greenfield AWS EKS GPU ML platform** at structural parity with the GKE
etalon (ADR-0036), via three net-new day-2 modules + reused building blocks + a
multi-region topology. All sub-decisions are **plan/validate-only**; nothing
applies without passing the apply gate.

### D1 — GPU driver: NVIDIA GPU Operator on EKS (DCGM disabled in the operator)

Install the **NVIDIA GPU Operator** as the EKS GPU software layer (new
`aws-eks-gpu-operator` module), mirroring the GKE `gke-gpu-operator`: GPU Feature
Discovery, Node Feature Discovery, container toolkit, CDI, and the **NVIDIA DRA
driver** — with the in-operator **DCGM disabled** (`dcgmExporter.enabled = false`)
because DCGM is owned by the dedicated `aws-eks-gpu-dcgm` module (the same split
the GKE etalon uses).

On **[Bottlerocket](0030-bottlerocket-node-os.md)** (this estate's EKS node OS,
ADR-0030) the NVIDIA driver/toolkit are **pre-baked into the GPU AMI variant**, so
the Operator runs **GFD/NFD/CDI + the NVIDIA DRA driver** and the **device-plugin
path** without managing the kernel driver itself. This is the inverse of the GKE
case (where the Operator *installs* the driver because the COS image does not bake
it) — a deliberate, OS-correct delta captured in the module contract
(`driver.enabled = false` on Bottlerocket GPU AMIs). On Amazon Linux 2023 GPU
AMIs the Operator installs the driver (`driver.enabled = true`).

Chosen over the **standalone NVIDIA k8s-device-plugin** (the minimal path) because
the Operator is the only path that unlocks **DRA** (it ships and lifecycle-manages
the NVIDIA DRA driver and the `ResourceSlice` publisher), gives one GFD/NFD/CDI
mental model shared with the GKE fleet, and is the NVIDIA-supported way to run
the full GPU stack (DCGM, MIG, DRA, time-slicing) on EKS.

### D2 — GPU request model: DRA device classes (EKS 1.33+), folded into scheduling

Adopt **Dynamic Resource Allocation** for typed GPU requests, mirroring the GKE
DRA-compute decision. The `aws-eks-gpu-scheduling` module ships the
`DeviceClass` + `ResourceClaimTemplate` objects (single-GPU, full-node NVLink
island, MIG slice) so jobs request *typed* GPUs (H100 vs A100 vs B200, full NVLink
island) instead of the opaque `nvidia.com/gpu: N` count. This requires the EKS
cluster at **Kubernetes 1.33+** with the `DynamicResourceAllocation` feature gate
(GA on EKS from 1.33; the NVIDIA DRA driver from D1 publishes the ResourceSlices).
For new pools we target **1.34+** where DRA is upstream-GA and the recommended
default; classic `nvidia.com/gpu` counting remains available as a fallback for
non-DRA workloads.

**Sharp coupling (recorded, decided in ADR-0045/0046):** the **EFA DRA driver**
(the network analog of GPU DRA) is **not supported with Karpenter or EKS Auto
Mode** today. GPU-compute DRA *is* compatible with Karpenter; **EFA** DRA is not.
That asymmetry is the single highest-risk integration point of the AWS platform
and is why the **fabric** decision (ADR-0045) and the **node strategy** decision
(ADR-0046) are split out of this ADR. This ADR fixes only **GPU-compute DRA**.

### D3 — Batch scheduling: Volcano (not Kueue)

Deploy **Volcano** as the EKS batch scheduler (new `aws-eks-gpu-scheduling`
module), identical in shape to the GKE `gke-gpu-scheduling`: a **secondary
scheduler** (`schedulerName: volcano`, opt-in) with the **gang**, **DRA**,
**binpack** (GPU-weighted), **topology**, and **proportion** plugins, and
`training` / `inference` / `batch` fair-share **Queues**. The same module ships
the DRA `DeviceClass` / `ResourceClaimTemplate` objects from D2.

Chosen over **Kueue** because:

- **Native gang scheduling.** Distributed ML training needs all-or-nothing pod
  admission so a multi-GPU job never deadlocks holding a partial set. Volcano
  provides gang scheduling natively; **Kueue does not** — it is a job-level
  queue/quota admission layer that then defers pod placement to the default
  scheduler. NCCL training meshes on EFA (ADR-0045) require simultaneous pod
  admission across the placement group, which is exactly Volcano's `PodGroup`
  gang semantics.
- **Parity with the GKE etalon.** ADR-0036 D2 chose Volcano on GKE; matching it on
  EKS preserves one scheduler binary, one queue taxonomy, one set of `PodGroup`
  manifests, and one operating model across clouds.
- **GPU-aware bin-packing + DRA** are first-class in Volcano (weight
  `binpack.resources.nvidia.com/gpu`), maximising GPU packing — directly relevant
  to R1 cost.

The industry **Kueue-for-quota over Volcano-for-gang** pattern is real and is
recorded as the **revisit trigger** below (matching ADR-0036), not adopted now, to
keep WS-A at strict parity with the proven Volcano-on-GKE design. (Full survey:
plan §7 OPEN DECISION "Volcano vs Kueue".)

### D4 — Cost guardrail: reuse `budgets` (`aws_budgets_budget`) + CUR/OpenCost

Where the GKE etalon **built** `gcp-billing-budget`, AWS **already has the native
analog in-repo** — the **`budgets`** module wrapping `aws_budgets_budget`. WS-A
**reuses it** rather than inventing a new module:

- A monthly GPU budget with ACTUAL `alert_thresholds = [80, 100, 120]` (the
  module default is `[50, 80, 100]`; we raise to match the GKE 80/100/120% rule)
  plus a **FORECASTED** `forecasted_alert_threshold = 120` for early warning —
  the AWS-native mirror of the GCP D4 FORECASTED-120% guard for **R1**.
- Scoped via `per_service_budgets` (e.g. `"Amazon Elastic Compute Cloud - Compute"`,
  `"Amazon Elastic Kubernetes Service"`) and/or `per_account_budgets` to the GPU
  account, so GPU spend is bounded independently of the rest of the estate.
- Routed to **SNS → Alertmanager → PagerDuty** (via `sns_topic_arns`), matching
  the plan's "80/100/120% → PagerDuty via Alertmanager" — the same paging path the
  GCP budget uses via Pub/Sub.
- **Granular attribution** rides the existing **OpenCost + AWS CUR/Athena**
  pipeline ([ADR-0027](0027-kubernetes-cost-opencost-cur.md)): ADR-0028
  `platform:system` tags make GPU cost roll up per `$system` across both regions —
  the AWS analog of the GKE label-scoped FinOps roll-up.

This asymmetry (build on GCP, reuse on AWS) is the **correct** mirror: the goal is
the *same guardrail behaviour* (80/100/120% + forecasted paging + per-`system`
attribution), achieved with each cloud's native primitive.

### D5 — Multi-region topology: independent regional EKS in ≥2 regions, DNS/health serving failover

- **Regional, independent EKS clusters in ≥2 AWS regions** (active/active for
  serving, primary/secondary roles per service), each a **self-contained copy of
  the D1–D3 stack** (GPU Operator + DRA + Volcano + DCGM) deployed by a
  **per-region Terragrunt stack** — the pattern the AWS estate already uses
  (`terragrunt/{prod,staging,dr}/<region>/...`). No stretched/multi-cluster
  control plane and no cross-region GPU pooling in this phase. (Cross-cluster
  *east-west* within a region is a separate concern — see
  [ADR-0043](0043-eks-cross-cluster-connectivity.md).)
- **Cross-region serving failover reuses the existing health-checked failover
  mechanism**, not a new one: the in-repo **`failover-controller`** (Go,
  health-store-backed Route 53 DNS failover) + **KEDA/HPA** per cluster for
  in-region elasticity — the exact mechanism the GKE etalon reuses. A region is
  taken out of rotation on health-signal loss and serving shifts to the healthy
  region; **batch/training does NOT fail over** (gang-scheduled GPU jobs are
  region-pinned and re-queued, not migrated).
- **Capacity is deliberately asymmetric** to bound cost (R1): the secondary region
  runs **scale-to-zero GPU NodePools** (Karpenter `min` / consolidation, ADR-0046)
  and **spot-first**, sized for failover-serving headroom rather than a hot mirror
  of training capacity.

### D6 — Reaffirm scope guards (locked)

- **Greenfield, not consolidation.** This platform is a clean `aws-eks-gpu-*`
  module set. The existing `gpu-inference-*` estate stays as-is and is **not** a
  dependency (plan §7 OPEN DECISION, user-confirmed greenfield). Cross-pollination
  is at the pattern level only.
- **Bottlerocket node OS** ([ADR-0030](0030-bottlerocket-node-os.md)) for GPU
  pools — driver-pre-baked GPU AMI variant (drives the D1 `driver.enabled = false`
  delta).
- **[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) is
  mandatory** on every resource here: the five `platform:*` keys as AWS tags on
  Terraform-managed resources (every `aws-eks-gpu-*` module accepts and applies a
  `tags` map) and the five `platform.*` keys as K8s labels on the
  operator/DCGM/Volcano workloads, so the AWS GPU fleet joins the existing
  single-pane `$system` dashboards and FinOps roll-ups. `platform:system` for the
  whole platform = **`ml-platform`**; components `gpu-operator` / `gpu-dcgm` /
  `gpu-scheduling`.

A reviewer checks conformance by confirming: (a) the GPU Operator is installed
with `dcgmExporter.enabled = false` and `driver.enabled` matching the node OS
(D1); (b) `aws-eks-gpu-operator`, `aws-eks-gpu-dcgm`, `aws-eks-gpu-scheduling`
modules exist with the contracts in Implementation notes; (c) a DRA `DeviceClass`
exists and the cluster is ≥1.33 (D2); (d) the `budgets` module is wired at
80/100/120% + forecasted → SNS → Alertmanager (D4); (e) a second AWS region has
its own Terragrunt stack with the full GPU stack (D5); (f) every AWS resource
carries the five ADR-0028 tags.

## Alternatives considered

### A1 — Consolidate onto the existing `gpu-inference-*` estate (not greenfield)
Extend the in-repo `gpu-inference-eks` cluster and its `gpu-inference-{operator,
dcgm,dra,volcano,vllm}` modules into the ML platform instead of building
`aws-eks-gpu-*`.
*Rejected because:* the user explicitly chose **greenfield** to maximise
structural correspondence with the GKE design and keep the ML platform's blast
radius independent of the inference estate. The `gpu-inference-*` modules carry
inference-cluster-specific assumptions (single-cluster, a specific vLLM topology,
Kata-CC) that would couple the ML platform to that estate's lifecycle. We **reuse
their patterns** (DCGM CSV, Volcano plugin/queue layout, DRA device-class shape)
without inheriting their wiring. (This is the plan §7 OPEN DECISION; greenfield is
confirmed.)

### A2 — Standalone NVIDIA device plugin instead of the GPU Operator
Run only `k8s-device-plugin` for `nvidia.com/gpu` counting; skip the Operator.
*Rejected because:* it forfeits **DRA** (no NVIDIA DRA driver / ResourceSlice
publisher), forfeits managed GFD/NFD/CDI/MIG, and diverges from the GKE operating
model. The plain device plugin remains the fallback for non-DRA pools, so D1 makes
the Operator additive rather than the only path to a GPU.

### A3 — Kueue instead of Volcano for batch scheduling
Adopt Kueue for queueing/quota.
*Rejected because:* **no native gang scheduling**, which distributed training
requires, and it would split scheduling models across clouds (GKE runs Volcano).
Kept on the table as a future **complement** (Kueue quota *over* Volcano gang) —
see revisit trigger and plan §7.

### A4 — Build a new `aws-billing-budget` module (mirror `gcp-billing-budget` literally)
Create a fresh AWS budget module to mirror the GCP one one-to-one.
*Rejected because:* the **`budgets`** module already exists and already wraps
`aws_budgets_budget` with ACTUAL+FORECASTED thresholds, per-service/per-account
scoping, and SNS sinks — building a second one violates DRY and the repo's "reuse,
don't reinvent" rule (plan §3). The *correct* mirror of GCP D4 is to **reuse the
native AWS primitive**, not to clone the GCP module's name.

### A5 — Single-region EKS + rely on the existing estate for redundancy
Leave the ML platform single-region.
*Rejected because:* WS-A explicitly requires **regional EKS in ≥2 AWS regions**
with cross-region serving failover; a single region cannot satisfy a regional
outage or data-residency/failover requirement. (Day-1 single-region *first* with a
documented path to multi-region is a legitimate **phasing** choice — plan §7 OPEN
DECISION — but the target topology is multi-region.)

### A6 — Stretched / multi-cluster GPU pool across regions
One logical GPU pool spanning regions (ClusterMesh-style cross-region scheduling).
*Rejected because:* cross-region GPU scheduling pays inter-region latency/egress on
the hot path, deepens blast radius (a scheduler fault spans regions), and offers
little benefit for serving (Route 53 health failover suffices) — while
gang-scheduled training is not safely relocatable across regions. Independent
regional clusters (D5) keep blast radius per-region and cost bounded. (Mirrors
ADR-0036 A5.)

## Consequences

### Positive
- **Cross-cloud parity:** one GPU operating model (Operator + DRA + Volcano +
  DCGM) and one cost-guardrail behaviour across EKS and GKE — shared runbooks,
  dashboards, queue taxonomy, and ADR-0028 `$system` observability.
- **Greenfield independence:** the ML platform's lifecycle and blast radius are
  decoupled from the `gpu-inference-*` estate; either can change without the
  other.
- **Required capabilities unlocked:** DRA typed-GPU requests and gang-scheduled
  distributed training on EKS (impossible under the device-plugin-only / Kueue-only
  paths).
- **Geographic resilience:** serving survives a single AWS regional outage via the
  existing health-checked Route 53 failover; no new failover machinery.
- **Spend is observable and paged:** 80/100/120% (+forecasted) budget thresholds
  page on-call before month-end via the existing SNS→Alertmanager→PagerDuty path,
  with per-`system` CUR/OpenCost attribution.

### Negative
- **New surface to operate per region:** GPU Operator, DCGM stack, Volcano, and
  DRA device classes must be deployed and upgraded in **every** EKS region — N× the
  day-2 footprint versus single-region.
- **A second parallel GPU estate:** running `aws-eks-gpu-*` *alongside* the existing
  `gpu-inference-*` modules means two GPU module families in one repo — mitigated by
  identical ADR-0028 tagging, shared dashboards, and a clear naming split
  (`aws-eks-gpu-*` = ML platform; `gpu-inference-*` = legacy inference estate).
- **Version-skew surface widens:** GPU Operator ↔ NVIDIA DRA driver ↔ EKS version ↔
  Volcano ↔ DCGM must be co-validated per region (DRA needs EKS ≥1.33; the EFA-DRA
  constraint in ADR-0045 adds a Karpenter-vs-node-group dimension).

### Risks
- **R1 — multi-region GPU cost (highest).** A second region multiplies the most
  expensive resource. *Mitigations:* secondary region is **scale-to-zero +
  spot-first** (ADR-0046), sized for failover-serving headroom, **not** a hot
  training mirror; Volcano GPU-weighted bin-packing; `budgets` 80/100/120%
  (+forecasted) paging; ADR-0028 tags give per-`system` GPU cost attribution.
- **R4 — per-region GPU quota / Capacity Block availability.** P5/P5en/P4d and
  B200 (P6) supply is region-, quota-, and **Capacity-Block**-constrained.
  *Mitigations:* treat per-region GPU **quota / Capacity Block reservations** as an
  explicit prerequisite of bringing up region N; prefer accelerator types with
  multi-region availability; the scale-to-zero secondary lowers steady-state
  pressure but failover needs **reserved burst** capacity — not assumed.
- **GPU-stack version skew** — *Mitigation:* pin Operator/DRA/Volcano/DCGM chart
  versions per region; validate against the region's EKS version in CI plan before
  any apply.
- **EFA-DRA × Karpenter coupling** (forward-referenced) — the EFA fabric cannot use
  the DRA driver under Karpenter (ADR-0045); getting the device-plugin-vs-DRA split
  wrong yields no EFA or a broken NCCL fabric. Tracked as the top integration risk;
  decided in ADR-0045/0046.

## Implementation notes

This ADR is **planning-only**: the PR that introduces it creates **no** AWS
resources, **no** `aws-eks-gpu-*` modules, and **no** second region. Implementation
is **apply-gated** and lands as separate, plan/validate-only PRs per the AWS ML
Platform plan. Apply runs from CI on `main` after merge, never from a feature
branch or an agent.

**Conventions to match (verified against the repo):** `aws ~> 6.0`, Terraform
`~> 1.11` (per `terraform/modules/*/versions.tf`, e.g. `aws-config`,
`break-glass-user`); every module takes a `tags` (map(string)) input carrying the
five ADR-0028 keys and merges it the way the existing modules do; commit
`.terraform.lock.hcl`; one `*.tftest.hcl` per module (impl phase). Helm-release
shape, namespace, and toleration/nodeSelector conventions mirror the existing
`gpu-inference-{gpu-operator,dcgm,volcano}` modules so the two clouds (and the two
AWS estates) stay diff-able. EKS-authenticated `helm`/`kubernetes` providers use
the `aws eks get-token` exec pattern (as `catalog/units/gpu-inference-vllm`),
**not** the GCP `google_client_config` token pattern.

### Module interface contracts (for the parallel module build)

**`aws-eks-gpu-operator`** — NVIDIA GPU Operator on EKS. Mirrors GKE
`gke-gpu-operator`.
- Inputs: `cluster_name`, `cluster_endpoint`, `cluster_ca` (from `aws-eks-gpu`
  cluster), `chart_version` (NVIDIA GPU Operator), `dra_driver_enabled = true`,
  `driver_enabled` (**`false`** on Bottlerocket GPU AMIs — driver pre-baked;
  `true` on AL2023), `dcgm_exporter_enabled = false` (DCGM owned by
  `aws-eks-gpu-dcgm`), `gpu_node_selector` (default
  `{ "karpenter.sh/nodepool" = "gpu" }` or the node-group GPU label),
  `operator_cpu_limit` / `operator_memory_limit`, `namespace` (default
  `gpu-operator`), `tags`.
- Outputs: `gpu_operator_namespace`, `gpu_operator_version`, `dra_enabled`.

**`aws-eks-gpu-dcgm`** — DCGM Exporter + GPU-health auto-taint + alert rules.
Mirrors GKE `gke-gpu-dcgm` / EKS `gpu-inference-dcgm`.
- Inputs: `dcgm_exporter_version`, `namespace` (default `gpu-monitoring`),
  `enable_auto_taint` (bool, default `true`), `xid_error_threshold`,
  `temperature_threshold`, `scrape_interval`, `gpu_node_selector`,
  `alert_namespace`, `metrics_backend` (`prometheus` | `victoriametrics` — match
  the region's stack, ADR-0026), `kubectl_image`, `taint_cron_schedule`, `tags`.
- Outputs: `dcgm_namespace`, `service_monitor_name`, `auto_taint_enabled`,
  `alert_rule_name`.

**`aws-eks-gpu-scheduling`** — Volcano batch scheduler + queues + DRA device
classes. Combines GKE `gke-gpu-scheduling` (Volcano + DRA in one).
- Inputs: `chart_version` (Volcano — current line with DRA), `scheduler_replicas`,
  `controller_replicas`, `training_queue_weight` / `inference_queue_weight` /
  `batch_queue_weight`, `enable_dra` (bool, default `true` → Volcano `dra` plugin),
  `device_classes` (map: GPU SKU → CEL selector on `productName`, e.g.
  H100/A100/B200), `resource_claim_templates` (single-GPU / full-node-island /
  MIG-slice), `tags`.
- Outputs: `volcano_namespace`, `volcano_version`, `queue_names` (list),
  `device_class_names` (list).

**`budgets` (reuse, do not rebuild)** — `aws_budgets_budget` cost guardrail.
- Wire: `monthly_budget_amount`, `alert_thresholds = [80, 100, 120]`,
  `forecasted_alert_threshold = 120`, `per_service_budgets` (EC2-Compute, EKS),
  `sns_topic_arns` (→ Alertmanager bridge), `tags`. **No new module.**

**Multi-region wiring (D5):** add an AWS `aws-gpu-analysis` Terragrunt stack per
region (`terragrunt/<env>/<aws-region>/aws-gpu-analysis/terragrunt.stack.hcl`)
composing the cluster + node pools + the three `aws-eks-gpu-*` units, exactly as
`catalog/stacks/gcp-gpu-analysis` composes the GKE equivalents. The `budgets` unit
is **account-scoped once** (not per region) and filters by service/account. Pin
every chart/module ref (`?ref=vX.Y.Z`, no `main`); dev may take the latest pin,
prod the proven one.

- Effort: **M–L** (three day-2 modules + a greenfield cluster/VPC + per-region
  stack + a second region; node strategy + fabric in ADR-0045/0046).
- Rollback: each module/region is independently revertible; the existing
  `gpu-inference-*` estate and the GKE estate remain authoritative throughout.

## Revisit trigger

Re-open this decision if any of the following hold:
- **Kueue gains production-grade native gang scheduling** (or the Kueue-over-Volcano
  quota pattern is adopted estate-wide) — re-evaluate D3, potentially running
  **Kueue for quota over Volcano for gang**.
- **EKS Auto Mode / Karpenter gains EFA-DRA support** — re-evaluate the D2/ADR-0045
  device-plugin-vs-DRA split for the fabric.
- **The greenfield-vs-consolidation call is reversed** (a mandate to unify with
  `gpu-inference-*`) — revisit D6/A1 and the whole module-naming split.
- **The R1 cost envelope is breached** despite scale-to-zero + spot + budgets —
  revisit the multi-region topology (D5): fewer GPU SKUs in the secondary, or a
  cold-standby (IaC, zero running GPU) failover model.
- **A third region or a data-residency mandate** changes the topology — revisit D5.

## References

- Dynamic Resource Allocation on Amazon EKS (GA from EKS 1.33; NVIDIA DRA driver,
  ResourceSlices; recommended for 1.34+):
  <https://docs.aws.amazon.com/eks/latest/userguide/device-management.html>,
  <https://awslabs.github.io/ai-on-eks/docs/guidance/dynamic-resource-allocation>
- AWS EKS AI/ML compute & autoscaling best practices:
  <https://docs.aws.amazon.com/eks/latest/best-practices/aiml-compute.html>
- NVIDIA GPU Operator on EKS / Bottlerocket (driver pre-baked):
  <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/amazon-eks.html>
- DCGM Exporter: <https://github.com/NVIDIA/dcgm-exporter>; NVIDIA XID errors:
  <https://docs.nvidia.com/deploy/xid-errors/index.html>
- Volcano (gang scheduling, DRA): <https://volcano.sh/en/>,
  <https://github.com/volcano-sh/volcano/releases>
- Volcano vs Kueue (gang gap; Kueue-over-Volcano pattern):
  <https://www.infracloud.io/blogs/batch-scheduling-on-kubernetes/>
- `aws_budgets_budget`:
  <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget>
- In-repo references: `terraform/modules/karpenter`,
  `terraform/modules/karpenter-nodepools`, `terraform/modules/placement-group`,
  `terraform/modules/gpu-eks`, `terraform/modules/budgets`,
  `terraform/modules/gpu-inference-{gpu-operator,dcgm,dra,volcano,vllm}`,
  `failover-controller/`, `catalog/stacks/gpu-analysis`,
  `catalog/stacks/gcp-gpu-analysis`.
- Related ADRs: [ADR-0036](0036-gke-ml-infra-parity-multiregion.md) (the GKE
  etalon this mirrors); [ADR-0045](0045-aws-efa-gpu-fabric-placement-groups.md)
  (fabric); [ADR-0046](0046-eks-node-strategy-karpenter-spot.md) (node strategy);
  [ADR-0047](0047-eks-inference-serving-front-waf.md) (serving front);
  [ADR-0048](0048-aws-ml-cicd-registry-drift.md) (ML CI/CD + drift);
  [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (taxonomy —
  mandatory); [ADR-0030](0030-bottlerocket-node-os.md) (node OS);
  [ADR-0027](0027-kubernetes-cost-opencost-cur.md) (CUR/OpenCost);
  [ADR-0018](0018-eks-pod-identity-as-default-workload-identity.md) (Pod Identity /
  ABAC).

---
*Doc-verified 2026-06-15 against official AWS EKS device-management/DRA, NVIDIA GPU
Operator on EKS, Volcano, and HashiCorp `aws_budgets_budget` documentation.
Greenfield AWS mirror of the GKE etalon ADR-0036. Planning-only ADR — proposed,
not yet implemented in platform-design. WS-A "EKS GPU infrastructure parity &
elasticity"; implementation apply-gated.*
