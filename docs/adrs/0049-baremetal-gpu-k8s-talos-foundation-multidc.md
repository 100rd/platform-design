# ADR-0049: Bare-metal GPU Kubernetes on Talos Linux — foundation, immutability & multi-DC

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — the bare-metal GPU cluster is **design-only
  fiction**: `docs/transaction-analytics/06-uk-datacenters.md` specifies Talos +
  Cluster API + InfiniBand + Volcano + MinIO across two UK DCs, but **no
  `talos-machineconfig` / `talos-cluster` / `talos-gpu-nodepool` module exists**,
  there is no `baremetal-cilium-lb` / `baremetal-rook-ceph` unit, and the only
  bare-metal-adjacent code (`terraform/modules/hetzner-nodes`) is a kubeadm path
  this ADR explicitly does **not** reuse.
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: WS-A "Bare-metal GPU cluster foundation & elasticity"
  (Bare-Metal ML Platform plan, `docs/baremetal-ml-platform/IMPLEMENTATION_PLAN.md`);
  risk-register R1 (fixed capacity), R3 (self-operated control plane), R7 (no
  managed services). Greenfield bare-metal mirror of
  [ADR-0036](0036-gke-ml-infra-parity-multiregion.md).
- Supersedes: (none)
- Superseded by: (none)

## Context

The repo already commits, in product fiction, to **owned bare-metal GPU compute
on Talos Linux** as the home of all training, template-mining, and
LLM-as-judge evaluation. `docs/transaction-analytics/06-uk-datacenters.md` is
explicit: two UK colocation DCs (**primary** + **standby**), **Talos Linux** for
the Kubernetes layer, **Cluster API** (`cluster-api-provider-metal3` /
`cluster-api-provider-sidero` + the Talos bootstrap/control-plane providers) for
node lifecycle, **Ansible** for everything below Talos's declarative surface
(`bare-metal-firmware`, `nic-tuning`, `gpu-nodes`, `network-fabric`, …), H100
training + H200 inference + CPU + storage pools, **400 Gbps InfiniBand** with
NVSwitch, **Volcano** queues with a named taxonomy, **MinIO** object pools, and
**namespace-per-tenant** multi-tenancy. `docs/runbooks/uk-dc-failover.md`
specifies primary-active + standby-hot-standby with the in-repo
**`failover-controller`** + **`dns-monitor`** and RPO < 60 s / RTO < 15 min
targets.

None of this exists as **code**. This ADR is the foundation decision that turns
the fiction into an IaC build target, and it is the **greenfield bare-metal mirror
of [ADR-0036](0036-gke-ml-infra-parity-multiregion.md)** (which brought GPU-on-GKE
to parity + multi-region). The GCP etalon and this ADR solve the **same problem
shape** — a multi-region/multi-DC GPU Kubernetes platform with DRA, Volcano, DCGM,
and health-checked failover — but the substrate inverts three foundational
assumptions:

| Concern | GCP etalon (ADR-0036) | Bare-metal (this ADR) |
|---|---|---|
| Control plane | **GKE-managed** (Google runs the API server + etcd) | **Self-operated Talos control plane** — we run etcd, KubePrism, upgrades |
| Node OS | GKE COS/Ubuntu, mutable, SSH-able | **Talos Linux — immutable, no shell, no SSH, no package manager**, declarative `MachineConfig` over mTLS |
| Node lifecycle / elasticity | GKE node autoscaling (`min/max_node_count`, scale-to-zero, spot) | **No cloud autoscaler** — fixed pools + Cluster-API re-image + workload scale-to-zero (ADR-0054) |
| Region model | regional GKE in ≥2 GCP regions | **≥2 owned UK DCs** (primary + standby), independent clusters |
| Cost guardrail | `gcp-billing-budget` (per-call cloud spend) | **owned-capacity FinOps** — capex/colo, no per-call meter to budget |

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (the unified
`platform:system` / `platform.system` taxonomy) is mandatory on every resource
introduced here — but its enforcement policy (`tests/opa/platform_tags.rego`) is
**AWS-shaped** (its `_exempt_types` and the `tags["platform:system"]` lookup
assume `aws_*` resources), so a **bare-metal/`talos_*` profile for the OPA policy
is a required follow-up** (called out below and in the plan's OPEN DECISIONS).

The explicit user constraint is **Talos immutable**. The repo's
`terraform/modules/hetzner-nodes` (+ `terraform/user_data/hetzner-kubeadm.sh`) is a
**Hetzner-Cloud, cloud-init, kubeadm-join** path onto a **mutable Ubuntu host with
SSH keys** — the exact opposite posture — and is **reference only, not reused**.

## Decision

Build an **owned bare-metal GPU Kubernetes platform on Talos Linux** as
declarative IaC, in six plan/validate-only sub-decisions. Nothing here applies
without passing the apply gate, and **nothing is ever applied to real hardware**
(mock/emulation repo). This ADR is the **foundation**; the four hardest
sub-stories get their own ADRs ([0050](0050-talos-gpu-driver-system-extensions.md)
driver, [0051](0051-baremetal-networking-cilium-lb-bgp.md) networking,
[0052](0052-baremetal-storage-rook-ceph.md) storage,
[0053](0053-baremetal-gpu-fabric-roce-infiniband.md) fabric,
[0054](0054-baremetal-elasticity-node-lifecycle.md) elasticity).

### D1 — Talos Linux as the immutable node OS for control plane and GPU workers

Adopt **Talos Linux** for both control-plane and GPU-worker machine classes,
rendered as declarative `MachineConfig` by a new **`talos-machineconfig`** module
(via the `siderolabs/talos` provider: `talos_machine_secrets`,
`talos_machine_configuration`, `talos_client_configuration`). This formalizes the
fiction in `06-uk-datacenters.md`. The decisive properties:

- **Immutable + minimal:** no shell, no SSH, no package manager; the OS surface is
  a small API. This is the security posture, not an inconvenience (see
  [ADR-0050](0050-talos-gpu-driver-system-extensions.md) for the GPU-driver
  consequence and WS-E for the SOC mapping).
- **Declarative, same mental model as the Terragrunt stacks:** machine config, k8s
  version, disk layout, network, and **system extensions** are all config — the
  team's IaC mental model transfers (the UK doc makes this argument explicitly).
- **Atomic upgrades:** A/B system-partition install + reboot, **auto-rollback on
  boot failure** — the upgrade story for a self-operated cluster.
- **No host bootstrap script.** A node joins by booting the Talos image with its
  `MachineConfig`; there is **no `kubeadm-join` / cloud-init** step. This is the
  explicit replacement for `terraform/user_data/hetzner-kubeadm.sh`.

Rejected alternatives (RKE2, k3s, Ubuntu+kubeadm) are recorded below — they are
the alternatives the UK doc itself weighed.

### D2 — Self-operated control plane: etcd + KubePrism + VIP

Stand up the Kubernetes control plane **ourselves** (new **`talos-cluster`**
module: `talos_machine_bootstrap`, `talos_cluster_kubeconfig`), because no managed
control plane exists on owned hardware. This brings **etcd ownership** (snapshot +
restore are now ours), a **control-plane VIP** + **KubePrism** (Talos's in-cluster
API-server load-balancing/HA so workloads reach the API even if an endpoint dies),
and **control-plane upgrade/quorum** as first-class operational concerns. The
execution model therefore adds **etcd-snapshot-and-verify before any control-plane
`MachineConfig` change or Talos upgrade**, and a **quorum check before draining a
control-plane node** (plan §6) — gates the GKE etalon never needed.

### D3 — GPU node pools are fixed-capacity (no autoscaler), driver via system extension

A new **`talos-gpu-nodepool`** module expresses a *logical* GPU pool over a set of
bare-metal machines bound to the GPU-worker machine class, with taints/labels
(`nvidia.com/gpu.present=true` + the five ADR-0028 keys). It is the bare-metal
analogue of `gcp-gke-gpu-nodepools` **minus the autoscaler** — there is no
`min/max_node_count`, no spot, no scale-to-zero *of nodes*. The **NVIDIA driver
is delivered as a Talos system extension** baked into the image, not installed on
a host ([ADR-0050](0050-talos-gpu-driver-system-extensions.md)); the GPU Operator
runs **driver-less** on top. Elasticity is **workload-level** (KEDA/HPA scale
pods, Volcano gates jobs) and **node-level only via re-image**
([ADR-0054](0054-baremetal-elasticity-node-lifecycle.md)).

### D4 — Day-2 GPU stack at parity with the cloud estate (ported shapes)

Port the proven day-2 GPU stack to bare metal, reusing the **shape** of the
existing EKS/GKE modules (the Helm releases, queue taxonomy, DRA semantics, and
auto-taint logic are substrate-independent):

| Concern | Cloud reference (in-repo) | Bare-metal module (this ADR) |
|---|---|---|
| GPU Operator (driver-less) | `gke-gpu-operator` / `gpu-operator` | `baremetal-gpu-operator` (`driver.enabled=false`) |
| DCGM + health auto-taint | `gke-gpu-dcgm` / `gpu-inference-dcgm` | `baremetal-gpu-dcgm` |
| Volcano + DRA | `gke-gpu-scheduling` / `gpu-inference-volcano` + `gpu-inference-dra` | `baremetal-gpu-scheduling` (with the **exact UK queue taxonomy** from `06-uk-datacenters.md`) |
| Serving elasticity | `keda` + `hpa-defaults` | reuse unchanged |

`baremetal-gpu-scheduling` ships the **named Volcano queues already specified** in
`06-uk-datacenters.md` (H100: `training-default`/`training-bootstrap`/
`training-urgent`; H200: `serving-vllm`/`eval-judge`/`engine-build`/
`batch-rescore`), so the queue taxonomy is honoured, not invented. Networking
([0051](0051-baremetal-networking-cilium-lb-bgp.md)), storage
([0052](0052-baremetal-storage-rook-ceph.md)), and fabric
([0053](0053-baremetal-gpu-fabric-roce-infiniband.md)) are split into their own
ADRs because each is a genuine bare-metal decision with alternatives.

### D5 — Multi-DC topology: independent per-DC clusters + the existing health-checked failover

- **Independent Talos clusters per DC** (primary + standby), each a self-contained
  copy of the D1–D4 stack, deployed by a **per-DC Terragrunt stack**
  (`catalog/stacks/baremetal-gpu-analysis` placed under
  `terragrunt/uk/{primary,standby}/platform/` — the path the UK doc already
  names). **No stretched/multi-cluster control plane** across DCs.
- **Cross-DC failover reuses the existing machinery, not a new one:** the in-repo
  **`failover-controller`** (Go, raft, anti-split-brain) + **`dns-monitor`** +
  `dns-sync`, exactly as `docs/runbooks/uk-dc-failover.md` already specifies. A DC
  is taken out of rotation on health-signal loss and **serving** shifts to the
  standby; **batch/training is DC-pinned and re-queued, not migrated**
  (gang-scheduled GPU jobs are not safely relocatable mid-flight — the same rule
  as ADR-0036 D5).
- **Capacity is deliberately asymmetric** to bound cost: standby runs at ~40% of
  primary (per the UK doc), sized for failover serving headroom, not a hot
  training mirror. This is the bare-metal analogue of ADR-0036's scale-to-zero
  secondary — except here it is **fixed iron at 40%**, not an autoscaled `min=0`.

### D6 — Reaffirm: ADR-0028 labels mandatory; OPA policy needs a bare-metal profile

- **[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) is
  mandatory** on every resource here: the five `platform_*` keys as labels on
  Terraform-managed resources and the five `platform.*` keys as Talos
  `machine.nodeLabels` / K8s labels on the workloads, so the bare-metal fleet
  joins the same single-pane `$system` dashboards and FinOps roll-ups as the cloud
  estate.
- **The OPA enforcement policy must gain a bare-metal profile.**
  `tests/opa/platform_tags.rego` keys on `tags["platform:system"]` and an
  `aws_*`-shaped `_exempt_types` set — it will not see `talos_*` /
  `kubernetes_manifest` resources. A follow-up adds a bare-metal/`talos_*` profile
  (or a parallel rego) so plan-time enforcement holds on this estate. This is a
  **tracked follow-up, not a blocker** for the foundation, and is listed in the
  plan's OPEN DECISIONS.

A reviewer can check conformance by confirming: (a) `talos-machineconfig` renders
control-plane + GPU-worker configs with **no SSH** and the ADR-0050 driver
extension; (b) `talos-cluster` owns etcd + KubePrism + the snapshot schedule;
(c) `talos-gpu-nodepool` has **no autoscaler inputs**; (d) the four day-2 modules
exist with the UK Volcano queue taxonomy; (e) a per-DC stack exists for primary +
standby under `terragrunt/uk/...`; (f) the `failover-controller`/`dns-monitor` are
wired (not re-implemented); (g) every resource carries the five ADR-0028 keys.

## Alternatives considered

### A1 — Managed Kubernetes (EKS/GKE) instead of self-operated Talos
Run the GPU workloads on a managed control plane and skip operating Talos.
*Rejected because:* the product premise (`06-uk-datacenters.md`) is **owned UK
bare metal** for cost (2–4× cheaper at our continuous-high-duty-cycle GPU pattern
over 3 years) and physical-layer knobs (NIC tuning, NUMA pinning, thermal
profiles, IB fabric) **not exposed on cloud instance types** — and UK
data-residency for training data. Managed K8s forfeits all of these. The cloud
estates (EKS/GKE) already exist and are **kept** for their workloads; this is
additive, not a replacement.

### A2 — Rancher RKE2 on the bare metal instead of Talos
Use RKE2 for a more flexible, more familiar distro.
*Rejected because:* (the UK doc's own reasoning) RKE2 is more flexible but has a
**larger attack surface and heavier operational cost**; Talos's immutable, no-SSH,
API-driven, atomic-upgrade model is the security and ops posture we want, and its
declarative config matches the team's Terragrunt mental model.

### A3 — k3s on the bare metal
Use k3s for a lightweight distro.
*Rejected because:* k3s is **better suited to edge than to 10+ node GPU DC
workloads** (the UK doc's words); it is not the right fit for the H100/H200 pool
scale and the InfiniBand/DRA/Volcano stack.

### A4 — Stock Ubuntu + kubeadm (the `hetzner-nodes` path)
Reuse `terraform/modules/hetzner-nodes` + `hetzner-kubeadm.sh`: cloud-init a
mutable Ubuntu host and `kubeadm join`.
*Rejected because:* it is the **opposite of the user's chosen immutable posture** —
mutable host, SSH keys, a host-side bootstrap script, and per-host config drift —
and the UK doc explicitly rejects "stock Ubuntu + kubeadm" as "reimplementing what
Talos gives us for free." Kept strictly as **reference**, never reused.

### A5 — Stretched / ClusterMesh single cluster across both DCs
One logical cluster spanning primary + standby with cross-DC scheduling.
*Rejected because:* cross-DC scheduling pays inter-DC latency on the hot path and
**deepens blast radius** (a control-plane/etcd fault spans both DCs), while
gang-scheduled training is not safely relocatable across DCs anyway. Independent
per-DC clusters + the existing health-checked DNS failover (D5) keep blast radius
per-DC — the same conclusion ADR-0036 D5/A5 reached for GCP regions.

### A6 — Status quo (leave the bare-metal DC as design-only fiction)
Keep `06-uk-datacenters.md` as a doc and run everything on the cloud estates.
*Rejected because:* the plan's gap map (#1) identifies the bare-metal cluster as
the **biggest open gap**, and the product economics + UK data-residency premise
require owned compute. Doing nothing leaves the training/eval/mining workloads
without their specified home.

## Consequences

### Positive
- **The fiction becomes a buildable target:** one coherent IaC foundation for the
  UK DCs, mirroring the proven GCP/EKS GPU operating model (Operator + DCGM +
  Volcano + DRA) so runbooks, dashboards, queue taxonomy, and ADR-0028 `$system`
  observability are **shared across cloud and bare metal**.
- **Security posture by construction:** immutable, no-SSH, mTLS-API Talos is a
  smaller attack surface than any mutable distro — a WS-E SOC asset, not just an
  ops choice.
- **Cost + control:** owned GPU compute at the documented 2–4× saving with
  physical-layer tuning the cloud cannot expose, and UK data-residency for
  training data.
- **Geographic resilience with no new machinery:** serving survives a DC outage
  via the **existing** `failover-controller`/`dns-monitor`.

### Negative
- **We now operate a control plane.** etcd backup/restore, control-plane upgrades,
  and quorum management are ours — concerns GKE hid (R3). The execution model gains
  etcd-snapshot and quorum gates.
- **No elasticity safety valve.** Fixed capacity means a burst beyond standby
  headroom cannot be autoscaled away (R1); the mitigation is workload scale-to-zero
  + the `training-urgent` reserved queue + slow node re-image, not fast node
  autoscaling (ADR-0054).
- **N× day-2 footprint per DC**, same as ADR-0036's per-region cost — the GPU
  Operator, DCGM, Volcano, DRA, Ceph, and fabric stacks deploy in **every** DC.
- **Wider upgrade/version-skew surface** with no managed backstop: Talos release ↔
  k8s version ↔ GPU system extension ↔ NVIDIA driver ↔ NCCL ↔ Volcano ↔ DCGM ↔
  Ceph must be co-validated per DC (R2, R7).
- **The OPA policy gap** (D6) must be closed before plan-time tag enforcement is
  real on this estate.

### Risks
- **R3 — self-operated control plane (highest-new).** *Mitigations:* etcd snapshot
  + verify before every control-plane change; quorum check before drain; KubePrism
  API HA; standby DC for catastrophic loss; Talos auto-rollback on boot failure.
- **R1 — fixed capacity.** *Mitigations:* size primary for 100% steady state +
  standby headroom; workload scale-to-zero; `training-urgent` reserved queue;
  Cluster-API re-image for slow capacity adds (ADR-0054).
- **R7 — no managed services widens ops/upgrade surface.** *Mitigations:* atomic
  A/B upgrades + auto-rollback; Git-driven Cluster-API lifecycle; reuse the
  existing observability + failover; WS-E runbooks.
- **Version skew across the whole stack** — *Mitigation:* pin Talos release +
  system-extension + every chart per DC; validate on standby before primary;
  NCCL-bandwidth + DCGM checks as gates.

## Implementation notes

This ADR is **planning-only**: the PR that introduces it creates **no** bare-metal
resources, **no** `talos-*` / `baremetal-*` modules, **no** cluster, and applies
**nothing to hardware**. Implementation is **apply-gated** and lands as separate,
plan/validate-only PRs per the Bare-Metal ML Platform plan.

**Conventions to match (verified against the repo):** Terraform `~> 1.11` (per
`gcp-gke-gpu-nodepools/versions.tf`); providers `siderolabs/talos` (machine/client
config) + a kubectl/kubernetes provider for Cluster-API/Metal³/Sidero CRs +
optionally `bpg/proxmox` or `hetznercloud/hcloud` per the OPEN-DECISION substrate;
every module takes a `labels` (map(string)) input carrying the five ADR-0028 keys;
Helm-release/namespace/toleration conventions mirror the existing `gpu-operator` /
`gpu-inference-dcgm` / `gpu-inference-volcano` modules so cloud and bare metal stay
diff-able. The Ansible-below-Talos roles (`bare-metal-firmware`/`nic-tuning`/
`gpu-nodes`/`network-fabric`) named in `06-uk-datacenters.md` sit **outside**
Terraform and are referenced, not rebuilt.

### Module set introduced (contracts detailed in the sub-ADRs)
- **`talos-machineconfig`** — control-plane + GPU-worker `MachineConfig`
  (immutable, no-SSH, KubePrism, system-extension list incl. the NVIDIA driver,
  `machine.nodeLabels` with ADR-0028 keys).
- **`talos-cluster`** — bootstrap + etcd + control-plane VIP/KubePrism + etcd
  snapshot schedule.
- **`talos-gpu-nodepool`** — fixed-capacity GPU pool (no autoscaler), taints/labels.
- **`baremetal-cilium-lb`** ([ADR-0051](0051-baremetal-networking-cilium-lb-bgp.md)),
  **`baremetal-rook-ceph`** ([ADR-0052](0052-baremetal-storage-rook-ceph.md)),
  **`baremetal-gpu-operator`**/**`baremetal-gpu-dcgm`**/**`baremetal-gpu-scheduling`**
  (this ADR, D4), **`baremetal-gpu-fabric`**
  ([ADR-0053](0053-baremetal-gpu-fabric-roce-infiniband.md)),
  **`baremetal-ingress-waf`** ([ADR-0053](0053-baremetal-gpu-fabric-roce-infiniband.md)).
- **Stack:** `catalog/stacks/baremetal-gpu-analysis/terragrunt.stack.hcl`, composed
  per DC under `terragrunt/uk/{primary,standby}/platform/`.

- Effort: **XL** (a greenfield cluster foundation + control plane + day-2 stack +
  storage + fabric + two DCs — the largest single workstream in the plan).
- Rollback: each module/DC is independently revertible; the cloud estates (EKS/GKE)
  and the existing UK-DC fiction remain authoritative throughout; nothing is
  applied to hardware.

## Revisit trigger

Re-open this decision if any of the following hold:
- **A managed bare-metal Kubernetes offering** with our required physical-layer
  control + UK residency appears (e.g. a managed Talos/CAPI service) — re-evaluate
  D2 (self-operated control plane).
- **Talos drops a capability we depend on** (system extensions, KubePrism, the
  `siderolabs/talos` provider) — re-evaluate D1.
- **A third DC or a changed data-residency mandate** alters the topology —
  re-evaluate D5 (and whether independent per-DC clusters still suffice).
- **The fixed-capacity envelope is chronically breached** — re-evaluate the
  elasticity model with ADR-0054 (more standby iron, or a burst-to-cloud overflow).

## References

- Talos Linux (immutable, API-driven, no SSH, system extensions, KubePrism,
  A/B upgrades): <https://www.talos.dev/>,
  <https://www.talos.dev/latest/talos-guides/configuration/system-extensions/>
- `siderolabs/talos` Terraform provider:
  <https://registry.terraform.io/providers/siderolabs/talos/latest/docs>
- Cluster API + Sidero (Talos-native bare-metal) / Metal³:
  <https://www.sidero.dev/>, <https://metal3.io/>,
  <https://cluster-api.sigs.k8s.io/>
- NVIDIA GPU Operator (driver-less mode for prebaked drivers):
  <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html>
- Volcano (gang scheduling, DRA): <https://volcano.sh/en/>
- In-repo fiction (HONORED): `docs/transaction-analytics/06-uk-datacenters.md`,
  `docs/runbooks/uk-dc-failover.md`, `failover-controller/`, `dns-monitor/`,
  `ai-sre/knowledge/{gpu-driver-updates,nccl-troubleshooting,cilium-bgp-issues}.md`.
- In-repo reference (NOT reused): `terraform/modules/hetzner-nodes`,
  `terraform/user_data/hetzner-kubeadm.sh`.
- In-repo cloud references (shape ported): `terraform/modules/gpu-operator`,
  `gpu-inference-dcgm`, `gpu-inference-volcano`, `gpu-inference-dra`, `keda`,
  `gke-gpu-operator`, `gke-gpu-dcgm`, `gke-gpu-scheduling`.
- Related ADRs: [ADR-0036](0036-gke-ml-infra-parity-multiregion.md) (GCP etalon —
  this is its bare-metal mirror), [ADR-0050](0050-talos-gpu-driver-system-extensions.md),
  [ADR-0051](0051-baremetal-networking-cilium-lb-bgp.md),
  [ADR-0052](0052-baremetal-storage-rook-ceph.md),
  [ADR-0053](0053-baremetal-gpu-fabric-roce-infiniband.md),
  [ADR-0054](0054-baremetal-elasticity-node-lifecycle.md),
  [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (mandatory).

---
*Planning-only ADR — proposed, not implemented; nothing applied to hardware
(mock/emulation repo). Greenfield bare-metal mirror of ADR-0036. WS-A "Bare-metal
GPU cluster foundation & elasticity"; implementation apply-gated. Drafted
2026-06-15.*
