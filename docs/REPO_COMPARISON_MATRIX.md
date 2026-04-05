# Repository Comparison Matrix: infra vs platform-design

> Generated: 2026-04-05
> Source of truth: `project/infra` (qbiq-ai/infra production landing zone)
> Target: `project/platform-design` (multi-region platform)
>
> Legend: YES = present and functional | PARTIAL = exists but incomplete/different | NO = absent | AHEAD = platform-design exceeds infra

---

## 1. Tooling Versions

| Tool / Component | infra version | platform-design version | Gap | Direction |
|---|---|---|---|---|
| Terraform | 1.14.8 | >= 1.11.0 (unpinned) | Not pinned | platform-design should pin to 1.14.8 |
| Terragrunt | 0.99.5 | >= 0.68.0 (unpinned) | Not pinned | platform-design should pin to 0.99.5 |
| AWS Provider | ~> 5.90 | ~> 6.0 | MAJOR version ahead | platform-design is AHEAD — evaluate regression risk |
| Helm Provider | ~> 2.14 | not centrally pinned | Missing pin | infra pattern preferred |
| Kubernetes Provider | ~> 1.5 | not centrally pinned | Missing pin | infra pattern preferred |
| EKS cluster version | 1.35 | 1.29 default / 1.34 max | 1–6 minor versions behind | Upgrade platform-design |
| Cilium chart | 1.19.2 | 1.17.1 | 2 minor versions behind | Upgrade platform-design |
| Karpenter chart | 1.10.0 | 1.8.1 | 2 minor versions behind | Upgrade platform-design |
| ArgoCD chart | 3.3.6 | unclear (DEPLOYMENTS.md incomplete) | Unknown | Audit and align |
| External Secrets Operator | 2.2.0 | v0.14.1 | MAJOR gap — 14 minor versions | Critical upgrade needed |
| cert-manager chart | 1.20.1 | 1.17.2 (cert-manager app ver) | 3 minor behind | Upgrade platform-design |
| AWS LB Controller chart | 3.1.0 | 3.0.0 | 1 patch behind | Upgrade platform-design |
| kube-prometheus-stack chart | 82.15.1 | ~81.2.2 | 1 minor behind | Upgrade platform-design |
| Loki chart | 3.7.1 | ~6.51.0 (v3.0 app) | Different chart track | Reconcile chart source |
| Tempo chart | 2.10.3 | ~1.24.3 (distributed) | Different deployment mode | Align with infra SimpleScalable |
| terraform-aws-modules/vpc | 6.6.0 | not centrally tracked | Missing | Centralize version tracking |
| terraform-aws-modules/eks | 21.15.1 | not centrally tracked | Missing | Centralize version tracking |
| terraform-aws-modules/iam | 6.4.0 | not centrally tracked | Missing | Centralize version tracking |
| Trivy | 0.69.3 | not pinned in CI | Missing pin | Pin in CI |
| Kargo | not present | 1.2.0 | AHEAD | platform-design unique value |
| Pyroscope | not present | 1.18.0 | AHEAD | platform-design unique value |
| Falco | not present | present | AHEAD | platform-design unique value |
| Thanos | not present | present | AHEAD | platform-design unique value |

---

## 2. Security and Compliance

| Feature | infra | platform-design | Priority |
|---|---|---|---|
| CIS AWS Foundations Benchmark v3.0 (90+ Checkov rules) | YES — `.checkov.yml`, enforced in CI | PARTIAL — Well-Architected checkov only, no CIS framework | P0 — Critical |
| Trivy config scan in CI | YES — `terraform-checks.yml` | NO — not in any workflow | P0 — Critical |
| Checkov CIS scan in CI | YES — `terraform-checks.yml` | PARTIAL — Well-Architected rules only (`well-architected.yml`) | P0 — Critical |
| IAM password policy (14 chars, 90-day rotation, 24 history) | YES — `modules/iam-baseline/` full CIS impl | PARTIAL — PCI-DSS compliant but different baseline, no Access Analyzer, no S3 block, no EBS encryption | P0 — Critical |
| IAM Access Analyzer (org + account level) | YES — `modules/iam-baseline/main.tf` | NO | P0 — Critical |
| S3 public access block (account level) | YES — `modules/iam-baseline/main.tf` | NO | P0 — Critical |
| EBS encryption by default | YES — `modules/iam-baseline/main.tf` | NO | P0 — Critical |
| SCP: deny-leave-org | YES | YES | Aligned |
| SCP: deny-root-account | YES | YES | Aligned |
| SCP: region-restriction (eu-west-1 + global services exemption) | YES — with Terraform role exemptions | PARTIAL — EU regions present but no Terraform exemption logic | P1 — High |
| SCP: deny-cloudtrail-changes | YES | YES | Aligned |
| SCP: deny-guardduty-changes | YES | NO | P1 — High |
| SCP: deny-s3-public (root-level) | YES | NO | P1 — High |
| SCP: require-ebs-encryption (root-level) | YES | NO | P1 — High |
| SCP: deny-all-suspended (quarantine OU) | YES | NO | P1 — High |
| Suspended / Quarantine OU | YES — `modules/organizations/main.tf` | NO — platform-design OU structure has no Suspended OU | P1 — High |
| KMS per-account, auto-rotation, prevent_destroy | YES — `modules/kms/` | PARTIAL — KMS module exists, rotation YES, no prevent_destroy | P1 — High |
| CloudTrail org-wide | YES — `modules/cloudtrail-org/` | YES — `catalog/units/cloudtrail/` | Aligned |
| GuardDuty org-wide with all detectors | YES — `modules/guardduty-org/` | YES — `catalog/units/guardduty-org/` with all protectors | Aligned |
| SecurityHub org-wide | YES — `modules/securityhub-org/` | YES — `catalog/units/security-hub/` | Aligned |
| AWS Config (recorder + delivery) | YES — `modules/config-org/` | YES — `catalog/units/aws-config/` | Aligned |
| AWS Config CIS Managed Rules (10+ rules) | YES — MFA root, password policy, CloudTrail, VPC flow logs | NO — basic recorder only, no managed rules | P1 — High |
| AWS Config Conformance Packs | YES | NO | P2 — Medium |
| GitHub OIDC (keyless auth, 3 role types) | YES — `modules/github-oidc/` terraform/readonly/ecr-push | NO — no equivalent module in catalog | P1 — High |
| Secrets: all via ESO from Secrets Manager | YES — nothing in git | PARTIAL — ESO present but no explicit ESO external-secret for all infra secrets | P1 — High |
| WireGuard pod-to-pod encryption (Cilium) | YES — enabled in Cilium values | NO — Cilium installed but no WireGuard config | P2 — Medium |
| Falco runtime security | NO | YES — `modules/falco/` | AHEAD |
| WAF module | NO | YES — `modules/waf/` | AHEAD |
| OPA Gatekeeper | NO | YES — deployed via ArgoCD | AHEAD |
| Kyverno policies | NO | YES — deployed via ArgoCD | AHEAD |
| Network policies (egress) | PARTIAL — monitoring egress only | YES — `network-policies/` directory | platform-design AHEAD |
| PCI-DSS CDE isolation NodePool | NO | YES — karpenter nodepool taint | AHEAD |
| Secret scanning in CI | NO dedicated workflow | YES — `secret-scan.yml` | platform-design AHEAD |

---

## 3. AWS Organization Structure

| Feature | infra | platform-design | Notes |
|---|---|---|---|
| Number of accounts | 9 (Mgmt, Security, Log Archive, Network, Shared, Dev, Stage, Prod, Third-party) | 6 (Mgmt/org, Network, Dev, Staging, Prod, DR) | infra has Security + Log Archive as dedicated accounts per Control Tower |
| Control Tower landing zone | YES — 9-account CT structure | NO — standard Organizations, no CT | Significant architecture difference |
| Security account (dedicated) | YES | NO | infra has dedicated account for GuardDuty/SecurityHub aggregation |
| Log Archive account (dedicated) | YES | NO | infra has dedicated account for CloudTrail/Config logs |
| Shared Services account | YES — EKS+observability in shared | NO — not separate | infra observability lives in shared account |
| Third-party account | YES | NO | infra has isolated account for third-party workloads |
| DR account | NO | YES | platform-design AHEAD |
| Suspended/Quarantine OU | YES | NO | Missing in platform-design |
| Sandbox OU | NO | YES (via `organizational_units`) | platform-design AHEAD |
| OU structure | Security, Infrastructure, Workloads, Suspended | Security, Infrastructure, NonProd, Prod (via vars) | Different hierarchy |
| Tagging: Project, Environment, ManagedBy, Owner, CostCenter | YES — all in `terragrunt.hcl` default_tags | PARTIAL — missing Owner, CostCenter from provider default_tags | P2 — gap in platform-design root.hcl |
| Tagging: TerragruntPath, Repository | YES | NO — not in root.hcl default_tags | P2 |
| Per-unit tag overrides (tags.yml) | YES | NO | P3 |
| DynamoDB lock table (per-account) | YES — `${project}-terraform-locks` | PARTIAL — `terraform-locks-${account_name}` (no project prefix) | Minor naming difference |

---

## 4. Kubernetes Platform

| Feature | infra | platform-design | Notes |
|---|---|---|---|
| EKS version | 1.35 | 1.29–1.34 | Upgrade needed in platform-design |
| Cilium CNI | 1.19.2 | 1.17.1 | Upgrade needed |
| Cilium WireGuard encryption | YES | NO | Add to platform-design |
| Hubble observability full config | YES | PARTIAL — installed, not fully configured | Add network observability policies |
| Cilium ClusterMesh | NO | YES — `modules/clustermesh-connect/` | platform-design AHEAD |
| Karpenter | 1.10.0 | 1.8.1 | Upgrade needed |
| Karpenter: dev spot-only NodePool | YES — `nodepool-default.yaml` dev overlay | PARTIAL — spot_percentage input only | Adopt infra business-hours pattern |
| Karpenter: business-hours scale-to-zero (dev) | YES — scheduled in NodePool spec | NO | Add schedule to dev NodePool |
| Karpenter: prod on-demand preferred | YES | PARTIAL — spot_percentage=0 option | Explicit prod pool needed |
| Karpenter: multi-arch (ARM64/Graviton) | NO | YES — `architectures` variable | platform-design AHEAD |
| Karpenter: PCI-DSS isolated NodePool | NO | YES | platform-design AHEAD |
| Auto-shutdown Lambda (dev EC2) | YES — `modules/auto-shutdown/` | NO | Cost control gap |
| KEDA | YES — 2.19.0 | YES | Aligned |
| WPA (Watermark Pod Autoscaler) | NO | YES | platform-design AHEAD |
| External Secrets Operator | 2.2.0 | v0.14.1 | CRITICAL upgrade needed |
| cert-manager | 1.20.1 | 1.17.2 (app ver) | Upgrade needed |
| AWS LB Controller | 3.1.0 | 3.0.0 | Upgrade needed |
| Velero backup | YES | YES | Aligned |
| ArgoCD HA mode | YES — HA, 2+ replicas | YES — HA mode supported | Aligned |
| ArgoCD SSO via Dex + IAM Identity Center OIDC | YES — `k8s/system/argocd/values.yaml` | PARTIAL — `enable_dex=false` by default, no IAM IC config | Configure in platform-design |
| ArgoCD RBAC (admin/developer/readonly) | YES | PARTIAL — RBAC structure present but roles not mapped to IAM IC groups | Configure in platform-design |
| ArgoCD notifications (Slack on sync/failure) | YES — `k8s/system/argocd/values.yaml` | NO | Add to platform-design |
| ArgoCD ApplicationSets multicluster | NO | YES | platform-design AHEAD |
| Kargo progressive delivery | NO | YES — 1.2.0 | platform-design AHEAD |
| PodDisruptionBudgets on all system components | YES | PARTIAL — not universal | Apply infra pattern |
| ServiceMonitors on all system components | YES | PARTIAL — not universal | Apply infra pattern |
| Resource quotas per namespace | YES | NO | Add to platform-design |
| Platform CRDs (separate module) | NO | YES — `catalog/units/platform-crds/` | platform-design AHEAD |
| OPA Gatekeeper policies | NO | YES | platform-design AHEAD |
| Kyverno admission controller | NO | YES | platform-design AHEAD |
| OpenTelemetry Operator | NO | YES — OTEL Operator + auto-instrumentation | platform-design AHEAD |
| RabbitMQ Operator | NO | YES | platform-design AHEAD |
| Hetzner nodes support | NO | YES | platform-design AHEAD |
| GCP GPU integration | NO | YES — `modules/gcp-gke-gpu-nodepools/` | platform-design AHEAD |

---

## 5. Observability

| Feature | infra | platform-design | Notes |
|---|---|---|---|
| kube-prometheus-stack | 82.15.1 | ~81.2.2 | Upgrade platform-design |
| Prometheus storage | Default PVC | Thanos long-term (1 year) | platform-design AHEAD |
| Thanos | NO | YES — object storage 1yr retention | platform-design AHEAD |
| Grafana | 12.4.2 chart | present (version unclear) | Align chart version |
| Loki mode | SimpleScalable + S3 | v3.0 app, Fluent Bit shipper | Different architecture — reconcile |
| Loki chart version | 3.7.1 | ~6.51.0 (different chart track) | Different chart family — consolidate |
| Tempo | 2.10.3 single-binary + S3 | ~1.24.3 distributed | Both valid; align on version |
| Pyroscope continuous profiling | NO | YES — 1.18.0 | platform-design AHEAD |
| Fluent Bit log shipper | NO | YES | platform-design AHEAD |
| AlertManager → Slack | YES — configured in kube-prometheus-stack values | NO explicit config visible | Add to platform-design |
| ServiceMonitors on all system components | YES | PARTIAL | Add to remaining components |
| Grafana dashboards as code | YES | YES — `monitoring/dashboards/` | Aligned |
| Centralized observability account | YES — Shared account | NO — per-cluster observability | Architectural difference |
| CloudWatch alarms module | YES — `modules/cloudwatch-alarms/` | NO | Add to platform-design |
| CloudWatch alarms: billing, EKS, EC2, ALB, S3 | YES — 8 alarms | NO | Add to platform-design |

---

## 6. Networking

| Feature | infra | platform-design | Notes |
|---|---|---|---|
| VPC design | Single region (eu-west-1) | Multi-region (4 EU regions) | platform-design AHEAD |
| Transit Gateway | YES — `_envcommon/transit-gateway.hcl` | YES — `modules/transit-gateway/` | Aligned |
| VPC Endpoints (S3, DynamoDB, SSM, EC2, ECR, STS, SNS, SQS, Logs, CloudWatch) | YES — `_envcommon/vpc-endpoints.hcl` | NO — no vpc-endpoints catalog unit | Missing in platform-design |
| Private hosted zones (qbiq.internal, env.qbiq.internal) | YES — `modules/route53/` | PARTIAL — `catalog/units/route53-resolver/` (resolver only) | Add private hosted zones |
| Custom DNS failover controllers (Go) | NO | YES — `failover-controller/`, `dns-sync/`, `dns-monitor/` | platform-design AHEAD |
| Global Accelerator | NO | YES — `modules/global-accelerator/` | platform-design AHEAD |
| ClusterMesh | NO | YES — `modules/clustermesh-connect/` | platform-design AHEAD |
| RAM share for TGW | YES — `_envcommon/vpc-endpoints.hcl` | YES — `catalog/units/ram-share/` | Aligned |
| VPN connection | NO | YES — `modules/vpn-connection/` | platform-design AHEAD |
| Network policies (Kubernetes) | PARTIAL — monitoring egress only | YES — `network-policies/` dir | platform-design AHEAD |
| WAF | NO | YES — `modules/waf/` | platform-design AHEAD |
| NLB ingress module | YES — `_envcommon` | YES — `modules/nlb-ingress/` | Aligned |

---

## 7. CI/CD

| Feature | infra | platform-design | Notes |
|---|---|---|---|
| Terraform fmt check | YES — `terraform-checks.yml` | YES — `terraform-validate.yml` | Aligned |
| Terragrunt hclfmt check | YES — `terraform-checks.yml` | YES — `terragrunt-validate.yml` | Aligned |
| tflint | YES — `terraform-checks.yml` | NO tflint in CI | Add to platform-design |
| Trivy config scan | YES — `terraform-checks.yml` | NO | Add to platform-design |
| Checkov CIS scan | YES — `terraform-checks.yml` | PARTIAL — Well-Architected only (`well-architected.yml`) | Add CIS framework |
| Terragrunt plan on PR | YES — `terraform-plan.yml` | NO explicit plan workflow | Add to platform-design |
| Terragrunt apply workflow | YES — `terraform-apply.yml` | NO apply workflow | Add to platform-design |
| Container image build + ECR push | YES — `build-and-push.yml` | YES — `container-build.yml` | Aligned |
| Helm chart validation | NO | YES — `helm-validate.yml` | platform-design AHEAD |
| Kubernetes manifest validation | NO | YES — `k8s-validate.yml` | platform-design AHEAD |
| Secret scanning | NO | YES — `secret-scan.yml` | platform-design AHEAD |
| Version manifest validation | NO | YES — `version-manifest-validate.yml` | platform-design AHEAD |
| YAML lint | NO | YES — `yaml-lint.yml` | platform-design AHEAD |
| Well-Architected compliance check | NO | YES — `well-architected.yml` | platform-design AHEAD |
| Go CI (custom controllers) | NO | YES — `go-ci.yml` | platform-design AHEAD |
| Auto-generated DEPLOYMENTS.md | NO | YES — `generate-inventory.yml` | platform-design AHEAD |
| Kargo progressive delivery | NO | YES — GitOps promotion via Kargo | platform-design AHEAD |
| GitHub OIDC (keyless CI auth) | YES — 3 role types (terraform/readonly/ecr-push) | NO — no GitHub OIDC catalog unit | Add to platform-design |
| Version pinning in CI (TF/TG versions) | YES — env vars from versions.hcl | PARTIAL — Terraform version in workflow only, TG not pinned | Align to versions file |

---

## 8. Cost Optimization

| Feature | infra | platform-design | Notes |
|---|---|---|---|
| Auto-shutdown Lambda (dev, EventBridge, 19:00 stop / 07:30 start) | YES — `modules/auto-shutdown/` | NO | Missing in platform-design |
| Karpenter dev spot-only NodePool | YES | PARTIAL — spot_percentage option, not enforced in dev | Enforce in dev |
| Karpenter business-hours scale-to-zero (dev) | YES — `nodepool-default.yaml` schedule | NO | Add schedule to dev NodePool |
| Budgets module (per-account alerts) | YES — `modules/budgets/` | NO — no budgets module | Add to platform-design |
| CloudWatch billing alarm (management account) | YES — `modules/cloudwatch-alarms/` | NO | Add to platform-design |
| Karpenter consolidation policy | YES — `WhenEmptyOrUnderutilized` | YES | Aligned |
| Multi-arch (ARM64/Graviton) for cost reduction | NO | YES — `architectures` variable | platform-design AHEAD |
| gp3 storage enforcement (checkov-policies) | NO explicit | YES — `wa_cost_gp3_storage.json` | platform-design AHEAD |
| RDS module (managed DB vs self-managed) | NO | YES — `modules/rds/` | platform-design AHEAD |
| ElastiCache module | NO | YES — `modules/elasticache/` | platform-design AHEAD |
| Hetzner nodes (cost arbitrage) | NO | YES | platform-design AHEAD |

---
