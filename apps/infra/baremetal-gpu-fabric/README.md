# baremetal-gpu-fabric (ArgoCD app)

GitOps **SR-IOV / DRA custom resources** for the bare-metal GPU fabric (RoCEv2 / InfiniBand
GPUDirect RDMA). Part of **WS-A**. System: `ml-infra`.

**ADR:** [ADR-0053](../../../docs/adrs/0053-baremetal-gpu-fabric-roce-infiniband.md).
ADR-0028 labels.

## Split of responsibility

| Layer | Owns |
|-------|------|
| `terraform/modules/baremetal-gpu-fabric` | SR-IOV operator install (Helm) |
| **this app** | `SriovNetworkNodePolicy` / `SriovNetwork` (day-0) + the gated DRANET `DeviceClass` / `ResourceClaimTemplate` |

## Two-stage gate (ADR-0053 D3)

- **Day-0 primary:** SR-IOV / RDMA device plugin (`sriov.enabled`).
- **Gated target:** Cilium `netdev` DRA / DRANET (`dranet.enabled`, default **false**) — flip
  only once DRA-`netdev` is GA on our Talos/k8s, a `dranet` release is validated, and it meets
  the SR-IOV NCCL baseline.

`fabricMode` defaults **infiniband**; MTU 9000. An **NCCL all-reduce bandwidth test** is the
acceptance gate (`nccl-troubleshooting.md`).

## Apply-gated / default-OFF

`enabled: false` — ArgoCD does not sync until a human enables the app. Nothing is applied to
real hardware in this repo.

## ADR-0028 labeling

`platform.system = ml-infra`, `platform.component = gpu-fabric`, `platform.managed-by = argocd`.
