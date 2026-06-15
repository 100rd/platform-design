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
**ratified 2026-06-07 by the platform owner** — and are now largely **implemented**
in platform-design (epic #252), except 0017 / 0019 / 0022 which remain **partial**
(see the platform-design status column + the remaining-work follow-ups #313/#314/#315).
They are tracked by ROADMAP Phase 8 under epic #252. ADRs 0017–0022 were corrected per the 2026-06-07 doc-verification
pass before ratification (e.g. AFT account vending in 0017, the six Pod Identity
session tags + ESO upgrade prereq in 0018, netkit unblocked on kernel 6.12 in 0019,
admission-time cosign verification in 0020, OTel SLO-gating in 0021, the supply-chain
follow-ons in 0022).

ADRs 0029–0032 are the **Batch-B infra-team ADRs**, implemented this session
(2026-06-08) — modules / templates / charts landed in their respective PRs and
are doc-verified 2026-06-08. ADR-0034 is **Proposed — Deferred (on hold)** by
the platform owner pending a dedicated Backstage owner being assigned.

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
| [0017](0017-resource-side-perimeter-and-declarative-org-controls.md) | Resource-side data perimeter and declarative org controls (AFT vending, RCPs, EC2 Declarative Policies, full-IAM SCPs) | Accepted | partial | research-backed + doc-verified |
| [0018](0018-eks-pod-identity-as-default-workload-identity.md) | EKS Pod Identity as the default workload identity (IRSA becomes legacy) | Accepted | implemented | research-backed + doc-verified |
| [0019](0019-harvest-cilium-ebpf-capabilities.md) | Harvest unused Cilium / eBPF capabilities (OBI tracing, Hubble UI, Tetragon, ClusterMesh, netkit pilot) | Accepted | partial | research-backed + doc-verified |
| [0020](0020-kyverno-and-vap-policy-engine.md) | Kyverno + ValidatingAdmissionPolicy as the policy-engine layer (admission-time cosign) | Accepted | implemented | research-backed + doc-verified |
| [0021](0021-kargo-gitops-promotion-layer.md) | Kargo as the GitOps environment-promotion layer (OTel SLO-gating) | Accepted | implemented | research-backed + doc-verified |
| [0022](0022-ci-supply-chain-runtime-hardening.md) | CI supply-chain runtime hardening — Actions SAST + runner egress monitoring | Accepted | partial | research-backed + doc-verified |
| [0023](0023-vpc-lattice-resource-connectivity.md) | VPC Lattice resource connectivity (cross-account/cross-VPC TCP resource access) | Accepted | implemented | research-backed + doc-verified |
| [0024](0024-argocd-operational-hardening.md) | ArgoCD operational hardening (PreDelete hooks, shallow clone, server-side diff/apply, progressive ApplicationSet rollout) | Accepted | implemented | research-backed + doc-verified |
| [0025](0025-envoy-gateway-secondary-l7.md) | Envoy Gateway as a secondary L7 GatewayClass alongside Cilium | Accepted | implemented | research-backed + doc-verified |
| [0026](0026-observability-target-architecture.md) | Observability target architecture (LGTM: Prometheus 3 + Thanos, Loki, Tempo, Alloy) | Accepted | implemented | research-backed + doc-verified |
| [0027](0027-kubernetes-cost-opencost-cur.md) | Kubernetes cost allocation via OpenCost + AWS CUR/Athena | Accepted | implemented | research-backed + doc-verified |
| [0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) | Unified Platform Tagging and Labeling Taxonomy | Accepted | pending | native |
| [0029](0029-ecr-pull-through-cache.md) | ECR Pull-Through Cache for public upstream registries | Accepted | synced (module) | proposal — doc-verified 2026-06-08 |
| [0030](0030-bottlerocket-node-os.md) | Bottlerocket as the EKS node operating system | Accepted | synced (module) / pending (manifests) | proposal — doc-verified 2026-06-08 |
| [0031](0031-secret-rotation.md) | Automated secret rotation via Secrets Manager rotation Lambda + ESO auto-refresh | Accepted | synced (module) | proposal — doc-verified 2026-06-08 |
| [0032](0032-db-migrations-gitops.md) | DB migrations via ArgoCD PreSync Jobs | Accepted | synced (helm) | proposal — doc-verified 2026-06-08 |
| [0034](0034-backstage-idp.md) | Backstage as the Internal Developer Platform | Proposed — Deferred (on hold) | pending | proposal — doc-verified 2026-06-08 |
| [0035](0035-control-tower-and-aft.md) | AWS Control Tower landing zone + Account Factory for Terraform (AFT) vending | Accepted | pending | epic #293 — supersedes ADR-0017 item-0; design 2026-06-09 |
| [0036](0036-gke-ml-infra-parity-multiregion.md) | GKE ML-infra parity + multi-region GKE + GCP cost guardrail (GPU Operator, DCGM, Volcano, billing-budget) | Accepted | pending | WS-A of GCP ML platform plan; design 2026-06-10 |
| [0037](0037-ml-cicd-pipeline-mlflow.md) | ML CI/CD pipeline — Airflow orchestrator + MLflow registry + GCS artifact store | Proposed | pending | WS-B of GCP ML platform plan; design 2026-06-10 |
| [0038](0038-ml-observability-drift.md) | ML observability — drift detection, accuracy monitoring, and retrain trigger (Evidently + whylogs, Prometheus-native) | Proposed | pending | WS-C of GCP ML platform plan; design 2026-06-10 |
| [0039](0039-self-serve-observability.md) | Self-serve observability — templated Grafana folders, starter dashboards, and alert-rules-as-code (Backstage deferred, ADR-0034) | Proposed | pending | WS-D of GCP ML platform plan; design 2026-06-10 |
| [0040](0040-soc-posture-and-oncall.md) | SOC2 posture — GCP org-policy parity + cross-cloud WIF (GCP↔AWS) + control-to-evidence matrix + ML on-call/runbooks | Proposed | pending | WS-E of GCP ML platform plan; design 2026-06-10 |
| [0041](0041-golden-paths-collaboration.md) | Golden-path templates, shared contracts, and cross-team collaboration model (Backstage deferred, ADR-0034) | Proposed | pending | WS-F of GCP ML platform plan; design 2026-06-10 |
| [0042](0042-gpu-inference-networking-serving-uplift.md) | GPU inference networking & serving uplift — per-family fabric (jumbo+gVNIC / GPUDirect-TCPX·TCPXO / DRANET·RoCE), GKE Inference Gateway, Cloud Armor | Proposed | pending | extends WS-A (network/serving axis); design 2026-06-13 |
| [0043](0043-eks-cross-cluster-connectivity.md) | EKS cross-cluster connectivity (app A→B) — options survey + decision: peered TGW substrate, default Cilium ClusterMesh, per-flow PrivateLink / VPC Lattice / NLB+Route53 / private ingress | Proposed | pending | builds on ADR-0005/0013/0019/0023; design 2026-06-14 |
| [0044](0044-aws-eks-gpu-ml-foundation-multiregion.md) | AWS EKS GPU ML-platform foundation (NVIDIA GPU Operator, DCGM, DRA, Volcano) + multi-region EKS + reuse `budgets` cost guardrail — greenfield mirror of ADR-0036 | Proposed | pending | WS-A of AWS ML platform plan; greenfield; design 2026-06-15 |
| [0045](0045-aws-efa-gpu-fabric-placement-groups.md) | AWS EFA high-performance GPU fabric (GPUDirect RDMA + cluster placement groups) — per-provisioner EFA device-plugin (Karpenter) vs EFA DRA driver (managed node groups); mirrors ADR-0042 fabric half | Proposed | pending | extends WS-A on the fabric axis; design 2026-06-15 |
| [0046](0046-eks-node-strategy-karpenter-spot.md) | EKS GPU node strategy — Karpenter (default) + managed node groups (reserved EFA-DRA training); spot / scale-to-zero / consolidation / Capacity Blocks | Proposed | pending | WS-A elasticity sub-decision (AWS-specific; GKE got it free from gcp-gke-gpu-nodepools); design 2026-06-15 |
| [0047](0047-eks-inference-serving-front-waf.md) | EKS inference serving front — Gateway API Inference Extension (InferencePool/InferenceObjective, v1 GA) on Envoy Gateway (default) + Endpoint Picker, ALB fallback, VPC Lattice out; AWS WAF; mirrors ADR-0042 serving half | Proposed | pending | extends WS-A on the serving axis; design 2026-06-15 |
| [0048](0048-aws-ml-cicd-registry-drift.md) | AWS ML CI/CD + MLflow registry + drift on EKS — AWS-native backends (S3 + RDS Postgres + Pod-Identity/ABAC + ECR), folding the cluster-agnostic ML layer from ADR-0037/0038 | Proposed | pending | WS-B + WS-C of AWS ML platform plan; design 2026-06-15 |
| [0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md) | Bare-metal GPU Kubernetes on Talos Linux — foundation, immutability & multi-DC (self-operated control plane, no cloud autoscaler, ≥2 UK DCs) | Proposed | pending | WS-A of Bare-Metal ML platform plan; greenfield mirror of ADR-0036; design 2026-06-15 |
| [0050](0050-talos-gpu-driver-system-extensions.md) | Talos GPU driver delivery via system extensions (vs host install) — `nonfree-kmod-nvidia` + `nvidia-container-toolkit` image-baked; GPU Operator driver-less | Proposed | pending | WS-A/WS-E of Bare-Metal ML platform plan; mirror of ADR-0036 D1; design 2026-06-15 |
| [0051](0051-baremetal-networking-cilium-lb-bgp.md) | Bare-metal networking — Cilium CNI (kube-proxy-less) + LB-IPAM/BGP vs MetalLB (replaces cloud VPC + cloud LB) | Proposed | pending | WS-A of Bare-Metal ML platform plan; replaces cloud-LB layer of ADR-0042; design 2026-06-15 |
| [0052](0052-baremetal-storage-rook-ceph.md) | Bare-metal storage for ML artifacts & state — Rook-Ceph (block/FS/RGW S3) vs Mayastor vs local-path; MinIO/Ceph-RGW artifact store; **requires `rbd`+`ceph` kernel modules in Talos MachineConfig** | Proposed | pending | WS-A/WS-B of Bare-Metal ML platform plan; substitutes GCS `ml-artifact-store`; design 2026-06-15 |
| [0053](0053-baremetal-gpu-fabric-roce-infiniband.md) | Bare-metal high-performance GPU fabric (RoCEv2/InfiniBand + SR-IOV day-0 → DRANET gated) & on-prem serving front (Gateway API: InferencePool/InferenceObjective + WAF) | Proposed | pending | extends WS-A (fabric/serving axis); bare-metal mirror of ADR-0042; design 2026-06-15 |
| [0054](0054-baremetal-elasticity-node-lifecycle.md) | Bare-metal elasticity & node lifecycle without a cloud autoscaler — Cluster-API/Sidero vs Metal³ vs robot-API vs static pools; workload scale-to-zero | Proposed | pending | WS-A of Bare-Metal ML platform plan; replaces GKE/Karpenter autoscaling; design 2026-06-15 |



## Notes on the sync

- **Multi-account strategy** (source `infra` ADR-007) is **not** a
  separate ADR here: it overlaps [ADR-0001](0001-ou-split.md) (the OU split). The
  account/OU rationale (blast-radius isolation, per-account cost allocation,
  OU-level SCP guardrails, Control Tower vending, separate Security/Log Archive
  and Network/Shared accounts) is folded into ADR-0001 rather than duplicated.
- Source numbering does not map 1:1 onto target numbering: ported ADRs were
  renumbered sequentially from 0003 with clearer kebab titles, and the two CI/CD
  ADRs land last as 0015–0016.
- ADR-0033 is intentionally unassigned (reserved gap between the Batch-B ADRs
  and the Backstage proposal).
- ADR-0037 is intentionally unassigned (reserved gap; WS-B ML CI/CD + MLflow ADR
  will use that slot).

## Conventions

- Filenames: `NNNN-kebab-title.md`, zero-padded to four digits.
- New ADRs continue from the highest existing number; never renumber a merged ADR.
- A superseded ADR keeps its file and links forward via `Superseded by: ADR-NNNN`.
