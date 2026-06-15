# talos-machineconfig

Renders **immutable Talos Linux `MachineConfig`** for two machine classes —
**control-plane** and **GPU-worker** — via the `siderolabs/talos` provider. Part of
**WS-A** of the Bare-Metal ML Platform. System: `ml-infra`.

**ADRs:** [ADR-0049](../../../docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
(Talos foundation / multi-DC), [ADR-0050](../../../docs/adrs/0050-talos-gpu-driver-system-extensions.md)
(GPU driver via system extension), [ADR-0052](../../../docs/adrs/0052-baremetal-storage-rook-ceph.md)
(Rook-Ceph `rbd`+`ceph` kernel-module prerequisite). ADR-0028 taxonomy labels on every node.

## Why this module is load-bearing

Talos is **immutable** — no shell, no SSH, no package manager. Anything the OS needs
**must be declared in the `MachineConfig` and baked into the boot image**; it cannot be
installed on a running host. This module is therefore the **single place** three
prerequisites are declared:

| Prerequisite | Declared as | ADR | Failure if omitted |
|--------------|-------------|-----|--------------------|
| **Rook-Ceph RBD** | `machine.kernel.modules` = `rbd` + `ceph` | ADR-0052 | `csi-rbdplugin` crash-loops; **no RBD PVC ever mounts** |
| **NVIDIA driver** | `install.extensions` (system extension) + `nvidia*` kernel modules | ADR-0050 | no GPU; `nvidia-smi` fails; GPU Operator has nothing to bind |
| **Rook kubelet state** | `kubelet.extraMounts` (`/var/lib/rook`) + sysctls | ADR-0052 | Ceph OSDs cannot persist state on the immutable host |

A `validation` block on `ceph_kernel_modules` **fails the plan** if `rbd` or `ceph` is
dropped — the ADR-0052 gate is enforced in code.

This module is the **explicit replacement** for the kubeadm `hetzner-kubeadm.sh` host
bootstrap script (which the plan does *not* reuse): there is **no host bootstrap**, only
declarative config applied over the mTLS machine API.

## What it creates (when `enabled = true`)

| Resource / data source | Purpose |
|------------------------|---------|
| `talos_machine_secrets.this` | Cluster PKI / secret bundle (sensitive; from a secret manager in real use) |
| `data.talos_machine_configuration.controlplane` | Control-plane config — etcd/API, KubePrism, `rbd`+`ceph` modules |
| `data.talos_machine_configuration.gpu_worker` | GPU-worker config — NVIDIA extension, `rbd`+`ceph`+`nvidia*` modules, Rook mounts/sysctls |
| `data.talos_client_configuration.this` | `talosctl` mTLS client config — the **only** access path (no SSH) |

## Apply-gated / default-OFF

`var.enabled` defaults to **false** so the WS-A stack provisions nothing until a human
explicitly enables it behind a reviewed plan. `talos_machine_secrets` is the only
*resource* (everything else is a data source); nothing is ever applied to a machine here
(`talos_machine_configuration_apply` / `talos_machine_bootstrap` live in `talos-cluster`
and stay apply-gated). **No `terraform apply`, no `talosctl apply-config` in this repo.**

## ADR-0028 labeling

Talos/Kubernetes-plane labels use **dotted** keys. Every node carries
`platform.system = ml-infra`, `platform.component = compute`,
`platform.managed-by = terragrunt`, merged with any `platform_labels` overrides
(`platform.env`, `platform.owner`). GPU workers additionally advertise
`nvidia.com/gpu.present = true`.

## Usage

```hcl
module "talos_machineconfig" {
  source = "../../terraform/modules/talos-machineconfig"

  enabled          = true
  cluster_name     = "uk-primary"
  cluster_endpoint = "https://10.10.0.10:6443"

  control_plane_endpoints = ["10.10.0.10", "10.10.0.11", "10.10.0.12"]

  platform_labels = {
    "platform.env"   = "production"
    "platform.owner" = "team-data"
  }
}
```

## Testing

```bash
terraform init -backend=false
terraform test
```

Tests mock the `talos` provider — no real machine, secrets, or credentials needed. They
assert the **rbd+ceph** prerequisite, the NVIDIA extension, ADR-0028 labels, KubePrism,
and the apply-gated default-OFF behaviour.
