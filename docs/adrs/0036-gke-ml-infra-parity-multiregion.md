# ADR-0036: GKE ML-infrastructure parity (GPU Operator, DCGM, DRA, batch scheduling) + multi-region GKE & GCP cost guardrail

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — `gcp-gke-gpu-nodepools` and `gcp-gpu-vpc`
  exist on GCP, but none of the GKE day-2 ML modules (`gke-gpu-operator`,
  `gke-gpu-dcgm`, `gke-gpu-scheduling`) nor `gcp-billing-budget` exist yet, and
  there is no second GCP region.
- Date: 2026-06-10
- Authors: platform-team (solution-architect), infra
- Related issues: WS-A "GKE ML infrastructure parity & elasticity" (GCP ML
  Platform plan); risk-register R1 (multi-region GPU cost), R4 (GPU quota /
  capacity per region).
- Supersedes: (none)
- Superseded by: (none)

## Context

GPU compute on GCP already exists in this repo as the **`gcp-gke-gpu-nodepools`**
module: `google_container_node_pool` instances created `for_each` over a config
map, each pinned to a **single zone for GPU locality**, with **spot** support,
**scale-to-zero** autoscaling (`min_node_count = 0`), NVIDIA accelerators, taints,
and **Workload Identity** (`workload_metadata_config { mode = "GKE_METADATA" }`).
That node-pool primitive — spot / scale-to-zero / per-zone locality / Workload
Identity — is **settled and is NOT re-opened by this ADR.**

What does **not** yet exist on GKE is the **day-2 ML stack** that the EKS estate
already runs, and which gives a GPU cluster its operational surface:

- a **GPU driver/operator** layer,
- **DCGM** GPU telemetry + health auto-remediation,
- **DRA** (Dynamic Resource Allocation) device classes for typed GPU requests,
- a **batch scheduler** with gang scheduling and fair-share queues for ML
  training, plus **HPA/KEDA**-driven elasticity for serving.

The EKS side is the parity reference and is already in-repo:

| Concern | EKS module (in-repo, reference) | GKE gap (this ADR) |
|---|---|---|
| GPU operator + driver | `terraform/modules/gpu-operator` (NVIDIA GPU Operator v26.3, DRA driver, GFD/NFD/CDI/toolkit) | `gke-gpu-operator` |
| GPU telemetry + health | `terraform/modules/gpu-inference-dcgm` (DCGM Exporter v4.5, XID/ECC/temp VMRules, auto-taint CronJob) | `gke-gpu-dcgm` |
| DRA device classes | `terraform/modules/gpu-inference-dra` (`DeviceClass`/`ResourceClaimTemplate` for H100/A100) | folded into `gke-gpu-scheduling` |
| Batch scheduling | `terraform/modules/gpu-inference-volcano` (**Volcano** v1.8, gang + `dra`/`binpack`/`topology` plugins, training/inference/batch queues) | `gke-gpu-scheduling` |
| Serving elasticity | `terraform/modules/keda` (KEDA 2.16) + `hpa-defaults` | reuse on GKE |
| Cost guardrail | `terraform/modules/budgets` (`aws_budgets_budget`, 80/90/100% → SNS) | **`gcp-billing-budget`** |

Two further forces shape the decision:

1. **GKE mode is locked to Standard.** GKE **Autopilot does not support
   node-level tooling** (NVIDIA GPU Operator, custom DaemonSets, the
   device-plugin/driver disable flags). Every decision below assumes **Standard
   node pools**; Autopilot is explicitly out of scope.
2. **The plan requires multi-region.** Today GCP has a single region. WS-A asks
   for **regional GKE in ≥2 GCP regions** with **cross-region serving failover**,
   which forces a topology decision and lands squarely on risk-register **R1
   (multi-region GPU cost)** and **R4 (per-region GPU quota/capacity)**.

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (the unified
`platform:system` / `platform.system` taxonomy) is mandatory on every resource
introduced here — AWS-tag form on the Terraform plane, K8s-label form on the
workload plane — so the GCP fleet is observable/cost-attributable on the same
`$system` Grafana variable as the AWS fleet.

## Decision

Achieve **GKE ML-infrastructure parity with EKS** and add **multi-region GKE**,
via four net-new modules plus a topology decision. All five sub-decisions are
**plan/validate-only**; nothing here applies without passing the apply gate.

### D1 — GPU driver: NVIDIA GPU Operator (not the GKE-managed driver) on GKE Standard

Install the **NVIDIA GPU Operator** as the GKE GPU software layer (new
`gke-gpu-operator` module), mirroring the EKS `gpu-operator` module: GPU Feature
Discovery, Node Feature Discovery, container toolkit, CDI, and the **NVIDIA DRA
driver** — with the in-cluster **DCGM disabled in the operator** because DCGM is
owned by the dedicated `gke-gpu-dcgm` module (same split as EKS, where
`gpu-operator` sets `dcgmExporter.enabled = false`).

Chosen over GKE's fully-managed GPU driver because:

- **It is the only path that unlocks DRA on GKE.** GKE DRA for GPUs **requires**
  `gpu-driver-version=disabled` **and** the `gke-no-default-nvidia-gpu-device-plugin=true`
  node label **and** `nvidia.com/gpu.present=true` — i.e. the GKE-managed driver
  and managed device-plugin DaemonSet must be turned **off** and a driver
  DaemonSet (GPU Operator) must take over. The Operator and DRA share **exactly
  the same node prerequisites**, so they compose; the managed driver is mutually
  exclusive with both.
- **Parity / single mental model.** SREs already operate the NVIDIA GPU Operator
  (GFD/NFD/CDI/DRA) on EKS; running the same Helm release on GKE means one set
  of runbooks, dashboards, and ResourceSlice semantics across both clouds.
- It is the **NVIDIA- and Google-supported** way to manage the GPU stack on GKE
  Standard (COS or Ubuntu node images); Autopilot — where the Operator is
  unsupported — is already excluded by the GKE-Standard lock.

**Hard consequence for `gcp-gke-gpu-nodepools` (call-out, not a redesign):** the
existing module hard-codes the GKE-managed driver via
`guest_accelerator { gpu_driver_installation_config { gpu_driver_version =
"LATEST" } }`. That is **incompatible** with the GPU Operator + DRA. The
Operator-managed pools must be created with the driver **disabled** and carry the
`gke-no-default-nvidia-gpu-device-plugin=true` + `nvidia.com/gpu.present=true`
labels. The minimal node-config inputs to express that are specified in the
`gke-gpu-operator` interface contract in Implementation notes; the node-pool
module gains a thin, additive "operator-managed driver" switch (no change to its
spot/scale-to-zero/locality/Workload-Identity behaviour). This coupling is the
single highest-risk integration point of WS-A and is tracked as such.

### D2 — Batch scheduling: Volcano (not Kueue)

Deploy **Volcano** as the GKE batch scheduler (new `gke-gpu-scheduling` module),
identical in shape to the EKS `gpu-inference-volcano` module: a **secondary
scheduler** (`schedulerName: volcano`, opt-in) with the **gang**, **DRA**,
**binpack** (GPU-weighted), **topology**, and **proportion** plugins, and
`training` / `inference` / `batch` fair-share **Queues**. The same module also
ships the **DRA `DeviceClass` / `ResourceClaimTemplate`** objects (folding in the
EKS `gpu-inference-dra` role) so typed GPU requests (e.g. H100 vs A100, full
NVLink island) are available to Volcano-scheduled jobs.

Chosen over **GKE Kueue** because:

- **Native gang scheduling.** Distributed ML training needs all-or-nothing pod
  admission so a multi-GPU job never deadlocks holding a partial set. **Volcano
  provides gang scheduling natively; Kueue does not** — Kueue is job-level
  queue/quota admission that then defers pod placement to the default scheduler,
  and only approximates gang behaviour through framework integrations (e.g.
  RayJob). The EKS workloads (NCCL training mesh, `PodGroup`-based distributed
  training) are built on Volcano gang semantics today.
- **Parity.** EKS already runs Volcano with this exact plugin/queue layout;
  reusing it on GKE preserves one scheduler binary, one queue taxonomy, one set
  of `PodGroup` manifests, and one operating model across clouds. Introducing a
  second, differently-shaped scheduler (Kueue) on GKE only would split the ML
  scheduling story.
- **GPU-aware bin-packing + DRA** are first-class in Volcano (the EKS config
  already weights `binpack.resources.nvidia.com/gpu`), which maximises GPU
  packing — directly relevant to the R1 cost risk.

Kueue's strengths (lightweight, no new scheduler binary, strong hierarchical
quota) are real; the industry pattern of **Kueue-for-quota over Volcano-for-gang**
is recorded as the **revisit trigger** below, not adopted now, to keep WS-A at
strict parity with the proven EKS stack.

### D3 — DCGM telemetry + GPU health (new `gke-gpu-dcgm`)

Port the EKS `gpu-inference-dcgm` module to GKE: **DCGM Exporter** DaemonSet on
GPU nodes (custom metrics CSV — utilisation, framebuffer, temperature, power,
**XID**, **NVLink**, **ECC**), a **ServiceMonitor** into the metrics stack, the
XID/temperature/ECC/NVLink **alert rules**, and the **GPU-health auto-taint
CronJob** that taints nodes on XID/ECC bursts (`gpu-health=unhealthy:NoSchedule`)
and un-taints on recovery. GKE deltas: node selector/toleration keys follow GKE's
GPU labels (`nvidia.com/gpu.present=true` from D1) and the alert sink is the
GCP-side Alertmanager that also receives D4 budget alerts.

### D4 — GCP cost guardrail: `gcp-billing-budget` (`google_billing_budget`)

Add a **`gcp-billing-budget`** module wrapping **`google_billing_budget`**, the
GCP analogue of the EKS `budgets` module. It sets a monthly amount with
**`threshold_rules` at 0.8 / 1.0 / 1.2** (the API uses a 0.0–1.0
`threshold_percent`, so 80/100/120%), scoped by `budget_filter` to the GCP
project(s)/services that carry the GKE GPU spend, and routes **`all_updates_rule`
→ Pub/Sub topic + Cloud Monitoring notification channels → Alertmanager →
PagerDuty** (matching the plan's "80/100/120% → PagerDuty via Alertmanager"). It
sets `disable_default_iam_recipients = true` so paging is the *only* channel (no
implicit billing-admin email). A **120% / FORECASTED** rule gives early warning
ahead of the hard monthly number — the primary code-level guard for risk **R1**.

### D5 — Multi-region topology: independent regional GKE in ≥2 regions, DNS/health serving failover

- **Regional, independent GKE clusters in ≥2 GCP regions** (active/active for
  serving, with primary/secondary roles per service), each a **self-contained
  copy of the D1–D3 stack** (GPU Operator + DRA + Volcano + DCGM) deployed by a
  **per-region Terragrunt stack** — the same pattern the AWS side already uses
  (`terragrunt/{prod,staging,dr}/<region>/platform/terragrunt.stack.hcl`). No
  stretched/multi-cluster control plane and no cross-region GPU pooling in this
  phase.
- **Cross-region serving failover reuses the existing health-checked failover
  mechanism**, not a new one: the in-repo **`failover-controller`** (Go,
  health-store-backed DNS failover) + **KEDA/HPA** per cluster for in-region
  elasticity. A region is taken out of rotation on health-signal loss and serving
  shifts to the healthy region; **batch/training does NOT fail over** (jobs are
  region-pinned and re-queued, not migrated) — gang-scheduled GPU jobs are not
  safely relocatable mid-flight.
- **Capacity is deliberately asymmetric** to bound cost (R1): the secondary
  region runs **scale-to-zero GPU pools** (already supported by
  `gcp-gke-gpu-nodepools`, `min_node_count = 0`) and **spot-first**, sized for
  failover serving headroom rather than a full hot mirror of training capacity.

### D6 — Reaffirm: GKE Standard + ADR-0028 labels (locked)

- **GKE Standard only.** All GPU node pools and the D1–D3 DaemonSets/operators
  run on **Standard** node pools. **Autopilot is out of scope** for the GPU plane
  for the duration of WS-A (it blocks the Operator, custom DaemonSets, and the
  driver/device-plugin disable flags D1 depends on).
- **[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) is
  mandatory** on every resource here: the five `platform:*` keys as GCP labels on
  Terraform-managed resources (`gke-gpu-*` modules accept and apply a `labels`
  map, exactly as `gcp-gke-gpu-nodepools` already does) and the five
  `platform.*` keys as K8s labels on the operator/DCGM/Volcano workloads, so the
  GCP GPU fleet joins the existing single-pane `$system` dashboards and FinOps
  roll-ups.

A reviewer can check conformance by confirming: (a) GPU pools are created with
the GKE driver **disabled** + the `gke-no-default-nvidia-gpu-device-plugin=true`
label (D1); (b) `gke-gpu-operator`, `gke-gpu-dcgm`, `gke-gpu-scheduling`, and
`gcp-billing-budget` modules exist with the contracts in Implementation notes;
(c) a second GCP region has its own `platform` Terragrunt stack with the full
GPU stack; (d) every GCP resource carries the five ADR-0028 labels.

## Alternatives considered

### A1 — GKE-managed GPU driver instead of the GPU Operator
Keep the existing `gpu_driver_installation_config { gpu_driver_version =
"LATEST" }` managed-driver path and skip the Operator.
*Rejected because:* it is **mutually exclusive with DRA on GKE** (DRA mandates
`gpu-driver-version=disabled` + the managed device-plugin disabled), so it would
forfeit a required WS-A capability; and it diverges from the EKS operating model,
giving SREs two different GPU-stack mental models across clouds. The managed
driver remains the right default for *non-DRA, non-Operator* GPU pools, so D1
makes the Operator path an additive switch rather than ripping the managed path
out of `gcp-gke-gpu-nodepools`.

### A2 — Kueue instead of Volcano for batch scheduling
Adopt GKE-friendly **Kueue** for queueing/quota.
*Rejected because:* **no native gang scheduling**, which the distributed-training
workloads require, and it would split scheduling models across clouds (EKS runs
Volcano). Kept on the table as a future **complement** (Kueue quota *over* Volcano
gang) — see revisit trigger.

### A3 — Autopilot GPU clusters
Use GKE Autopilot to cut node-management toil.
*Rejected because:* Autopilot **does not support** the NVIDIA GPU Operator,
custom DaemonSets, or the driver/device-plugin disable flags that D1/D3 require —
it is structurally incompatible with this stack. (The GKE-Standard lock in the
WS-A scope already encodes this; A3 is recorded for completeness.)

### A4 — Single-region GKE + multi-region only on EKS
Leave GCP single-region and rely on the AWS estate for geographic redundancy.
*Rejected because:* WS-A explicitly requires **regional GKE in ≥2 GCP regions**
with cross-region serving failover; a single GCP region cannot satisfy a GCP
regional outage or GCP-local data-residency/failover requirements.

### A5 — Stretched / multi-cluster GPU pool (ClusterMesh-style) across regions
One logical GPU pool spanning regions with cross-region scheduling.
*Rejected because:* cross-region GPU scheduling pays inter-region latency/egress
on the hot path, deepens the blast radius (a scheduler/control-plane fault spans
regions), and offers little benefit for serving (DNS/health failover suffices) —
while gang-scheduled training is not safely relocatable across regions anyway.
Independent regional clusters (D5) keep blast radius per-region and cost bounded.

### A6 — GCP-side cost control via Cloud Monitoring/quotas only (no billing budget)
Rely on monitoring alerts and hard GPU quotas instead of a billing budget.
*Rejected as the sole guard because:* quotas cap *capacity*, not *spend*, and
monitoring alerts don't model forecasted month-end cost. `google_billing_budget`
with a FORECASTED 120% rule is the direct spend guardrail for R1. Per-region GPU
**quota** management (R4) is complementary and still required — it is an
operational prerequisite of D5, not a substitute for D4.

## Consequences

### Positive
- **Cross-cloud parity:** one GPU operating model (Operator + DRA + Volcano +
  DCGM) and one cost-guardrail pattern across EKS and GKE — shared runbooks,
  dashboards, queue taxonomy, and ADR-0028 `$system` observability.
- **Required capabilities unlocked:** DRA typed-GPU requests and gang-scheduled
  distributed training become available on GKE (impossible under the managed
  driver / Kueue-only paths).
- **Geographic resilience:** serving survives a single GCP regional outage via
  the existing health-checked DNS failover; no new failover machinery.
- **Spend is observable and paged:** 80/100/120% budget thresholds page on-call
  before month-end via the existing Alertmanager→PagerDuty path.

### Negative
- **New surface to operate per region:** GPU Operator, DCGM stack, Volcano, and
  DRA device classes must be deployed and upgraded in **every** GKE region — N×
  the day-2 footprint versus single-region.
- **The `gcp-gke-gpu-nodepools` driver coupling (D1)** is a real, sharp
  integration: Operator-managed pools must disable the managed driver/device
  plugin; getting that wrong yields nodes with **no working GPU driver** or a
  **double-driver** conflict. This is the module-build risk to watch.
- **Version-skew surface widens:** GPU Operator ↔ DRA driver ↔ GKE version ↔
  Volcano ↔ DCGM must be co-validated per region (DRA on GKE needs
  `1.32.1-gke.1489001+`; Volcano's DRA support is on its current line, well ahead
  of the EKS-pinned v1.8.2).

### Risks
- **R1 — multi-region GPU cost (highest).** A second region multiplies the most
  expensive resource in the estate. *Mitigations:* secondary region is
  **scale-to-zero + spot-first**, sized for failover-serving headroom, **not** a
  hot training mirror; Volcano GPU-weighted bin-packing maximises utilisation;
  `gcp-billing-budget` 80/100/120% (incl. FORECASTED) pages early; ADR-0028 labels
  give per-`system` GPU cost attribution across both regions.
- **R4 — per-region GPU quota / capacity.** GPU SKUs (and spot availability)
  differ per GCP region; a region can lack quota or stock for the required
  accelerator, breaking failover assumptions. *Mitigations:* treat per-region GPU
  **quota** as an explicit prerequisite of bringing up region N (request/track
  before enabling its pools); validate accelerator availability per region;
  prefer accelerator types with multi-region availability; the scale-to-zero
  secondary lowers steady-state quota pressure but failover still needs *burst*
  quota — that burst headroom must be reserved, not assumed.
- **GPU-stack version skew** (see Negative) — *Mitigation:* pin
  Operator/DRA/Volcano/DCGM chart versions per region and validate against the
  region's GKE version in CI plan before any apply.
- **Failover correctness for stateful serving** — DNS failover shifts traffic but
  not in-region session/state. *Mitigation:* serving must be stateless or
  externalise state; **batch/training is explicitly excluded from failover**
  (region-pinned, re-queued).

## Implementation notes

This ADR is **planning-only**: the PR that introduces it creates **no** GCP
resources, **no** `gke-gpu-*` / `gcp-billing-budget` modules, and **no** second
region. Implementation is **apply-gated** and lands as separate, plan/validate-only
PRs per the GCP ML Platform plan.

**Conventions to match (verified against the repo):** `google ~> 6.0`, Terraform
`~> 1.11` (per `gcp-gke-gpu-nodepools/versions.tf`); every module takes a
`labels` (map) input carrying the five ADR-0028 keys and merges it the way
`gcp-gke-gpu-nodepools` already does; Helm-release shape, namespace, and
toleration/nodeSelector conventions mirror the EKS `gpu-operator` /
`gpu-inference-dcgm` / `gpu-inference-volcano` / `keda` modules so the two clouds
stay diff-able.

### Module interface contracts (for the parallel module build)

These are the **input/output contracts** the Terraform Engineer should build to.
Inputs list the load-bearing ones (each module also takes `labels` (map(string))
for ADR-0028 and provider/version pins per the conventions above).

**`gke-gpu-operator`** — NVIDIA GPU Operator on GKE Standard (driver + GFD/NFD/CDI
+ DRA driver). Mirrors EKS `gpu-operator`.
- Inputs: `project_id`, `cluster_id`/`cluster_name`, `chart_version` (NVIDIA GPU
  Operator), `dra_driver_version`, `driver_enabled = true` (GKE installs the
  driver via the Operator DaemonSet — opposite of the EKS Bottlerocket default
  where the AMI pre-bakes it), `dcgm_exporter_enabled = false` (DCGM owned by
  `gke-gpu-dcgm`), `gpu_node_selector` (default `{ "nvidia.com/gpu.present" =
  "true" }`), `operator_cpu_limit` / `operator_memory_limit`, `namespace`
  (default `gpu-operator`).
- Outputs: `gpu_operator_namespace`, `gpu_operator_version`, `dra_enabled`.
- **Node-pool coupling (D1):** Operator-managed pools in `gcp-gke-gpu-nodepools`
  must be created with the managed driver **disabled** and these node labels:
  `gke-no-default-nvidia-gpu-device-plugin = "true"` and `nvidia.com/gpu.present
  = "true"`. Expose this as an additive `operator_managed_driver` (bool, default
  `false`) on `gcp-gke-gpu-nodepools` that (a) omits/clears
  `gpu_driver_installation_config` (driver disabled) and (b) injects those two
  labels — **without** touching spot/scale-to-zero/locality/Workload-Identity.

**`gke-gpu-dcgm`** — DCGM Exporter + GPU-health auto-taint + alert rules. Mirrors
EKS `gpu-inference-dcgm`.
- Inputs: `dcgm_exporter_version`, `namespace` (default `gpu-monitoring`),
  `enable_auto_taint` (bool, default `true`), `xid_error_threshold`,
  `temperature_threshold`, `scrape_interval`, `gpu_node_selector` (GKE:
  `{ "nvidia.com/gpu.present" = "true" }`), `alert_namespace`, `use_vm_rule`
  (PrometheusRule vs VMRule, match the GCP-region metrics stack), `kubectl_image`,
  `taint_cron_schedule`.
- Outputs: `dcgm_namespace`, `service_monitor_name`, `auto_taint_enabled`,
  `alert_rule_name`.

**`gke-gpu-scheduling`** — Volcano batch scheduler + queues + DRA device classes.
Combines EKS `gpu-inference-volcano` + `gpu-inference-dra`.
- Inputs: `chart_version` (Volcano — current line with DRA, ahead of EKS v1.8.2),
  `scheduler_replicas`, `controller_replicas`, `training_queue_weight` /
  `inference_queue_weight` / `batch_queue_weight`, `enable_dra` (bool, default
  `true` → enables the Volcano `dra` plugin), `device_classes` (map: GPU SKU →
  CEL `productName` selector, e.g. H100/A100 — GCP accelerator product names),
  `resource_claim_templates` (single-GPU / full-node-island / prioritized).
- Outputs: `volcano_namespace`, `volcano_version`, `queue_names` (list),
  `device_class_names` (list).

**`gcp-billing-budget`** — `google_billing_budget` cost guardrail. GCP analogue of
EKS `budgets`.
- Inputs: `billing_account` (ID), `display_name`, `monthly_budget_amount`
  (units; currency from the billing account), `budget_filter` =
  `{ projects = [...], services = optional([...]) }` (scope to the GKE/GPU
  project(s)), `threshold_percents` (default `[0.8, 1.0, 1.2]` — API is 0.0–1.0),
  `forecasted_threshold_percent` (default `1.2`, `spend_basis = FORECASTED_SPEND`),
  `pubsub_topic` (`projects/{id}/topics/{topic}` → Alertmanager bridge),
  `monitoring_notification_channels` (list, ≤5 — Cloud Monitoring → PagerDuty),
  `disable_default_iam_recipients` (default `true`).
- Outputs: `budget_id`/`budget_name`, `pubsub_topic`, `threshold_percents`.

**Multi-region wiring (D5):** add a GCP `platform` Terragrunt stack per region
(`terragrunt/<env>/<gcp-region>/platform/terragrunt.stack.hcl`) composing the GPU
node pools + the three `gke-gpu-*` units, exactly as the AWS regions compose
`eks`/`cilium`/`keda`/`hpa-defaults`. `gcp-billing-budget` is **org/project-scoped
once** (not per region) and filters by project. Pin every chart/module ref
(`?ref=vX.Y.Z`, no `main`); dev may take the latest pin, prod the proven one.

- Effort: **M–L** (four modules + per-region day-2 stack + node-pool driver
  coupling + a second region).
- Rollback: each module/region is independently revertible; the existing
  single-region GPU plane and the EKS estate remain authoritative throughout.

## Revisit trigger

Re-open this decision if any of the following hold:
- **Kueue gains production-grade native gang scheduling** (or the
  Kueue-over-Volcano quota pattern is adopted estate-wide) — re-evaluate D2,
  potentially running **Kueue for quota over Volcano for gang**.
- **GKE-managed GPU drivers gain DRA compatibility** (managed driver +
  DRA + device plugin coexist) — re-evaluate D1; the Operator coupling on
  `gcp-gke-gpu-nodepools` could be dropped.
- **GKE Autopilot adds GPU Operator / custom-DaemonSet / DRA support** —
  re-evaluate the Standard lock (D6/A3).
- **The R1 cost envelope is breached** despite scale-to-zero + spot + budgets —
  revisit the multi-region topology (D5): fewer GPU SKUs in the secondary, or a
  cold-standby (infra-as-code, zero running GPU) failover model.
- **A third region or a data-residency mandate** changes the topology — revisit
  D5 (and whether per-region independent clusters still suffice vs. a managed
  multi-cluster fleet).

## References

- NVIDIA GPU Operator on GKE (Standard; not Autopilot; disable managed driver +
  device plugin): <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/google-gke.html>,
  <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/gpu-operator>
- GKE GPUs in Standard node pools / driver install options
  (`gpu-driver-version`): <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/gpus>,
  <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/gpus>
- GKE Dynamic Resource Allocation (DRA) for GPUs — GA; requires
  `1.32.1-gke.1489001+`, `gpu-driver-version=disabled`,
  `gke-no-default-nvidia-gpu-device-plugin=true`, `nvidia.com/gpu.present=true`:
  <https://cloud.google.com/kubernetes-engine/docs/how-to/set-up-dra>
- DCGM Exporter: <https://github.com/NVIDIA/dcgm-exporter>; NVIDIA XID errors:
  <https://docs.nvidia.com/deploy/xid-errors/index.html>
- Volcano (gang scheduling, DRA, v1.12+): <https://volcano.sh/en/>,
  <https://github.com/volcano-sh/volcano/releases>
- Kueue vs Volcano (gang scheduling gap; Kueue-over-Volcano pattern):
  <https://www.infracloud.io/blogs/batch-scheduling-on-kubernetes/>
- `google_billing_budget` (threshold_rules, all_updates_rule/pubsub,
  monitoring_notification_channels, disable_default_iam_recipients):
  <https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/billing_budget>
- KEDA: <https://keda.sh/>
- In-repo references: `terraform/modules/gpu-operator`,
  `terraform/modules/gpu-inference-dcgm`, `terraform/modules/gpu-inference-volcano`,
  `terraform/modules/gpu-inference-dra`, `terraform/modules/keda`,
  `terraform/modules/budgets`, `terraform/modules/gcp-gke-gpu-nodepools`,
  `failover-controller/`.
- Related ADRs: [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md)
  (tagging/labeling taxonomy — mandatory here).

---
*Doc-verified 2026-06-10 against official Google Cloud GKE, NVIDIA GPU Operator,
Volcano, and HashiCorp `google_billing_budget` documentation. Planning-only ADR —
proposed, not yet implemented in platform-design. WS-A "GKE ML infrastructure
parity & elasticity"; implementation apply-gated.*
