# gke-gpu-dranet

GKE managed **DRANET** RoCE/RDMA fabric for H200 / B200 via Dynamic Resource Allocation
(ADR-0042 D3).

Ships the DRA `netdev` objects that bind GPUDirect-RDMA (RoCE, 3.2 Tbps over CX-7) NICs
to pods on `a3-ultragpu-8g` (H200) and `a4-highgpu-8g` (B200) pools:

- a **DeviceClass** (`roce-netdev`) selecting DRANET-managed RDMA NICs (driver `dra.net`);
- a **ResourceClaimTemplate** (`rdma-all-nics`) requesting **all** RDMA NICs on the node.

This is the same DRA model the estate already uses for GPU **compute** (ADR-0036 /
`gpu-inference-dra`), extended to the network — so Volcano (DRA plugin) schedules GPU +
NIC as one unit. A pod references both the GPU-compute claim and this RDMA claim.

## Prerequisites (not created here)

- **GKE managed DRANET enabled** on the cluster — requires GKE **>= 1.35.2-gke.1842000**.
  DRANET GA covers A3 Ultra / A4 / A4X (and TPU v6e/v7x); it does **not** cover A3
  High/Mega (use `gke-gpu-fabric` / GPUDirect-TCPX·TCPXO there).
- A **RoCE VPC** (`gcp-gpu-vpc` `enable_rdma_network = true`) attached to the pools.

## Usage

```hcl
module "gpu_dranet" {
  source = "../../modules/gke-gpu-dranet"

  namespace       = "gpu-inference"
  platform_labels = { "platform.env" = "staging", "platform.owner" = "team-ml-infra" }
}
```

## Testing

`terraform test` mocks the kubernetes provider — no cluster needed (same pattern as
`gpu-inference-dra`). Note that against a **real** cluster, `kubernetes_manifest` requires
the DRA CRDs to exist at plan time.

## References

- ADR-0042 §D3 — DRANET/RoCE for H200/B200.
- GKE managed DRANET: <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/allocate-network-resources-dra>
- <https://github.com/kubernetes-sigs/dranet>
