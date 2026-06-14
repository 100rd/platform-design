# ADR-0050: Talos GPU driver delivery via system extensions (vs host install)

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — no Talos image, no system-extension
  manifest, and no `baremetal-gpu-operator` module exist; the cloud GPU-driver
  modules in-repo (`gpu-operator`, `gke-gpu-operator`) assume a mutable host
  (AMI-prebaked or GKE/Operator-installed driver) — a path that **cannot exist on
  Talos**, which has no package manager and no writable host filesystem.
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: WS-A "Bare-metal GPU cluster foundation & elasticity" + WS-E
  "Security posture" (Bare-Metal ML Platform plan,
  `docs/baremetal-ml-platform/IMPLEMENTATION_PLAN.md`); risk-register R2 (Talos ↔
  extension ↔ driver ↔ NCCL skew). Bare-metal counterpart of
  [ADR-0036](0036-gke-ml-infra-parity-multiregion.md) D1 (GPU Operator vs managed
  driver).
- Supersedes: (none)
- Superseded by: (none)

## Context

[ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md) commits the GPU
nodes to **Talos Linux** — an **immutable** OS with **no shell, no SSH, and no
package manager**. That single fact rewrites the GPU-driver story, because every
GPU-driver path the repo currently uses assumes a **mutable host**:

- The EKS `gpu-operator` module runs on Bottlerocket where the **AMI pre-bakes**
  the driver (`gpu-operator` sets the driver toggle accordingly).
- The GKE path ([ADR-0036](0036-gke-ml-infra-parity-multiregion.md) D1) either
  uses the **GKE-managed driver** or the **GPU-Operator driver container**, both
  of which mutate a writable node OS.

On Talos there is **no `apt install nvidia-driver`, no DKMS, no writable
`/usr`** — you cannot install a kernel module onto a running Talos host the way
you would on Ubuntu/Bottlerocket. The kernel module must be **part of the
immutable image**. Talos solves this with **system extensions**: signed,
image-baked components (the NVIDIA stack ships as the
**`nonfree-kmod-nvidia-production`** kernel-module extension +
**`nvidia-container-toolkit-production`**) that are composed into the boot image
via the **Talos Image Factory** (or `imager`) and selected by the machine config's
install/schematic surface. A driver change is therefore an **image change + A/B
reboot**, not a host mutation — atomic, auditable, and rollback-safe.

This is the **direct bare-metal analogue of ADR-0036 D1's question** ("GPU
Operator vs the cloud-managed driver"), but the immutable constraint makes the
answer sharper: on Talos the **only** viable in-image driver is a system
extension, and the GPU Operator must therefore run **driver-less**
(`driver.enabled=false`) — the inverse of the EKS default and a deliberate
configuration of the new `baremetal-gpu-operator` module.

The `ai-sre/knowledge/gpu-driver-updates.md` post-update checklist (DCGM reports
all GPUs, NCCL benchmark, vLLM latency, operator pods restarted, new XID errors in
dmesg) is the **operational gate** this ADR plugs into — but the *delivery
mechanism* it assumes ("reboot node if needed", "rebuild containers") must be
reframed for the image-based, A/B model.

## Decision

Deliver the NVIDIA GPU driver to Talos GPU nodes as **image-baked Talos system
extensions**, and run the **GPU Operator driver-less** on top. Four
plan/validate-only sub-decisions; nothing applies without the gate; nothing is
applied to hardware.

### D1 — Driver = `nonfree-kmod-nvidia` + `nvidia-container-toolkit` Talos system extensions, baked into the image

The Talos boot image for the **GPU-worker machine class** is built (via the Talos
Image Factory schematic, pinned by digest) to include the
**`siderolabs/nonfree-kmod-nvidia-production`** kernel-module extension and the
**`siderolabs/nvidia-container-toolkit-production`** extension. The
**`talos-machineconfig`** module
([ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md)) carries the
extension/schematic reference as an input (`system_extensions` list +
`talos_image_schematic_id`), and sets the documented prerequisites
(`machine.kernel.modules` for `nvidia`/`nvidia_uvm`/`nvidia_drm`/`nvidia_modeset`,
the required sysctls, and the `nvidia` container-runtime-class wiring). The
control-plane machine class carries **no** GPU extension.

### D2 — GPU Operator runs driver-less (`driver.enabled=false`)

The new **`baremetal-gpu-operator`** module installs the NVIDIA GPU Operator with
**`driver.enabled=false`** and **`toolkit.enabled=false`** (both supplied by the
Talos extensions), running only **GPU Feature Discovery, Node Feature Discovery,
the device plugin, CDI, and the NVIDIA DRA driver** — exactly the same role split
as the cloud modules, but with the driver/toolkit responsibility moved from the
host/AMI to the Talos image. `dcgmExporter.enabled=false` (DCGM owned by
`baremetal-gpu-dcgm`, same as ADR-0036 D1/D3). This is the inverse default of the
EKS `gpu-operator` (Bottlerocket AMI) and the GKE Operator path — and the
**conformance check** is precisely that `driver.enabled=false` on this module.

### D3 — Driver upgrades are image + A/B reboot, gated by the existing checklist

A driver bump is a **new Talos image schematic** (new extension version) →
`talos-machineconfig` reference update → **Talos upgrade (A/B partition + reboot,
auto-rollback on boot failure)**, **staged on the standby DC first**
([ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md) D5). The
**`ai-sre/knowledge/gpu-driver-updates.md` checklist is the acceptance gate**
(DCGM all-GPU report, NCCL benchmark per `nccl-troubleshooting.md`, vLLM latency
non-regression, operator pods clean, no new XID), reframed for the image model:
"reboot node if needed" becomes "the A/B upgrade already rebooted; if the new
image fails to boot, Talos auto-rolls-back to the previous partition" — a
*stronger* guarantee than the mutable-host checklist assumed.

### D4 — Driver/toolkit version is pinned to the Talos release; coupled-upgrade cost accepted

Pin the **system-extension version to the Talos release** (Image Factory
schematics are version-coupled to the Talos version), accepting that a driver bump
and a Talos bump travel together. This trades **faster independent driver bumps**
(which the Operator-driver-container path would allow) for **a single, atomic,
rollback-safe image** and a smaller moving-part count — the right trade for an
estate whose headline risk (R2) is exactly version skew across Talos ↔ extension ↔
driver ↔ NCCL. The Operator-driver-container alternative is recorded below as the
revisit trigger if driver-cadence pressure outweighs the coupling cost.

A reviewer checks conformance by confirming: (a) the GPU-worker image schematic
includes `nonfree-kmod-nvidia-production` + `nvidia-container-toolkit-production`,
pinned; (b) `talos-machineconfig` sets the kernel modules + runtime-class wiring
and carries the schematic reference; (c) `baremetal-gpu-operator` sets
`driver.enabled=false` **and** `toolkit.enabled=false`; (d) control-plane nodes
carry no GPU extension; (e) the upgrade runbook stages on standby and runs the
`gpu-driver-updates.md` checklist as a gate.

## Alternatives considered

### A1 — Mutable host driver install (`apt`/DKMS on the node)
Install the NVIDIA driver onto the running node OS, as on Ubuntu/Bottlerocket.
*Rejected because:* it is **impossible on Talos** — no package manager, no shell,
no writable `/usr`. This isn't a preference; the immutable OS
([ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md) D1) structurally
forecloses it. (It is the implicit model of the `hetzner-nodes` kubeadm path,
which is reference-only and not reused.)

### A2 — GPU-Operator-managed driver container (`driver.enabled=true`)
Let the GPU Operator deploy the driver as a container/DaemonSet that loads the
module at runtime (the GKE-style path).
*Rejected as the default because:* on Talos the Operator driver container would
have to load a kernel module into an immutable, locked-down kernel at runtime —
fighting the OS model, requiring extra privileges, and re-introducing a mutable,
non-atomic driver surface that A/B image upgrades were chosen to avoid. The
system-extension path is **Sidero's documented, supported** Talos GPU mechanism.
**Kept as the revisit trigger** if independent driver cadence becomes a hard
requirement (it would decouple driver bumps from Talos bumps at the cost of D4's
atomicity).

### A3 — Prebake the driver into a custom node image outside the extension system
Build a bespoke Talos image with the driver compiled in by hand (not via the
Image Factory extension).
*Rejected because:* it re-implements what the **Image Factory system extension**
already provides (signed, versioned, supported), forfeits the upstream
build/signing pipeline, and increases our maintenance surface for no benefit — the
extension *is* the supported "driver baked into the image" path.

### A4 — Status quo (reuse a cloud GPU-driver module unchanged)
Point `gpu-operator` / `gke-gpu-operator` at the bare-metal cluster as-is.
*Rejected because:* both assume a mutable host driver (AMI-prebaked or
Operator/GKE-installed) that **cannot exist on Talos**; running them unchanged
yields GPU nodes with **no working driver**. The driver-less `baremetal-gpu-operator`
+ system-extension split (D1/D2) is the minimal correct adaptation.

## Consequences

### Positive
- **Atomic, rollback-safe driver lifecycle:** a driver change is an image + A/B
  reboot with auto-rollback on boot failure — no half-applied driver, no DKMS
  drift, no "works on node 3 but not node 7."
- **Security posture preserved:** the driver lives in the signed, immutable image;
  no runtime kernel-module loading, no extra host privileges, no writable OS —
  a WS-E SOC asset that the mutable-host paths cannot claim.
- **One operating model with the cloud estate, minus the host:** GFD/NFD/CDI/
  device-plugin/DRA-driver via the Operator are identical to EKS/GKE; only the
  driver source moves (host/AMI → Talos image), so runbooks/dashboards transfer.
- **Auditability:** the exact driver version is the image schematic digest in Git —
  fully traceable.

### Negative
- **Coupled Talos+driver upgrades (D4):** bumping the driver means bumping the
  Talos image (and rebooting); you cannot hot-swap just the driver. This is the
  deliberate trade for atomicity (revisit trigger A2 if it bites).
- **Image-build step in the pipeline:** building/pinning the Image Factory
  schematic is a new CI artifact the cloud path didn't need.
- **Inverse-default footgun:** `baremetal-gpu-operator` must set
  `driver.enabled=false` (opposite of intuition coming from GKE's
  `driver.enabled=true`); getting it wrong yields a **double-driver** conflict (image
  extension + Operator container both trying to own the module) or **no driver** —
  this is the single sharpest integration point (mirrors ADR-0036 D1's node-pool
  coupling call-out).

### Risks
- **R2 — Talos release ↔ extension ↔ NVIDIA driver ↔ NCCL skew (highest for this
  ADR).** A bad image bricks GPU nodes cluster-wide. *Mitigations:* pin the
  schematic per DC; **A/B auto-rollback** on boot failure; **stage on standby DC
  first**; the `gpu-driver-updates.md` checklist + an NCCL all-reduce bandwidth
  test as hard gates before promoting to primary.
- **Double-driver / no-driver misconfig** (the inverse-default footgun) —
  *Mitigation:* the conformance check `driver.enabled=false && toolkit.enabled=false`
  is asserted in the module's `*.tftest.hcl` (impl phase) and in code review.

## Implementation notes

This ADR is **planning-only**: the PR introducing it builds **no** Talos image,
creates **no** `baremetal-gpu-operator` module, and applies **nothing to hardware**.
Implementation is **apply-gated**.

**Conventions to match:** Terraform `~> 1.11`; `siderolabs/talos` provider for the
machine config; Helm-release/namespace/toleration shape mirrors the EKS/GKE
`gpu-operator` modules so the only diff is the driver/toolkit toggles. Carry the
five ADR-0028 `platform_*` labels on every resource and `platform.*` on the
Operator workloads.

### Module interface contract (for the parallel module build)
**`baremetal-gpu-operator`** — NVIDIA GPU Operator, driver-less, on Talos.
- Inputs: `cluster_endpoint`/`kubeconfig` (from `talos-cluster`),
  `chart_version` (NVIDIA GPU Operator), `dra_driver_version`,
  `driver_enabled = false` (**fixed**; driver from the Talos extension),
  `toolkit_enabled = false` (**fixed**; toolkit from the Talos extension),
  `dcgm_exporter_enabled = false` (DCGM owned by `baremetal-gpu-dcgm`),
  `gpu_node_selector` (default `{ "nvidia.com/gpu.present" = "true" }`),
  `namespace` (default `gpu-operator`), `labels` (map(string), ADR-0028).
- Outputs: `gpu_operator_namespace`, `gpu_operator_version`, `dra_enabled`.
- **Extension coupling:** the GPU-worker `talos-machineconfig` MUST carry the
  `nonfree-kmod-nvidia-production` + `nvidia-container-toolkit-production`
  schematic and the `nvidia*` kernel modules; this module asserts driver/toolkit
  **disabled** so the Operator never fights the image-baked driver.

- Effort: **M** (one driver-less Operator module + an Image Factory schematic
  pin + the upgrade runbook reframe).
- Rollback: revert the module / image schematic; Talos A/B auto-rollback covers a
  failed boot; the cloud GPU estate stays authoritative.

## Revisit trigger

Re-open this decision if any of the following hold:
- **Driver cadence pressure** (a security/perf driver fix needed faster than the
  Talos release cycle allows) outweighs D4's atomicity — move to the
  **Operator-driver-container** path (A2), decoupling driver from Talos at the cost
  of runtime module loading.
- **Talos changes the extension model** (e.g. out-of-image driver injection becomes
  supported) — re-evaluate D1.
- **NVIDIA stops shipping the `nonfree-kmod-nvidia` extension** for our GPU/kernel
  combo — re-evaluate the in-image driver source.

## References

- Talos system extensions (concept, Image Factory, install/schematic surface):
  <https://www.talos.dev/latest/talos-guides/configuration/system-extensions/>,
  <https://www.talos.dev/latest/learn-more/image-factory/>
- NVIDIA on Talos (production `nonfree-kmod-nvidia` + `nvidia-container-toolkit`
  extensions, kernel modules, runtime class):
  <https://www.talos.dev/latest/talos-guides/configuration/nvidia-gpu-proprietary/>
- `siderolabs/extensions` (the extension catalogue):
  <https://github.com/siderolabs/extensions>
- NVIDIA GPU Operator driver-less / `driver.enabled=false` (prebaked driver):
  <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html>
- In-repo (HONORED gate): `ai-sre/knowledge/gpu-driver-updates.md`,
  `ai-sre/knowledge/nccl-troubleshooting.md`.
- In-repo cloud references (driver-toggle shape): `terraform/modules/gpu-operator`,
  `terraform/modules/gke-gpu-operator`.
- Related ADRs: [ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
  (foundation — Talos immutability is the premise),
  [ADR-0036](0036-gke-ml-infra-parity-multiregion.md) D1 (the cloud GPU-driver
  decision this mirrors), [ADR-0053](0053-baremetal-gpu-fabric-roce-infiniband.md)
  (the fabric the driver feeds), [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md).

---
*Planning-only ADR — proposed, not implemented; nothing applied to hardware
(mock/emulation repo). Bare-metal counterpart of ADR-0036 D1. WS-A/WS-E;
implementation apply-gated. Drafted 2026-06-15.*
