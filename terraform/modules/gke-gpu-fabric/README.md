# gke-gpu-fabric

GPUDirect-**TCPX / TCPXO** fabric for H100 / H100-Mega via the legacy GKE multi-networking
path (ADR-0042 D2).

DRANET GA does **not** cover A3 High/Mega, so H100 GPUDirect must use
`GKENetworkParamSet` + `Network` (Device mode) plus the NCCL plugin installer. (For
H200/B200 RoCE, use `gke-gpu-dranet` instead.)

## What it creates

Per data-plane VPC (4 for TCPX / `a3-highgpu-8g`, 8 for TCPXO / `a3-megagpu-8g`):

- a **GKENetworkParamSet** (`deviceMode: NetDevice`) referencing the VPC + subnet;
- a **Network** (`type: Device`) the pod's additional NIC binds to.

Plus one **NCCL plugin installer DaemonSet** (TCPX or TCPXO image) node-selected onto
`fabric-mode = <mode>` pools (the label set by `gcp-gke-gpu-nodepools`).

## Inputs (load-bearing)

| Input | Purpose |
|-------|---------|
| `mode` | `tcpx` (4 NICs) or `tcpxo` (8 NICs) |
| `data_plane_networks` | List of `{name, network, subnetwork}` — the VPCs from `gcp-gpu-vpc` data-plane outputs |
| `tcpx_installer_image` / `tcpxo_installer_image` | Pinned NCCL plugin images (pin a real tag at apply time) |

## Pairing with the VPC and node pools

```
gcp-gpu-vpc:            data_plane_network_count = 4   (TCPX) / 8 (TCPXO)
gcp-gke-gpu-nodepools:  fabric_mode = "tcpx", additional_node_networks = [...4...]
gke-gpu-fabric:         mode = "tcpx", data_plane_networks = [...4...]
```

## Testing

`terraform test` mocks the kubernetes provider — no cluster needed. Against a real
cluster, `kubernetes_manifest` for the GKE CRDs requires those CRDs to exist at plan time.

## References

- ADR-0042 §D2 — GPUDirect-TCPX/TCPXO for H100.
- <https://cloud.google.com/kubernetes-engine/docs/how-to/gpu-bandwidth-gpudirect-tcpx>
