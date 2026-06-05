# ADR-0003: Cilium over aws-vpc-cni as the EKS CNI

- Status: **Accepted** — decision is *adopted (live in source estate)*
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

The transaction-analytics platform runs all AWS control-plane workloads on EKS
(GitOps orchestration, the LiteLLM/inference gateway front-end, public APIs).
These clusters need a CNI plugin. The EKS default `aws-vpc-cni` allocates
ENI-attached IPs from the VPC, which caps pod density per node and leaves
network-policy enforcement to security-groups-for-pods rather than a first-class
policy layer. We evaluated three options:

1. **aws-vpc-cni** (default) — tight VPC integration but limited pod density and
   coarse policy model.
2. **Calico** — mature network policies but iptables-based at scale.
3. **Cilium** — eBPF-based with advanced observability and security.

Pod-to-pod encryption matters here: the control plane carries scoring requests
and references to client data, so data-in-transit protection is a baseline
requirement rather than a nice-to-have.

## Decision

Use **Cilium** as the CNI for all EKS clusters in the platform.

A reviewer can check conformance by confirming new clusters ship Cilium (not
`aws-vpc-cni`) and that network policy is expressed as `CiliumNetworkPolicy` /
`CiliumClusterwideNetworkPolicy` rather than security-groups-for-pods.

## Alternatives considered

### Alternative A: aws-vpc-cni (EKS default)
Keep the managed default add-on.
Rejected because: ENI IP allocation caps pod density per node and the policy
model relies on security-groups-for-pods, which is coarser and harder to audit
than L3/L4/L7 Cilium policies. No native pod-to-pod encryption without sidecars.

### Alternative B: Calico
Mature, widely deployed network-policy CNI.
Rejected because: iptables-based dataplane adds per-packet overhead at the
connection rates the platform sees, and it lacks the built-in flow observability
(Hubble) and transparent WireGuard encryption Cilium provides.

### Alternative C: Status quo
At time of decision the clusters were greenfield, so "status quo" is the EKS
default (Alternative A) — same rejection.

## Consequences

### Positive
- eBPF kernel-level packet processing avoids iptables overhead (~20–30% better
  latency observed on service-mesh-style workloads in source-estate benchmarks).
- Transparent WireGuard pod-to-pod encryption satisfies data-in-transit
  requirements without per-pod sidecars.
- L3/L4/L7 DNS-aware policies via `CiliumNetworkPolicy` are more expressive than
  vanilla `NetworkPolicy`.
- Hubble gives flow logs, service maps, and HTTP-level metrics from eBPF — no
  extra agent. This pairs with the platform's existing Prometheus/Grafana stack.
- Overlay mode is not bounded by ENI IP allocation, so pod density per node is
  higher.
- ClusterMesh enables cross-cluster connectivity (relevant for the multi-region
  control plane) without bolt-on infrastructure.

### Negative
- Team must learn Cilium-specific CRDs.
- Cannot use `aws-vpc-cni` security-groups-for-pods — policy moves entirely to
  Cilium.
- Cilium operator adds management/upgrade overhead, maintained separately from
  EKS managed add-ons.

### Risks
- Kernel-version dependency (5.10+). Mitigated by AL2023 node AMIs, which satisfy
  it.
- Cilium upgrade path is decoupled from EKS add-on lifecycle. Mitigated by
  pinning the Cilium chart version in GitOps and gating upgrades behind a runbook.

## Implementation notes

- Cilium is installed via Helm (GitOps-managed), CNI add-on disabled on the
  cluster module.
- Network policy authored as `CiliumNetworkPolicy`; default-deny baseline per
  namespace.
- Locks in alongside ADR-0009 (Cilium Gateway API ingress), which reuses the same
  Cilium install.

## References

- Cilium docs: <https://docs.cilium.io/>
- Ported from `infra` ADR-001 (Cilium over aws-vpc-cni)
- Related: ADR-0009 (Cilium Gateway API ingress)

---
*Ported from infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live).*
