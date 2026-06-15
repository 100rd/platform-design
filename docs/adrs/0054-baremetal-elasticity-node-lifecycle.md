# ADR-0054: Bare-metal elasticity & node lifecycle without a cloud autoscaler (Cluster-API/Metal³ vs Robot-API vs static pools)

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — there is **no node-lifecycle automation**
  for the bare-metal cluster: no Cluster-API/Metal³/Sidero install, no provider-API
  provisioning, and no fixed-pool definitions. The cloud estate has Karpenter
  (`karpenter-*` modules) and GKE node autoscaling (`gcp-gke-gpu-nodepools`) — **none
  of which exist or even make sense on owned hardware**, where a "new node" is a
  physical re-image, not a cloud API call.
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: WS-A "Bare-metal GPU cluster foundation & elasticity"
  (Bare-Metal ML Platform plan, `docs/baremetal-ml-platform/IMPLEMENTATION_PLAN.md`);
  risk-register R1 (fixed capacity). This is the bare-metal answer to the elasticity
  that [ADR-0036](0036-gke-ml-infra-parity-multiregion.md) got for free from GKE node
  autoscaling + [ADR-0007](0007-karpenter-over-cluster-autoscaler.md) Karpenter.
- Supersedes: (none)
- Superseded by: (none)

## Context

Every elasticity assumption in the cloud etalon **evaporates on bare metal**. GKE
node autoscaling (`gcp-gke-gpu-nodepools`: `min/max_node_count`, scale-to-zero
`min=0`, spot) and the EKS **Karpenter** decision
([ADR-0007](0007-karpenter-over-cluster-autoscaler.md)) both rest on a cloud API
that conjures and destroys VMs in **seconds**. On owned hardware in a UK colo
there **is no such API** — a "new node" is a **bare-metal machine being PXE-booted
and re-imaged with Talos**, a process measured in **minutes to hours**, bounded by
physical inventory you already paid for. There is **no scale-to-zero of GPUs that
saves money** (the iron is bought either way) and **no burst capacity** beyond what
sits in the racks.

`docs/transaction-analytics/06-uk-datacenters.md` already commits to the shape of
the answer: **Cluster API** (`cluster-api-provider-metal3` / `-sidero` + the Talos
bootstrap/control-plane providers) for "lifecycle management of bare-metal nodes,"
**Git-driven** ("the cluster definition lives in `terragrunt/uk/{primary,standby}/
platform/`, ArgoCD applies it, Cluster API provisions or updates nodes
accordingly"), **fixed pools** (primary sized for 100% steady state, standby ~40%),
and **Volcano queues + DRA** for sharing the fixed GPU inventory. It also pins the
hard constraint that on immutable Talos a node change is a **re-image**
([ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md)), which is exactly
why **local-path storage is unsafe** ([ADR-0052](0052-baremetal-storage-rook-ceph.md))
— re-imaging wipes the node.

This ADR decides **how elasticity actually works without a cloud autoscaler**, and
**how nodes are provisioned/recycled**, resolving the plan's OPEN DECISIONS #1
(provider), #2 (provisioning), and the lifecycle half of #8 (topology).

## Decision

Provide elasticity through **workload-level scaling on fixed-capacity pools**, and
provide node lifecycle through **Cluster-API + Sidero (Git-driven re-image)**, in
five plan/validate-only sub-decisions. Nothing applies without the gate; nothing is
applied to hardware.

### D1 — Elasticity is workload-level, not node-level (the core inversion)

There is **no node autoscaler**. Elasticity is delivered by **scaling workloads
within fixed capacity**:

- **Serving:** **KEDA/HPA scale vLLM/serving pods** up and down — including
  **scale-to-zero of pods** (reuse `keda` + `hpa-defaults`). Scaling a serving
  Deployment to zero **frees its GPUs back to the pool**; it does **not**
  deprovision a node. This is the bare-metal meaning of "scale-to-zero": **zero
  pods, not zero nodes**.
- **Batch/training:** **Volcano queues + DRA gate jobs to the fixed GPU
  inventory.** The named queue taxonomy already in `06-uk-datacenters.md` (H100:
  `training-default`/`training-bootstrap`/`training-urgent` (cap 2); H200:
  `serving-vllm`/`eval-judge`/`engine-build`/`batch-rescore`) **is the elasticity
  mechanism** — fair-share weights + capability limits decide who runs on the fixed
  GPUs, and `training-urgent` **reserves burst headroom** for drift-triggered /
  incident retrains (the R1 mitigation). DRA fractional/specific-GPU claims pack the
  small jobs (engine builds, some eval) so big GPUs stay free for training/batch.

This is the deliberate inversion of `gcp-gke-gpu-nodepools` (which scales **nodes**)
and the reason `talos-gpu-nodepool` has **no autoscaler inputs**
([ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md) D3).

### D2 — Node lifecycle = Cluster-API + Sidero (Git-driven re-image), primary

Adopt **Cluster API + Sidero** (the **Talos-native** bare-metal provider) for node
lifecycle, as the UK doc names. A node is a Cluster-API `Machine` /
`MetalMachine`; provisioning/recycling a node is **PXE-boot + Talos image apply**,
declared in Git (`terragrunt/uk/{primary,standby}/platform/`) and reconciled by
ArgoCD — **the same Git-driven model as the cloud stacks**, just with a re-image
where the cloud had an API call. **Sidero** is chosen over Metal³ as the primary
because it is **Talos-native** (purpose-built for Talos provisioning, least
impedance with the immutable model), while **Metal³ (Ironic)** is the documented
alternative for shops standardised on the OpenStack/Ironic bare-metal stack. The
**first control-plane node** is bootstrapped via **manual PXE/ISO** (the chicken-
and-egg fallback before any management cluster exists), then Cluster-API takes over.

### D3 — Capacity adds are a slow, deliberate, physical operation (not autoscaling)

Adding GPU capacity is: **rack/inventory a spare bare-metal machine → register it
with Sidero → Cluster-API re-images it into the GPU-worker class → it joins the
fixed pool.** This is **minutes-to-hours**, a planned operation, **not** a reaction
to a traffic spike. The plan's R1 (fixed capacity) is mitigated **not** by making
this fast, but by: (a) sizing primary for 100% steady state + standby headroom;
(b) workload scale-to-zero freeing GPUs fast (D1); (c) the `training-urgent`
reserved queue; (d) cross-DC failover as the last resort (D4). A burst beyond
standby headroom is a **capacity-planning** problem, surfaced by FinOps/observability,
not an autoscaling event.

### D4 — Cross-DC failover is the elasticity-of-last-resort (reuse, don't build)

When a whole DC is lost or saturated, the **existing `failover-controller` +
`dns-monitor`** (ADR-0049 D5, `uk-dc-failover.md`) shift **serving** to the standby
DC. **Batch/training does NOT fail over** — gang-scheduled GPU jobs are DC-pinned
and **re-queued**, not migrated (the same rule as ADR-0036 D5). This is reuse of
machinery that already exists, not a new elasticity system.

### D5 — Provider substrate is abstracted at the Cluster-API layer; owned-colo default

The **bare-metal provider** (OPEN DECISION #1) is abstracted **beneath Cluster-API**:
the design is **provider-agnostic at the Talos/CAPI layer**, with the provider as
the Sidero/Metal³/robot driver underneath. **Default to the owned-colo premise**
`06-uk-datacenters.md` commits to (the source of the IB fabric, dark fibre, and
2-DC topology). **Hetzner robot-API** is the cheap **emulation substrate** for the
mock/plan (and the closest match to the repo's existing `hcloud` familiarity —
though note the `hetzner-nodes` *kubeadm* module is **not** reused; only the robot
*provisioning* concept is relevant, driving Talos, not cloud-init). **Equinix Metal**
is the alternative for a first-class bare-metal-API provider. The choice does not
change D1–D4; it only changes the driver below Cluster-API.

A reviewer checks conformance by confirming: (a) `talos-gpu-nodepool` has **no
autoscaler inputs** (fixed capacity); (b) serving scales via KEDA/HPA incl.
scale-to-zero of **pods**; (c) the Volcano queue taxonomy from `06-uk-datacenters.md`
is present with `training-urgent` reserved; (d) node lifecycle is Cluster-API +
Sidero, Git-driven, with manual-PXE first-node bootstrap; (e) cross-DC failover
reuses `failover-controller`/`dns-monitor`; (f) the provider sits below CAPI and
defaults to owned-colo.

## Alternatives considered

### A1 — Port Karpenter / a node autoscaler to bare metal
Run Karpenter (or Cluster-Autoscaler) against a bare-metal provider.
*Rejected because:* Karpenter ([ADR-0007](0007-karpenter-over-cluster-autoscaler.md))
provisions **cloud instances via a cloud API in seconds**; on owned hardware there
is no instance to launch — only fixed iron to re-image in minutes-to-hours.
"Autoscaling" over a finite, pre-purchased rack is a category error: you cannot
scale past the machines you own, and scaling to zero saves no money. Cluster-API
re-image (D2) is the correct lifecycle primitive; **workload** scaling (D1) is the
correct elasticity primitive.

### A2 — Static pools only (manual PXE/ISO, no Cluster-API)
Pre-provision every node by hand and never automate lifecycle.
*Rejected as the steady state because:* it makes every node add/replace/upgrade a
manual, error-prone, non-Git-tracked operation — losing the declarative,
auditable, ArgoCD-reconciled model the UK doc explicitly wants ("Cluster lifecycle
is Git-driven"). **Kept only as the first-control-plane-node bootstrap** (D2) before
a management cluster exists.

### A3 — CAPI bare-metal provider: Sidero vs Metal³ (the two distinct options behind D2)
The Cluster-API bare-metal infrastructure provider is itself a choice with two
real, differently-shaped options — both named in `06-uk-datacenters.md` and both
referenced by §7 decision #2 of the plan, so this ADR weighs them explicitly rather
than collapsing them:

- **Sidero (`cluster-api-provider-sidero` / Sidero Omni lineage) — chosen primary.**
  **Talos-native**: built by the Talos authors specifically to PXE-boot and manage
  **Talos** machines (it pairs with the Talos bootstrap + control-plane CAPI
  providers). It speaks Talos's machine API end-to-end, so a node is provisioned and
  upgraded the same declarative, image-based way the rest of the estate is — **least
  impedance with the immutable model**, smallest moving-part count, no second OS
  abstraction. Trade-off: a smaller ecosystem than Metal³ and tighter coupling to the
  Talos world (which here is a feature, not a cost).
- **Metal³ (`cluster-api-provider-metal3` + Bare Metal Operator + Ironic) —
  documented alternative.** The CNCF/community standard bare-metal CAPI stack:
  the **Bare Metal Operator (BMO)** drives **Ironic** (the OpenStack bare-metal
  service) for inspection, IPMI/Redfish power control, and image deployment via
  `BareMetalHost` CRs. **Strengths:** broad hardware/BMC coverage, a large
  ecosystem, and it is OS-agnostic (it can deploy a Talos image too). **Costs:** it
  is **heavier** (Ironic + BMO + an image-cache/DHCP/PXE stack to operate), carries
  OpenStack/Ironic operational lineage, and adds a non-Talos abstraction layer over
  machines that are otherwise pure Talos.

*Decision:* **Sidero is primary** (Talos-native, lowest impedance); **Metal³ is the
documented alternative** for shops already standardised on Ironic/BMO or needing its
broader BMC coverage. Either satisfies D2's Git-driven re-image model; the choice is
§7 decision #2 and does not change D1/D3/D4. (Both are *rejected-as-sole-option* only
in that neither is mandated — the plan picks Sidero with Metal³ as the fallback.)

### A4 — Burst to the cloud (overflow GPU into EKS/GKE under spike)
Spill excess demand onto the cloud GPU estates when the bare metal saturates.
*Rejected as day-one scope because:* it breaks **UK data-residency** for training
data (the whole reason for owned compute), adds cross-cloud data movement on the
hot path, and re-introduces the cloud cost the bare metal was meant to avoid.
**Recorded as a revisit trigger** if the fixed-capacity envelope is chronically
breached — an explicit, deliberate exception, not a default.

### A5 — Status quo (no lifecycle automation, no elasticity story)
Leave node provisioning and elasticity unspecified.
*Rejected because:* it leaves R1 (fixed capacity) unmitigated and the cluster
un-buildable — the plan's biggest gap. An explicit fixed-capacity + workload-scaling
+ Git-driven-re-image story is required.

## Consequences

### Positive
- **Honest elasticity model:** the design stops pretending bare metal autoscales
  and instead does what actually works — **scale pods, gate jobs, re-image nodes
  deliberately** — with the Volcano queue taxonomy from the fiction as the sharing
  mechanism.
- **Git-driven node lifecycle:** Cluster-API + Sidero gives the same declarative,
  auditable, ArgoCD-reconciled lifecycle as the cloud stacks — re-image where the
  cloud had an API call.
- **R1 mitigated without magic:** steady-state sizing + standby headroom + pod
  scale-to-zero + `training-urgent` reserve + cross-DC failover bound the
  fixed-capacity risk.
- **Reuses existing machinery:** KEDA/HPA, Volcano, `failover-controller`,
  `dns-monitor`, and the UK queue taxonomy already exist or are specified — minimal
  net-new.
- **Provider flexibility:** abstracting the substrate below CAPI lets the mock run
  on Hetzner robot while the design targets owned colo.

### Negative
- **No fast burst:** a spike beyond standby headroom **cannot** be absorbed quickly
  (R1) — it is a capacity-planning event (slow re-image), not an autoscaling one.
  This is intrinsic to owned hardware, not a flaw to fix.
- **We operate bare-metal provisioning:** Sidero/Metal³, PXE, IPMI/Redfish, image
  serving — real day-2 surface the cloud hid.
- **Manual first-node bootstrap:** the chicken-and-egg control-plane bring-up is a
  hand operation (D2) before automation exists.
- **Capacity is capex:** growing the fleet is a procurement + rack-and-stack cycle
  (the UK doc's separate operational workstream), not a console click.

### Risks
- **R1 — fixed capacity / no burst (the defining risk of this ADR).**
  *Mitigations:* size primary 100% + standby headroom; pod scale-to-zero frees GPUs
  fast; `training-urgent` (cap 2) reserves incident burst; cross-DC failover (D4);
  FinOps/observability surface capacity pressure early; A4 cloud-burst is the
  explicit, residency-gated last resort.
- **Provisioning-automation failure** (Sidero/PXE/image-serve broken) blocks node
  adds/replacements. *Mitigation:* manual-PXE fallback (D2/A2) keeps the cluster
  recoverable; the management cluster + image cache are themselves monitored.
- **Re-image data loss** if a stateful workload was wrongly on local-path —
  *Mitigation:* enforced by [ADR-0052](0052-baremetal-storage-rook-ceph.md)
  (local-path only for ephemeral scratch; stateful data on replicated Ceph).

## Implementation notes

This ADR is **planning-only**: the PR introducing it creates **no** Cluster-API
install, provisions **no** nodes, and applies **nothing to hardware**.
Implementation is **apply-gated**.

**Conventions to match:** Terraform `~> 1.11`; Cluster-API/Sidero objects via a
kubectl/kubernetes provider; `talos-gpu-nodepool` (ADR-0049) carries **no**
autoscaler inputs; reuse `keda` + `hpa-defaults` for serving scaling and
`baremetal-gpu-scheduling` (ADR-0049 D4) for the Volcano queues. Carry the five
ADR-0028 keys on every resource.

### Lifecycle wiring (for the build)
- **`talos-gpu-nodepool`** (ADR-0049) gains, per this ADR, an optional
  `lifecycle_provider` (`"sidero" | "metal3" | "static" | "robot"`, default
  `"sidero"`) that, when set to a CAPI provider, drives the `Machine`/`MetalMachine`
  objects for re-image-based lifecycle; `"static"` is pre-provisioned PXE.
- **Serving elasticity:** KEDA `ScaledObject` / HPA on the vLLM Deployments
  (scale-to-zero of **pods**), reusing `keda`/`hpa-defaults`.
- **Batch elasticity:** the `baremetal-gpu-scheduling` Volcano queues
  (`training-urgent` reserved) + DRA claims — **no new module**.
- **Cross-DC:** `failover-controller` + `dns-monitor` (reused, no new code).

- Effort: **M** (Cluster-API + Sidero install + node-class wiring + the KEDA/Volcano
  reuse + the manual-PXE bootstrap runbook).
- Rollback: revert the lifecycle provider to `"static"` (manual PXE); the fixed
  pools and the cloud estate remain authoritative; nothing applied to hardware.

## Revisit trigger

Re-open this decision if any of the following hold:
- **The fixed-capacity envelope is chronically breached** despite sizing + scale-
  to-zero + reserved-queue — evaluate **A4 cloud-burst** (residency-gated) or simply
  **buy more iron** (capacity planning).
- **Sidero/Metal³ proves insufficient** for our hardware (a server the provider
  can't drive) — re-evaluate D2 (the other CAPI provider, or robot-API).
- **A managed bare-metal-as-a-service** with true elastic billing + UK residency
  appears — re-evaluate the fixed-capacity premise (D1/A1).
- **A standby-utilisation change** (e.g. standby raised above 40% for co-work)
  alters the headroom math — re-evaluate the R1 sizing.

## References

- Cluster API (bare-metal lifecycle, `Machine`/`MachineDeployment`):
  <https://cluster-api.sigs.k8s.io/>
- Sidero (Talos-native bare-metal provisioning, CAPI provider):
  <https://www.sidero.dev/>
- Metal³ (`cluster-api-provider-metal3`, Ironic): <https://metal3.io/>
- KEDA (scale-to-zero of pods): <https://keda.sh/>; HPA:
  <https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/>
- Volcano queues / fair-share / capability limits: <https://volcano.sh/en/docs/queue/>
- In-repo (HONORED): `docs/transaction-analytics/06-uk-datacenters.md` (Cluster API
  metal3/sidero, Git-driven lifecycle, fixed-pool sizing, the Volcano queue
  taxonomy + `training-urgent`, DRA for small jobs), `docs/runbooks/uk-dc-failover.md`
  (cross-DC failover), `failover-controller/`, `dns-monitor/`.
- In-repo references (the cloud elasticity this replaces): `terraform/modules/keda`,
  `catalog/units/hpa-defaults`, `terraform/modules/karpenter-nodepools`,
  `terraform/modules/gcp-gke-gpu-nodepools`.
- In-repo reference (NOT reused — kubeadm provisioning concept only):
  `terraform/modules/hetzner-nodes`.
- Related ADRs: [ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
  (`talos-gpu-nodepool` has no autoscaler; multi-DC failover),
  [ADR-0036](0036-gke-ml-infra-parity-multiregion.md) (the GKE autoscaling this
  replaces), [ADR-0007](0007-karpenter-over-cluster-autoscaler.md) (the cloud
  Karpenter decision — inapplicable on bare metal),
  [ADR-0052](0052-baremetal-storage-rook-ceph.md) (re-image is why local-path is
  unsafe), [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md).

---
*Planning-only ADR — proposed, not implemented; nothing applied to hardware
(mock/emulation repo). Bare-metal answer to GKE/Karpenter autoscaling. WS-A;
implementation apply-gated. Drafted 2026-06-15.*
