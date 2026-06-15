# baremetal-cilium-lb

**Cilium CNI (kube-proxy-less) + LB-IPAM + BGP control-plane** for the bare-metal GPU
cluster. Part of **WS-A** of the Bare-Metal ML Platform. System: `ml-infra`.

**ADRs:** [ADR-0051](../../../docs/adrs/0051-baremetal-networking-cilium-lb-bgp.md)
(Cilium LB-IPAM/BGP vs MetalLB), with MTU 9000 for the fabric per
[ADR-0053](../../../docs/adrs/0053-baremetal-gpu-fabric-roce-infiniband.md). ADR-0028 labels.

## Why a load-balancer module at all

On owned hardware there is **no cloud VPC and no cloud LB** (ADR-0051) — nothing hands a
Service an external IP. So Cilium provides both pod networking (eBPF, kube-proxy-less) and
the load-balancer: **LB-IPAM** allocates service VIPs and the **Cilium BGP control-plane**
advertises them to the ToR switches.

## What it creates (when `enabled = true`)

| Resource | Purpose |
|----------|---------|
| `helm_release.cilium` | Cilium CNI, kube-proxy-less, MTU 9000, BGP control-plane |
| `kubernetes_manifest.lb_ip_pool` | `CiliumLoadBalancerIPPool` — service-VIP address pool |
| `kubernetes_manifest.bgp_cluster_config` | (gated) `CiliumBGPClusterConfig` — ToR peering |
| `kubernetes_manifest.bgp_peer_config` | (gated) `CiliumBGPPeerConfig` — runbook-tuned timers |

## BGP and the runbook

`enable_bgp` defaults **true**. BGP timers honour `ai-sre/knowledge/cilium-bgp-issues.md`:
**hold timer 180s** so sessions survive CPU pressure on GPU nodes, ToR `max-prefix` sized
upstream. When `enable_bgp = false`, LB-IPAM still allocates VIPs (the **MetalLB-L2-style
fallback** documented in ADR-0051) but BGP peering is not configured.

## Apply-gated

`var.enabled` defaults **false**. The CRs are rendered against mocked providers at plan
time — no live cluster. No `terraform apply` / Helm install in this repo.

## ADR-0028 labeling

Dotted keys: `platform.system = ml-infra`, `platform.component = networking`,
`platform.managed-by = terragrunt`, plus `platform_labels` overrides — on the Helm
workloads and every LB/BGP custom resource.

## Testing

```bash
terraform init -backend=false
terraform test
```
