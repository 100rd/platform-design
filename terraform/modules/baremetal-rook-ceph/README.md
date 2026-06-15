# baremetal-rook-ceph

**Rook-Ceph storage** — replicated block (RBD) + shared FS + **RGW S3 object** — for the
Talos GPU cluster. Part of **WS-A** of the Bare-Metal ML Platform. System: `ml-infra`.

**ADRs:** [ADR-0052](../../../docs/adrs/0052-baremetal-storage-rook-ceph.md)
(Rook-Ceph vs Mayastor; + S3-compatible artifact store). ADR-0028 labels.

## The load-bearing rbd+ceph contract (ADR-0052)

RBD PVCs **will not mount** until `talos-machineconfig` declares the **`rbd`** + **`ceph`**
kernel modules (+ the Rook kubelet extra-mount for `/var/lib/rook`). Without them
`csi-rbdplugin` crash-loops. This module **enforces** that contract: `var.ceph_kernel_modules`
is wired from the `talos-machineconfig` output through the stack `dependency`, and a
`validation` block **fails the plan** if `rbd` or `ceph` is missing — so the dependency is
checked in code, not just documented. `data_dir_host_path` must match the machineconfig
kubelet extraMount.

Self-contained as **pods** (operator + CSI), because immutable Talos has no host packages.

## What it creates (when `enabled = true`)

| Resource | Purpose |
|----------|---------|
| `kubernetes_namespace.rook_ceph` | Namespace, ADR-0028 labels |
| `helm_release.rook_ceph_operator` | Rook operator + CSI (RBD + CephFS drivers) |
| `kubernetes_manifest.ceph_cluster` | `CephCluster` (≥3 mons, replicated) |
| `kubernetes_manifest.ceph_block_pool` | `CephBlockPool` — RBD PVCs (Postgres/MLflow) |
| `kubernetes_manifest.ceph_filesystem` | (gated) `CephFilesystem` — shared RWX datasets |
| `kubernetes_manifest.ceph_object_store` | (gated) `CephObjectStore` — **RGW S3** artifact backend |

## S3 for WS-B

When `enable_object_store = true` (default), the module surfaces an in-cluster `s3_endpoint`
output — the **S3-compatible artifact-store backend** WS-B's `baremetal-ml-artifact-store`
re-points MLflow at (ADR-0052), keeping training data UK-resident (no external S3).

## Durability

`block_pool_replicas` is **`validation`-floored at 3** (survive a node loss; risk R5).
`mon_count` is validated odd (quorum).

## Apply-gated

`var.enabled` defaults **false**. Providers mocked at plan time — no live cluster, no Helm
install. No `terraform apply` in this repo.

## ADR-0028 labeling

Dotted keys: `platform.system = ml-infra`, `platform.component = storage`,
`platform.managed-by = terragrunt`, plus `platform_labels` overrides.

## Testing

```bash
terraform init -backend=false
terraform test
```

Tests assert the Ceph CRs, the S3 endpoint, and that a **missing `rbd` module fails the
plan** (the ADR-0052 gate).
