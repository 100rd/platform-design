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
