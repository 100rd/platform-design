# Architecture Decision Records

This directory holds the platform-design Architecture Decision Records (ADRs).
Each ADR follows [`0000-template.md`](0000-template.md): Context → Decision →
Alternatives considered → Consequences → Implementation notes → References.

ADRs 0001–0002 are native to platform-design. ADRs 0003–0016 were **ported during
the 2026-06 platform-design sync** from the source-of-truth estate
(`qbiq-ai/infra@572b54d` and `qbiq-ai/argocd@c364c6c`), with wording adapted to
this transaction-analytics platform. Each ported ADR carries a provenance footer
and is marked **adopted** (live in the source estate) or **design-target**
(proposed / rolling out).

## Index

| ADR | Title | Status | Provenance |
|-----|-------|--------|------------|
| [0001](0001-ou-split.md) | OU split — Prod / Non-Prod / Deployments / Suspended / Sandbox | Accepted | native |
| [0002](0002-tf-only-state-backend.md) | Terraform-only state backend bootstrap | Accepted | native |
| [0003](0003-cilium-over-aws-vpc-cni.md) | Cilium over aws-vpc-cni as the EKS CNI | Accepted | ported · adopted |
| [0004](0004-terragrunt-over-plain-terraform.md) | Terragrunt over plain Terraform for multi-account orchestration | Accepted | ported · adopted |
| [0005](0005-hub-spoke-transit-gateway.md) | Hub-and-spoke connectivity via AWS Transit Gateway | Accepted | ported · adopted |
| [0006](0006-argocd-for-gitops.md) | ArgoCD for GitOps delivery of Kubernetes workloads | Accepted | ported · adopted |
| [0007](0007-karpenter-over-cluster-autoscaler.md) | Karpenter over Cluster Autoscaler for EKS node provisioning | Accepted | ported · adopted |
| [0008](0008-external-secrets-operator.md) | External Secrets Operator over native K8s secrets | Accepted | ported · adopted |
| [0009](0009-cilium-gateway-api-ingress.md) | Cilium Gateway API as the cluster ingress controller | Accepted | ported · adopted |
| [0010](0010-eks-public-endpoint-cidr-allowlist.md) | EKS public API endpoint with a parameterised CIDR allow-list | Accepted | ported · adopted (prod allow-list is a design-target) |
| [0011](0011-break-glass-iam-destroy-protection.md) | Break-glass IAM user destroy protection | Accepted | ported · adopted |
| [0012](0012-cluster-role-label-scheme-for-appsets.md) | `cluster_role` label scheme for ArgoCD ApplicationSet selectors | Accepted | ported · adopted |
| [0013](0013-inter-vpc-access-security-model.md) | Inter-VPC access security model (TGW segmentation + cross-estate VPN join) | Accepted | ported · adopted (legacy-side routes + prod NACL backstop are design-targets) |
| [0014](0014-argo-rollouts-canary-progressive-delivery.md) | Argo Rollouts canary with Gateway API traffic-routing and analysis | Accepted | ported · adopted |
| [0015](0015-reusable-ci-pipelines.md) | Reusable CI/CD pipelines for the platform organisation | Proposed | ported · design-target |
| [0016](0016-tier1-supply-chain-hardening.md) | Tier 1 CI/CD hardening — dep scan, secrets, SAST, signing, manifest validation, smoke | Proposed | ported · design-target |

## Notes on the sync

- **Multi-account strategy** (source `qbiq-ai/infra` ADR-007) is **not** a
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
