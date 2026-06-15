# talos-system-extensions

GitOps **source of truth** for the Talos **system-extension catalog + version pins** — the
NVIDIA driver + container toolkit extensions baked into the bare-metal GPU cluster's boot
image. Part of **WS-A**. System: `ml-infra`.

**ADR:** [ADR-0050](../../../docs/adrs/0050-talos-gpu-driver-system-extensions.md) (GPU
driver via Talos system extension). ADR-0028 labels.

## What this is (and isn't)

It is a **pin/doc chart**: it makes the extension image refs and their Talos-release
coupling visible and reviewable in GitOps. It does **not** install anything on a running
host — Talos extensions ship in the boot **image** and are applied by a **re-image**, never
`apt install` (there is no package manager). The Terraform `talos-machineconfig` module
references the same pins; this app keeps the catalog auditable.

## Apply-gated

Changing an extension = a Talos image change + node re-image. That is **apply-gated**,
staged on the **standby DC first**, with A/B-partition auto-rollback and the
`gpu-driver-updates.md` post-update checklist as the gate (risk R2). Nothing here mutates a
host directly.

## Contents

- `nonfree-kmod-nvidia` — NVIDIA kernel driver (GPU workers)
- `nvidia-container-toolkit` — NVIDIA container runtime hooks
- the `rbd`/`ceph` (ADR-0052) + `nvidia*` (ADR-0050) kernel modules the cluster needs

## ADR-0028 labeling

`platform.system = ml-infra`, `platform.component = compute`, `platform.managed-by = argocd`.
