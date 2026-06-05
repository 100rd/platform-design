# ADR-0007: Karpenter over Cluster Autoscaler for EKS node provisioning

- Status: **Accepted** — decision is *adopted (live in source estate)*
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

The platform's EKS clusters carry bursty, heterogeneous workloads: steady GitOps
and observability components alongside spiky inference-gateway and template-mining
support jobs. Node scaling must right-size capacity quickly and cheaply, with a
preference for Graviton/arm64 and spot where workloads tolerate it. Options:

1. **Cluster Autoscaler (CAS)** — scales predefined node groups based on pending
   pods.
2. **Karpenter** — provisions nodes directly from pod requirements.

## Decision

Use **Karpenter** for all EKS node scaling, with capacity shaped by `NodePool`
and `EC2NodeClass` CRDs. A reviewer can check conformance by confirming capacity
is expressed as Karpenter `NodePool`/`EC2NodeClass` rather than managed node
groups + CAS.

## Alternatives considered

### Alternative A: Cluster Autoscaler
Scale predefined ASG-backed node groups.
Rejected because: CAS scales fixed node-group shapes, frequently over-provisioning
nodes that don't match actual pod requests; scale-up rides ASG latency; and
scale-down only removes empty nodes (no active consolidation).

### Alternative B: Status quo
Greenfield — "status quo" is no autoscaling (static node groups), which neither
right-sizes nor controls cost for bursty workloads.

## Consequences

### Positive
- Bin-packing: Karpenter provisions right-sized instances from actual pod
  requests, across a broad instance set, prioritising spot where allowed — good
  fit for spiky inference-support workloads.
- Speed: provisions nodes in under ~60s via direct EC2 API calls.
- Consolidation actively bin-packs and terminates underutilised nodes.
- Disruption budgets handle rolling updates and spot interruptions gracefully.
- AWS-native EKS integration; `EC2NodeClass` simplifies AMI/subnet/SG selection
  (and makes Graviton/arm64 defaults easy).

### Negative
- EKS-specific (not portable to other K8s platforms).
- Must author `NodePool` / `EC2NodeClass` CRDs (learning curve).
- Manages its own node lifecycle — cannot use ASG lifecycle hooks / warm pools.

### Risks
- Spot interruption handling is built-in but requires proper pod-disruption
  budgets on workloads. Mitigated by shipping default PDBs in the reference chart.
- Karpenter is younger than CAS. Mitigated by pinning to the stable v1 API and
  GitOps-gated upgrades.

## Implementation notes

- Karpenter installed via Helm (GitOps); `NodePool` favours Graviton + spot for
  tolerant workloads, on-demand for stateful/critical pods.
- Consolidation enabled; disruption budgets tuned per workload class.

## References

- Karpenter docs: <https://karpenter.sh/>
- Ported from `infra` ADR-005 (Karpenter over Cluster Autoscaler)
- Related: ADR-0003 (Cilium CNI), ADR-0006 (ArgoCD)

---
*Ported from infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live).*
