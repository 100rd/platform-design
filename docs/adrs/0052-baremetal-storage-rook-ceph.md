# ADR-0052: Bare-metal storage for ML artifacts & state — Rook-Ceph vs Mayastor vs local-path (+ S3-compatible artifact store)

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — no `baremetal-rook-ceph` and no
  `baremetal-ml-artifact-store` module exist; the cluster has **no CSI, no
  replicated block/FS, and no in-DC S3 endpoint**. `06-uk-datacenters.md` names
  MinIO pools + tiered NVMe and CloudNativePG, and the cloud ML layer uses a
  GCS-backed `ml-artifact-store` — but on bare metal there is no managed object
  store and (Talos being immutable) no host-level storage daemon.
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: WS-A "Bare-metal GPU cluster foundation & elasticity" + WS-B "ML
  CI/CD + model registry" (Bare-Metal ML Platform plan,
  `docs/baremetal-ml-platform/IMPLEMENTATION_PLAN.md`); risk-register R5 (storage
  SPOF). Bare-metal substitute for the GCS-backed `ml-artifact-store`
  ([ADR-0037](0037-ml-cicd-pipeline-mlflow.md)) and for cloud block storage.
- Supersedes: (none)
- Superseded by: (none)

## Context

The cloud etalon assumes **managed storage**: GCS for the MLflow artifact store
(the `ml-artifact-store` module + [ADR-0037](0037-ml-cicd-pipeline-mlflow.md)),
Cloud SQL / RDS for Postgres, and a managed CSI for block PVCs. On owned bare
metal **none of this exists** and two constraints from
[ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md) shape the answer:

1. **Talos is immutable** — there is no host package manager, so a storage backend
   that expects host-level daemons/packages (a hand-rolled Ceph on the OS, a host
   ZFS install) is awkward; the storage layer must be **self-contained as pods /
   CSI** that runs on the locked-down OS.
2. **Ceph block CSI needs kernel modules Talos does not load by default.**
   Rook-Ceph's `csi-rbdplugin` maps RBD volumes via the **`rbd`** kernel module
   (and CephFS/RBD paths use **`ceph`**); on minimal immutable Talos these are
   **not loaded** unless declared in **`machine.kernel.modules`**. Without them the
   `csi-rbdplugin` DaemonSet crash-loops and **RBD PVCs never mount** — this is the
   single load-bearing prerequisite for Ceph on Talos, and it lives in the Talos
   `MachineConfig` ([`talos-machineconfig`](0049-baremetal-gpu-k8s-talos-foundation-multidc.md)),
   not in the Rook chart. (Rook on Talos additionally needs **kubelet extra-mounts**
   for the Rook data dir, the **network sysctls**, and **raised open-file limits**
   for the OSDs — all `MachineConfig`/Talos-side, none installable on a running host.)
3. **The ML layer needs three storage shapes at once:** **(a) replicated block**
   (Postgres for MLflow/tenant metadata via CloudNativePG; Qdrant; QuestDB), **(b)
   shared filesystem** (some Airflow/data workflows), and **(c) S3-compatible
   object** (MLflow artifacts + Iceberg cold tier + the `train→register→deploy`
   pipeline). The cloud got (c) from GCS/S3; bare metal must provide it in-DC for
   **UK data-residency** of training data.

`06-uk-datacenters.md` already commits to **MinIO pools** (with MinIO
**site-replication** for cross-DC DR) and tiered NVMe + HDD storage chassis, and
to **CloudNativePG** for Postgres with **streaming replication** to the standby.
So the fiction already implies an object store (MinIO) and replicated Postgres —
this ADR must choose the **block/FS CSI** and reconcile it with the **S3 artifact
store**, honouring those commitments rather than overriding them.

The decision space: **block/FS CSI** = Rook-Ceph vs Mayastor/OpenEBS vs local-path;
**S3 artifact store** = MinIO vs Ceph-RGW vs external S3. The two interact: if
Rook-Ceph is the CSI, its **RGW** gives S3 "for free," which competes with the
already-specified MinIO.

## Decision

Adopt **Rook-Ceph** as the default block + filesystem + object (**RGW S3**)
storage substrate, with **MinIO honoured as the artifact-store default** (and
Ceph-RGW as the consolidating alternative), in five plan/validate-only
sub-decisions. Nothing applies without the gate; nothing is applied to hardware.

### D1 — Rook-Ceph as the default storage substrate (block + FS + object)

The new **`baremetal-rook-ceph`** module deploys a **Rook-managed Ceph cluster**
(the Rook operator + a `CephCluster` over the storage-chassis NVMe/HDD from
`06-uk-datacenters.md`), exposing **RBD block** (`CephBlockPool` →
`StorageClass`), **CephFS shared filesystem**, and **RGW object** (`CephObjectStore`
→ an **S3-compatible endpoint**). Rook-Ceph runs **entirely as pods** — the right
fit for immutable Talos (no host packages) — and gives **all three storage shapes
from one system**, which is the decisive advantage over a block-only backend.
Replication is **≥3 replicas** (or an EC profile) for the ML-state pools (R5).

**Hard Talos prerequisite (call-out, not optional):** the storage and any
RBD-consuming nodes' Talos `MachineConfig` **must** declare the **`rbd`** and
**`ceph`** kernel modules under `machine.kernel.modules`, plus the Rook **kubelet
extra-mounts**, **network sysctls**, and **raised open-file limits**. This is set
in the [`talos-machineconfig`](0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
module (the same place the NVIDIA driver extension lives,
[ADR-0050](0050-talos-gpu-driver-system-extensions.md)), **before** this module is
applied. **Get this wrong and `csi-rbdplugin` crash-loops and no RBD PVC mounts** —
it is the highest-risk integration point of WS-A storage and is tracked as such
(R5).

### D2 — Postgres on replicated Ceph RBD via CloudNativePG (honour the fiction)

MLflow's and the tenant-metadata Postgres run on **CloudNativePG** (already named
in `06-uk-datacenters.md`) with PVCs on the **Ceph RBD** `StorageClass`, and
**streaming replication to the standby DC** (the doc's `synchronous_commit=remote_write`
for critical schemas). Ceph RBD's own replication protects the data *within* a DC;
CloudNativePG streaming protects it *across* DCs — the two layers compose, matching
the existing replication design in `uk-dc-failover.md`.

### D3 — S3 artifact store: MinIO default (honour fiction), Ceph-RGW as the consolidating alternative

The **`baremetal-ml-artifact-store`** module (WS-B; the bare-metal analogue of the
GCS-backed `ml-artifact-store`) provisions an **S3 bucket + a scoped S3 credential
(via Vault/ESO, not a cloud IAM principal)** on an **S3-compatible endpoint**. The
endpoint is, by default, **MinIO** — because `06-uk-datacenters.md` already
commits to MinIO pools **and** to **MinIO site-replication** for cross-DC artifact
DR (a proven path the doc relies on). **Ceph-RGW** (from D1) is the **consolidating
alternative**: if we prefer one fewer object system, point the artifact store at
RGW and drop MinIO — a clean sub-decision because both speak S3 and MLflow + the GH
Actions are **endpoint-agnostic**. **External S3 (AWS) is rejected** for
UK-resident training data (residency). This open MinIO-vs-RGW call is listed in the
plan's OPEN DECISIONS and resolved here as **MinIO-by-default, RGW-if-consolidating**.

### D4 — Optional Mayastor fast-block tier for latency-sensitive DBs

Where a workload needs **lowest-latency block** (e.g. QuestDB's hot path, or a
latency-critical Postgres), an **optional Mayastor/OpenEBS (NVMe-oF)** `StorageClass`
is available as a **fast tier alongside Ceph** — not instead of it. Ceph remains
the default (it provides FS + object that Mayastor cannot); Mayastor is a targeted
performance escape hatch, gated behind a measured need.

### D5 — Reject local-path; reaffirm ADR-0028 + cross-DC replication

- **local-path is rejected** for any stateful ML data: no replication, node-pinned,
  data lost if the node is re-imaged (which, on Talos, is the **normal** lifecycle
  per [ADR-0054](0054-baremetal-elasticity-node-lifecycle.md)). It is acceptable
  only for genuinely ephemeral scratch.
- **[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) labels** on
  every storage resource; the per-tenant KMS keys (Vault for UK-resident data, per
  `06-uk-datacenters.md`) encrypt at rest. **Cross-DC DR** = Ceph/MinIO
  site-replication (object) + CloudNativePG streaming (relational) + the existing
  `uk-dc-failover.md` procedure — **no new DR machinery**.

A reviewer checks conformance by confirming: (a) the `talos-machineconfig` for
storage/RBD-consuming nodes declares the **`rbd`** + **`ceph`** kernel modules
(+ Rook kubelet extra-mounts / sysctls / open-file limits) **and an RBD PVC
actually mounts on a Talos node**; (b) `baremetal-rook-ceph` provides RBD + CephFS
+ RGW `StorageClass`es/endpoint; (c) ML-state pools are ≥3-replica; (d) Postgres
runs on CloudNativePG over Ceph RBD with cross-DC streaming; (e) the artifact store
points at MinIO (or RGW), **never external S3**, with a Vault/ESO S3 credential;
(f) local-path is used only for ephemeral scratch; (g) every resource carries
ADR-0028 labels + at-rest encryption.

## Alternatives considered

### A1 — Mayastor/OpenEBS as the primary storage backend
Use Mayastor (NVMe-oF) for all persistent storage.
*Rejected as the primary because:* Mayastor is **block-only** — it provides no
shared filesystem and **no S3 object store**, both of which the ML layer needs
(MLflow artifacts, Iceberg, CephFS workflows). Choosing it would still require a
*separate* object system and a separate FS, defeating the "one substrate" benefit.
**Kept as an optional fast-block tier** (D4) where its NVMe-oF latency wins.

### A2 — local-path / hostPath storage
Use the local-path provisioner on node-local NVMe.
*Rejected because:* **no replication**, node-pinned, and **data is destroyed on
node re-image** — which is the *normal* node lifecycle on immutable Talos
([ADR-0054](0054-baremetal-elasticity-node-lifecycle.md)). Unacceptable for any
stateful ML data (R5); fine only for ephemeral scratch.

### A3 — External S3 (AWS) for the artifact store
Point MLflow's artifact store at an AWS S3 bucket.
*Rejected because:* it puts **UK-resident training data off-prem**, violating the
data-residency premise of `06-uk-datacenters.md` (Vault KMS for UK-resident data,
all training in-DC). Cross-cloud egress + latency are secondary objections. In-DC
MinIO/RGW is required.

### A4 — Hand-rolled Ceph on the host (not Rook)
Install and operate Ceph directly on the node OS.
*Rejected because:* Talos is **immutable** — no host package install, no host
daemons to manage. **Rook** runs Ceph as pods/CRDs, which is the only sane fit for
the OS model and gives a Kubernetes-native operator lifecycle.

### A5 — Keep MinIO as the *only* storage (object only), no block CSI
Use only the already-specified MinIO and avoid a block/FS CSI.
*Rejected because:* MinIO is object-only; Postgres/Qdrant/QuestDB need **block**,
and some workflows need a **shared FS**. A block/FS CSI is non-negotiable; Rook-Ceph
provides it (and can subsume MinIO via RGW if we consolidate, D3).

## Consequences

### Positive
- **One substrate, three shapes:** Rook-Ceph gives block + FS + S3 from a single
  Kubernetes-native, pod-based system — ideal for immutable Talos and the
  three-shape ML need.
- **Honours the fiction:** MinIO (+ its site-replication) stays the artifact-store
  default per `06-uk-datacenters.md`; CloudNativePG-on-Ceph matches the documented
  Postgres replication; cross-DC DR reuses `uk-dc-failover.md` with no new
  machinery.
- **UK data-residency preserved:** training artifacts live in-DC (MinIO or RGW),
  encrypted with the per-tenant Vault KMS keys.
- **Resilience:** ≥3-replica Ceph pools + CloudNativePG streaming + object
  site-replication remove the single-copy SPOF (R5).
- **WS-B is a near-drop-in:** MLflow + the GH Actions are endpoint-agnostic, so
  re-pointing the artifact store at MinIO/RGW is config, not redesign.

### Negative
- **Talos kernel-module coupling (the sharp edge):** Ceph RBD on Talos **will not
  mount** until `rbd` + `ceph` are in `machine.kernel.modules` and the Rook kubelet
  extra-mounts / sysctls / open-file limits are set — a `talos-machineconfig`
  prerequisite that is invisible from the Rook chart alone. Omitting it yields a
  crash-looping `csi-rbdplugin` and stuck PVCs; the conformance check + the
  "RBD PVC mounts on a Talos node" acceptance gate exist to catch it.
- **Ceph is operationally heavy:** Rook-Ceph is a substantial system to run (OSDs,
  MONs, MGRs, placement groups, rebalancing) — real day-2 surface the managed cloud
  hid. WS-D adds Ceph-health panels; WS-E folds Ceph backup into the DR drill.
- **Two object stores if we keep both MinIO and RGW:** unless we consolidate (D3),
  MinIO + Ceph-RGW both exist — the consolidation sub-decision exists precisely to
  avoid that.
- **Storage-capacity is fixed iron** (like compute, R1): growing the Ceph cluster
  means adding/-reimaging storage chassis, not clicking a console.

### Risks
- **R5 — storage SPOF for ML state + artifacts (highest for this ADR).**
  *Mitigations:* ≥3-replica Ceph pools (or EC); MinIO/RGW **site-replication** to
  the standby DC; CloudNativePG **streaming** for relational; the DR drill exercises
  restore (`uk-dc-failover.md`).
- **Ceph RBD does not mount on Talos without the `rbd`/`ceph` kernel modules.**
  *Mitigation:* declare them (+ Rook kubelet-mounts/sysctls/open-file limits) in
  `talos-machineconfig` **before** applying this module; the "RBD PVC mounts on a
  Talos node" acceptance gate + the conformance check (a) block a deploy that
  forgot them.
- **Ceph mis-sizing / rebalancing storms** under load. *Mitigation:* size PGs and
  pools per the `storage-pools` Ansible role assumptions; Ceph-health alerting in
  WS-D; capacity headroom reserved.
- **Bootstrap ordering:** storage must exist before stateful ML — WS-A sequences
  `baremetal-rook-ceph` after the CNI and before the GPU/ML stack (plan §5).

## Implementation notes

This ADR is **planning-only**: the PR introducing it creates **no** Ceph cluster,
**no** buckets, and applies **nothing to hardware**. Implementation is
**apply-gated**.

**Conventions to match:** Terraform `~> 1.11`; the Helm-release/CRD shape mirrors
how `apps/infra/*` ArgoCD apps deploy operators; the artifact-store module mirrors
the **input/output contract** of the GCS-backed `ml-artifact-store` but swaps the
GCS bucket + GSA for an **S3 bucket + Vault/ESO credential**. Carry the five
ADR-0028 `platform_*` labels on every resource.

### Module interface contracts (for the parallel module build)
**`baremetal-rook-ceph`** — Rook operator + Ceph (block/FS/RGW).
- Inputs: `cluster_endpoint`/`kubeconfig` (from `talos-cluster`),
  `rook_chart_version`, `ceph_version`, `storage_nodes` (list — the storage-chassis
  machines), `block_pool_replicas` (default `3`), `enable_cephfs` (bool, default
  `true`), `enable_rgw` (bool, default `true`), `rgw_instances`, `namespace`
  (default `rook-ceph`), `labels` (map(string), ADR-0028).
- Outputs: `rbd_storage_class`, `cephfs_storage_class`, `rgw_s3_endpoint`,
  `rgw_object_store_name`.
- **MachineConfig dependency (HARD):** requires the `talos-machineconfig` for
  storage/RBD-consuming nodes to set `machine.kernel.modules: [rbd, ceph]` + the
  Rook kubelet extra-mounts / `machine.sysctls` / open-file limits. This module
  **does not and cannot** load host kernel modules itself (immutable OS); it should
  fail its `*.tftest.hcl`/validate if the wired machine config lacks `rbd`.

**`baremetal-ml-artifact-store`** (WS-B) — S3 bucket + scoped credential on
MinIO/RGW (bare-metal analogue of `ml-artifact-store`).
- Inputs: `s3_endpoint` (MinIO or `rgw_s3_endpoint` from `baremetal-rook-ceph`),
  `bucket_name`, `credential_secret_ref` (Vault/ESO path — **no** cloud IAM),
  `enable_site_replication` (bool — MinIO cross-DC DR), `labels` (ADR-0028;
  `platform_system = ml-pipeline`, `platform_component = model-registry`).
- Outputs: `bucket_name`, `s3_endpoint`, `credential_secret_ref`.

- Effort: **L** (Rook-Ceph cluster + StorageClasses + RGW + the artifact-store
  module + CloudNativePG wiring + cross-DC replication validation).
- Rollback: each module is independently revertible; until storage is proven, the
  cloud ML estate (GCS-backed) remains authoritative; nothing is applied to
  hardware.

## Revisit trigger

Re-open this decision if any of the following hold:
- **Ceph operational cost outweighs the one-substrate benefit** — split into
  MinIO (object) + Mayastor (block) + a managed FS, accepting multiple systems.
- **A workload's block latency is unmet by Ceph RBD** — promote **Mayastor** (D4)
  for that class as a measured decision.
- **The MinIO-vs-RGW consolidation is decided** — collapse to one object system
  (D3) and update the artifact-store endpoint.
- **A data-residency exception is granted** — re-evaluate A3 (external S3) for the
  non-resident subset only.

## References

- Rook-Ceph (operator, `CephCluster`/`CephBlockPool`/`CephFilesystem`/
  `CephObjectStore` RGW S3): <https://rook.io/docs/rook/latest/Getting-Started/intro/>
- Ceph RGW S3 API: <https://docs.ceph.com/en/latest/radosgw/s3/>
- Mayastor / OpenEBS (NVMe-oF block): <https://openebs.io/docs/>
- CloudNativePG (Postgres operator, streaming replication):
  <https://cloudnative-pg.io/documentation/current/>
- MinIO site replication (cross-DC object DR):
  <https://min.io/docs/minio/linux/operations/install-deploy-manage/multi-site-replication.html>
- MLflow artifact stores (S3-compatible, endpoint-agnostic):
  <https://mlflow.org/docs/latest/tracking/artifacts-stores.html>
- In-repo (HONORED): `docs/transaction-analytics/06-uk-datacenters.md` (MinIO pools
  + site-replication, CloudNativePG, tiered NVMe, `storage-pools` role),
  `docs/runbooks/uk-dc-failover.md` (replication + DR drill).
- In-repo reference (artifact-store contract): `catalog/units/ml-artifact-store`,
  `terraform/modules/ml-artifact-store`.
- Related ADRs: [ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
  (foundation — immutable OS forces pod-based storage),
  [ADR-0037](0037-ml-cicd-pipeline-mlflow.md) (the GCS artifact store this replaces),
  [ADR-0054](0054-baremetal-elasticity-node-lifecycle.md) (node re-image is why
  local-path is unsafe), [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md).

---
*Planning-only ADR — proposed, not implemented; nothing applied to hardware
(mock/emulation repo). Bare-metal substitute for the GCS artifact store + cloud
block storage. WS-A/WS-B; implementation apply-gated. Drafted 2026-06-15.*
