# rook-ceph (ArgoCD app)

GitOps **Ceph cluster CRs** — `CephCluster`, `CephBlockPool`, `CephFilesystem`, and the
`CephObjectStore` (RGW S3) — for the bare-metal GPU cluster. Part of **WS-A**. System:
`ml-infra`.

**ADR:** [ADR-0052](../../../docs/adrs/0052-baremetal-storage-rook-ceph.md). ADR-0028 labels.

## Split of responsibility

| Layer | Owns |
|-------|------|
| `terraform/modules/baremetal-rook-ceph` | Operator + CSI install (Helm) |
| **this app** | The `CephCluster` / pool / object-store **CRs** the operator reconciles |

## The rbd+ceph prerequisite (ADR-0052)

RBD PVCs will not mount until the Talos MachineConfig declares the `rbd` + `ceph` kernel
modules (`talos-machineconfig` / `talos-system-extensions`). `dataDirHostPath` must match the
Talos kubelet extraMount. Replication is **≥3** (survive a node loss, risk R5).

## S3 for WS-B

The `CephObjectStore` (RGW) exposes the in-cluster S3 endpoint WS-B's MLflow artifact store
re-points at (UK-resident, no external S3).

## Apply-gated / default-OFF

`enabled: false` — ArgoCD does not sync these CRs until a human enables the app behind a
reviewed plan + blast-radius review. Nothing is applied to real hardware in this repo.

## ADR-0028 labeling

`platform.system = ml-infra`, `platform.component = storage`, `platform.managed-by = argocd`.
