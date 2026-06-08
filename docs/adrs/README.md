# Architecture Decision Records

This directory holds the platform-design Architecture Decision Records (ADRs).
Each ADR follows [`0000-template.md`](0000-template.md): Context → Decision →
Alternatives considered → Consequences → Implementation notes → References.

ADRs 0001–0002 are native to platform-design. ADRs 0003–0016 were **ported during
the 2026-06 platform-design sync** from the source-of-truth estate
(`infra@572b54d` and `argocd@c364c6c`), with wording adapted to
this transaction-analytics platform. Each ported ADR carries a provenance footer
and is marked **adopted** (live in the source estate) or **design-target**
(proposed / rolling out). The two CI/CD ADRs (0015, 0016) were promoted from
Proposed to **Accepted — rolling out** once PR #241 implemented them in-repo
(Tier-1 composite actions + reusable workflows + cosign signing).

ADRs 0017–0027 are **research-backed + doc-verified 2026-06-07 (Context7 + official
AWS/vendor docs)** — formalized from the 2026 platform modernization deep-dives
(grounded in `infra@572b54d` / `argocd@c364c6c`). They are all **Accepted** —
**ratified 2026-06-07 by the platform owner** — but remain **pending** in
platform-design (decided, not yet implemented). They are tracked by ROADMAP Phase 8
under epic #252. ADRs 0017–0022 were corrected per the 2026-06-07 doc-verification
pass before ratification (e.g. AFT account vending in 0017, the six Pod Identity
session tags + ESO upgrade prereq in 0018, netkit unblocked on kernel 6.12 in 0019,
admission-time cosign verification in 0020, OTel SLO-gating in 0021, the supply-chain
follow-ons in 0022).

Every ported ADR also carries a **platform-design status** (`synced` / `partial`
/ `pending`) recording whether the decision is actually wired into *this* repo —
see the column in the index below. This makes the catalog a development driver:
the ROADMAP can point at the `partial` / `pending` rows as the remaining work.

## Index

The **platform-design status** column records whether each decision is actually
present in *this* repo (verified against modules / apps / charts), independent of
its status in the source estate: `synced` (decision wired in-repo), `partial`
(decision partly present or parameterised but not fully enforced), `pending` (not
yet ported). It is the signal the ROADMAP uses to see where the mock lags a
decision.

| ADR | Title | Status | platform-design status | Provenance |
|-----|-------|--------|------------------------|------------|
| [0001](0001-ou-split.md) | OU split — Prod / Non-Prod / Deployments / Suspended / Sandbox | Accepted | n/a (native) | native |
| [0002](0002-tf-only-state-backend.md) | Terraform-only state backend bootstrap | Accepted | n/a (native) | native |
| [0003](0003-cilium-over-aws-vpc-cni.md) | Cilium over aws-vpc-cni as the EKS CNI | Accepted | synced | ported · adopted |
| [0004](0004-terragrunt-over-plain-terraform.md) | Terragrunt over plain Terraform for multi-account orchestration | Accepted | synced | ported · adopted |
| [0005](0005-hub-spoke-transit-gateway.md) | Hub-and-spoke connectivity via AWS Transit Gateway | Accepted | synced | ported · adopted |
| [0006](0006-argocd-for-gitops.md) | ArgoCD for GitOps delivery of Kubernetes workloads | Accepted | synced | ported · adopted |
| [0007](0007-karpenter-over-cluster-autoscaler.md) | Karpenter over Cluster Autoscaler for EKS node provisioning | Accepted | synced | ported · adopted |
| [0008](0008-external-secrets-operator.md) | External Secrets Operator over native K8s secrets | Accepted | synced (eso-irsa WIP) | ported · adopted |
| [0009](0009-cilium-gateway-api-ingress.md) | Cilium Gateway API as the cluster ingress controller | Accepted | synced (#247) | ported · adopted |
| [0010](0010-eks-public-endpoint-cidr-allowlist.md) | EKS public API endpoint with a parameterised CIDR allow-list | Accepted | synced (#245) | ported · adopted |
| [0011](0011-break-glass-iam-destroy-protection.md) | Break-glass IAM user destroy protection | Accepted | synced (#246) | ported · adopted |
| [0012](0012-cluster-role-label-scheme-for-appsets.md) | `cluster_role` label scheme for ArgoCD ApplicationSet selectors | Accepted | synced | ported · adopted |
| [0013](0013-inter-vpc-access-security-model.md) | Inter-VPC access security model (TGW segmentation + cross-estate VPN join) | Accepted | synced (#249) | ported · adopted |
| [0014](0014-argo-rollouts-canary-progressive-delivery.md) | Argo Rollouts canary with Gateway API traffic-routing and analysis | Accepted | synced (#238) | ported · adopted |
| [0015](0015-reusable-ci-pipelines.md) | Reusable CI/CD pipelines for the platform organisation | Accepted — rolling out | synced (#241) | ported · implemented by #241 |
| [0016](0016-tier1-supply-chain-hardening.md) | Tier 1 CI/CD hardening — dep scan, secrets, SAST, signing, manifest validation, smoke | Accepted | synced (#241, #248) | ported · implemented by #241, #248 |
| [0017](0017-resource-side-perimeter-and-declarative-org-controls.md) | Resource-side data perimeter and declarative org controls (AFT vending, RCPs, EC2 Declarative Policies, full-IAM SCPs) | Accepted | pending | research-backed + doc-verified |
| [0018](0018-eks-pod-identity-as-default-workload-identity.md) | EKS Pod Identity as the default workload identity (IRSA becomes legacy) | Accepted | pending | research-backed + doc-verified |
| [0019](0019-harvest-cilium-ebpf-capabilities.md) | Harvest unused Cilium / eBPF capabilities (OBI tracing, Hubble UI, Tetragon, ClusterMesh, netkit pilot) | Accepted | pending | research-backed + doc-verified |
| [0020](0020-kyverno-and-vap-policy-engine.md) | Kyverno + ValidatingAdmissionPolicy as the policy-engine layer (admission-time cosign) | Accepted | pending | research-backed + doc-verified |
| [0021](0021-kargo-gitops-promotion-layer.md) | Kargo as the GitOps environment-promotion layer (OTel SLO-gating) | Accepted | pending | research-backed + doc-verified |
| [0022](0022-ci-supply-chain-runtime-hardening.md) | CI supply-chain runtime hardening — Actions SAST + runner egress monitoring | Accepted | pending | research-backed + doc-verified |
| [0023](0023-vpc-lattice-resource-connectivity.md) | VPC Lattice resource connectivity (cross-account/cross-VPC TCP resource access) | Accepted | pending | research-backed + doc-verified |
| [0024](0024-argocd-operational-hardening.md) | ArgoCD operational hardening (PreDelete hooks, shallow clone, server-side diff/apply, progressive ApplicationSet rollout) | Accepted | pending | research-backed + doc-verified |
| [0025](0025-envoy-gateway-secondary-l7.md) | Envoy Gateway as a secondary L7 GatewayClass alongside Cilium | Accepted | pending | research-backed + doc-verified |
| [0026](0026-observability-target-architecture.md) | Observability target architecture (LGTM: Prometheus 3 + Thanos, Loki, Tempo, Alloy) | Accepted | pending | research-backed + doc-verified |
| [0027](0027-kubernetes-cost-opencost-cur.md) | Kubernetes cost allocation via OpenCost + AWS CUR/Athena | Accepted | pending | research-backed + doc-verified |
| [0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) | Unified Platform Tagging and Labeling Taxonomy | Accepted | pending | native |


## Notes on the sync

- **Multi-account strategy** (source `infra` ADR-007) is **not** a
  separate ADR here: it overlaps [ADR-0001](0001-ou-split.md) (the OU split). The
  account/OU rationale (blast-radius isolation, per-account cost allocation,
  OU-level SCP guardrails, Control Tower vending, separate Security/Log Archive
  and Network/Shared accounts) is folded into ADR-0001 rather than duplicated.
- Source numbering does not map 1:1 onto target numbering: ported ADRs were
  renumbered sequentially from 0003 with clearer kebab titles, and the two CI/CD
  ADRs land last as 0015–0016.

## Conventions

- Filenames: `NNNN-kebab-title.md`, zero-padded to four digits.
- New ADRs continue from the highest existing number; never renumber a merged ADR.
- A superseded ADR keeps its file and links forward via `Superseded by: ADR-NNNN`.
