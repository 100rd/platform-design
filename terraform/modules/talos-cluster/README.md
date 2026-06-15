# talos-cluster

Bootstraps the **self-operated Talos control plane** — etcd init, kubeconfig retrieval,
and the **etcd-snapshot schedule** wiring. Part of **WS-A** of the Bare-Metal ML
Platform. System: `ml-infra`.

**ADRs:** [ADR-0049](../../../docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
(self-operated control plane / multi-DC). ADR-0028 taxonomy labels.

## Why this exists (no managed control plane)

Unlike GKE/EKS, **we own etcd and the API server** (ADR-0049). That means this module —
not a cloud provider — owns the **control-plane VIP / KubePrism** endpoint, the one-time
**etcd bootstrap**, and the **etcd-snapshot cadence** that the control-plane-change gate
depends on (a verified snapshot is taken before every control-plane `MachineConfig`
change or Talos upgrade).

It consumes the secrets + client config produced by `talos-machineconfig` (wired through
a `dependency` block at the stack layer) and emits the cluster **kubeconfig** every
in-cluster WS-A unit (cilium-lb, rook-ceph, gpu-operator, …) depends on.

## Double-gated, apply-gated

| Gate | Default | Effect |
|------|---------|--------|
| `var.enabled` | `false` | module creates nothing |
| `var.bootstrap_control_plane` | `false` | even when enabled, etcd is **not** initialised |

`talos_machine_bootstrap` (which actually `etcd init`s a live node) is created **only when
both gates are true**. The default posture provisions nothing, and **no bootstrap is ever
run in this repo** (mock/emulation, plan-only). No `terraform apply`, no
`talosctl bootstrap`.

## What it creates (when both gates true)

| Resource / data source | Purpose |
|------------------------|---------|
| `talos_machine_bootstrap.this` | One-time etcd init on the first control-plane node |
| `data.talos_cluster_kubeconfig.this` | Cluster kubeconfig for downstream in-cluster units |

## ADR-0028 labeling

Dotted keys: `platform.system = ml-infra`, `platform.component = control-plane`,
`platform.managed-by = terragrunt`, plus `platform_labels` overrides — surfaced via
outputs for downstream control-plane K8s resources.

## Testing

```bash
terraform init -backend=false
terraform test
```

Mocks the `talos` provider — asserts the double-gated bootstrap and the etcd-snapshot
wiring; no live cluster needed.
