# baremetal-gpu-fabric

**High-performance GPU fabric** (GPUDirect RDMA over RoCEv2 / InfiniBand) for the Talos
GPU cluster. Part of **WS-A** of the Bare-Metal ML Platform. System: `ml-infra`.

**ADRs:** [ADR-0053](../../../docs/adrs/0053-baremetal-gpu-fabric-roce-infiniband.md)
(fabric: SR-IOV day-0 / DRANET gated target; RoCEv2/IB; jumbo frames). ADR-0028 labels.

## Two-stage maturity gate (ADR-0053 D3)

| Stage | Path | Default | What it is |
|-------|------|---------|-----------|
| **Day-0 primary** | SR-IOV / RDMA device plugin | **on** | `SriovNetworkNodePolicy` carves RDMA VFs + `SriovNetwork` attaches them to GPU pods. Proven, ships now. |
| **Gated target** | Cilium `netdev` DRA (mirror of DRANET) | **off** (`enable_dranet`) | `DeviceClass` + `ResourceClaimTemplate` selecting RDMA NICs, so Volcano schedules **GPU + NIC as one DRA claim**. |

The DRANET path is gated until DRA-`netdev` is GA on our Talos/k8s, a `dranet` release is
validated on our NIC/kernel/image, and it meets the **SR-IOV NCCL baseline** — the ADR-0053
D3 gate. An **NCCL all-reduce bandwidth test** is the acceptance gate
(`ai-sre/knowledge/nccl-troubleshooting.md`).

## Fabric mode

`fabric_mode` defaults **infiniband** (the UK doc's 400 Gbps IB + NVSwitch) → SR-IOV
`linkType = ib`; `roce` → `linkType = eth`. MTU 9000 (jumbo frames) either way.

## What it creates (when `enabled = true`)

| Resource | Purpose |
|----------|---------|
| `kubernetes_namespace.fabric` | Namespace, ADR-0028 labels |
| `helm_release.sriov_operator` | SR-IOV Network Operator (day-0 primary) |
| `kubernetes_manifest.sriov_node_policy` | `SriovNetworkNodePolicy` — RDMA VFs |
| `kubernetes_manifest.sriov_network` | `SriovNetwork` — attaches VFs to pods |
| `kubernetes_manifest.dranet_device_class` | (gated) DRANET DeviceClass |
| `kubernetes_manifest.dranet_claim_template` | (gated) DRANET ResourceClaimTemplate |

## Apply-gated

`var.enabled` defaults **false**. Providers mocked at plan time — no live cluster, no Helm
install. No `terraform apply` in this repo.

## ADR-0028 labeling

Dotted keys: `platform.system = ml-infra`, `platform.component = gpu-fabric`,
`platform.managed-by = terragrunt`, plus `platform_labels` overrides.

## Testing

```bash
terraform init -backend=false
terraform test
```
