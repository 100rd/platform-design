# Synchronization Roadmap: infra → platform-design

> Generated: 2026-04-05
> Source: `project/infra` (qbiq-ai/infra — production source of truth)
> Target: `project/platform-design`
>
> Effort scale: Low = <0.5 day | Medium = 0.5–2 days | High = 2–5 days
> Risk scale: Low = config-only, no behavioral change | Medium = behavioral change, reversible | High = breaking change, blast radius >1 account

---

## Phase 1 — Critical Security and Compliance

These items represent gaps where platform-design has **no equivalent** to infra's production-hardened controls. Each has direct CIS AWS Foundations Benchmark or compliance implications. They must be added before platform-design is used in production.

---

### 1.1 CIS Checkov + Trivy in CI

**Why critical**: platform-design's CI only runs Well-Architected checkov rules. Infra enforces 90+ CIS AWS Foundations Benchmark v3.0 rules on every PR. Without this, PCI-DSS and CIS violations in new modules will ship undetected.

| | |
|---|---|
| Source file (infra) | `.github/workflows/terraform-checks.yml` (trivy + checkov jobs) |
| Source config (infra) | `.checkov.yml` |
| Target file (platform-design) | `.github/workflows/terraform-validate.yml` — add `trivy` and `checkov-cis` jobs |
| Also create | `.checkov.yml` at repo root with CIS framework config |
| Effort | Low |
| Risk | Low — CI-only, no infrastructure change |

**Specific actions**:
- Copy the `trivy` job from infra's `terraform-checks.yml` into platform-design's CI. Point it at `terraform/modules/` and `catalog/`.
- Add a `checkov-cis` job alongside the existing `well-architected.yml` checkov job. Use `framework: terraform` with `check: CKV_AWS_*` rather than custom policy directory.
- Copy `.checkov.yml` from infra and adjust paths to match platform-design's module layout (`terraform/modules/` vs root-level `modules/`).
- Retain the existing `well-architected.yml` workflow — it runs custom checkov policies that complement CIS, not replace it.

---

### 1.2 IAM Baseline: Access Analyzer, S3 Block, EBS Encryption

**Why critical**: platform-design's `iam-baseline` module only manages the password policy and MFA enforcement. Infra's version adds three additional account-level controls required by CIS 2.1.5 (S3 public access block), CIS 2.2.1 (EBS encryption by default), and CIS 1.20 (IAM Access Analyzer). These are one-line Terraform resources with no operational risk.

| | |
|---|---|
| Source file (infra) | `modules/iam-baseline/main.tf` — resources: `aws_accessanalyzer_analyzer`, `aws_s3_account_public_access_block`, `aws_ebs_encryption_by_default`, `aws_ebs_default_kms_key` |
| Source variables (infra) | `modules/iam-baseline/variables.tf` — `analyzer_type`, `ebs_kms_key_arn` |
| Target file (platform-design) | `terraform/modules/iam-baseline/main.tf` |
| Target variables (platform-design) | `terraform/modules/iam-baseline/variables.tf` |
| Effort | Low |
| Risk | Low — account-level defaults, no resource deletion |

**Specific actions**:
- Add `aws_accessanalyzer_analyzer.org` (type=ORGANIZATION, deploy in management account) and `aws_accessanalyzer_analyzer.account` (type=ACCOUNT, deploy in all other accounts). Wire via `var.analyzer_type`.
- Add `aws_s3_account_public_access_block` with all four flags set to `true`.
- Add `aws_ebs_encryption_by_default` and optional `aws_ebs_default_kms_key`.
- Update `catalog/units/iam-baseline/terragrunt.hcl` to pass `analyzer_type` per account: ORGANIZATION in management, ACCOUNT elsewhere.

---

### 1.3 Missing SCPs: deny-guardduty-changes, deny-s3-public, require-ebs-encryption, deny-all-suspended

**Why critical**: platform-design's SCP module is missing four of infra's seven SCPs. `deny-guardduty-changes` prevents anyone from disabling the organization's threat detection. `deny-s3-public` and `require-ebs-encryption` apply root-level guardrails. `deny-all-suspended` is needed for the quarantine OU pattern.

| | |
|---|---|
| Source file (infra) | `modules/scps/main.tf` — resources: `deny_guardduty_changes`, `deny_s3_public`, `require_ebs_encryption`, `deny_all_suspended` |
| Target file (platform-design) | `terraform/modules/scps/main.tf` |
| Also update | `terraform/modules/scps/variables.tf` to add `suspended_ou_id` input |
| Effort | Low |
| Risk | Medium — SCPs affect all accounts in the OU; test in dev OU first |

**Specific actions**:
- Copy the four missing `aws_organizations_policy` and `aws_organizations_policy_attachment` resources verbatim from infra.
- For `deny-s3-public` and `require-ebs-encryption`, attach at root level (all accounts), mirroring infra's attachment strategy.
- For `deny-guardduty-changes`, attach at the Workloads OU level.
- For `deny-all-suspended`, add an input variable `suspended_ou_id` and attach only when non-empty (the OU must exist first — see 1.4).
- Review the region-restriction SCP in platform-design: infra adds exemptions for `OrganizationAccountAccessRole` (for global IAM/ACM calls) and `qbiq-terraform-*` roles. Apply the same pattern to avoid breaking Terraform workflows that operate on global services.

---

### 1.4 Suspended / Quarantine OU

**Why critical**: Without a Suspended OU, there is no safe holding area for compromised or decommissioned accounts. Infra treats this as a security control, not just organizational hygiene.

| | |
|---|---|
| Source file (infra) | `modules/organizations/main.tf` — `aws_organizations_organizational_unit.suspended` |
| Target file (platform-design) | `terraform/modules/organization/main.tf` |
| Effort | Low |
| Risk | Low — adding an OU with no accounts is non-destructive |

**Specific actions**:
- Add `aws_organizations_organizational_unit.suspended` with `name = "Suspended"`.
- Export `suspended_ou_id` from the module's `outputs.tf`.
- Wire into the SCPs module input (Phase 1.3).
- Document the "move account here when compromised" runbook in `docs/RUNBOOKS.md`.

---

### 1.5 GitHub OIDC (Keyless CI Authentication)

**Why critical**: Without GitHub OIDC, CI workflows must use long-lived IAM access keys stored as GitHub secrets. This violates the principle of least privilege and creates a credential rotation burden. Infra uses three role types: terraform (apply), readonly (plan), ecr-push (image builds).

| | |
|---|---|
| Source file (infra) | `modules/github-oidc/main.tf` — three `iam-github-oidc-role` module calls |
| Target (platform-design) | Create `catalog/units/github-oidc/terragrunt.hcl` pointing to a new `terraform/modules/github-oidc/` module |
| Effort | Medium |
| Risk | Low — additive, existing keys can be removed once OIDC roles are validated |

**Specific actions**:
- Create `terraform/modules/github-oidc/` mirroring infra's module: `iam-github-oidc-provider` plus three `iam-github-oidc-role` instances (terraform, readonly, ecr-push).
- Scope the terraform role to the target branch (`refs/heads/main`) and the repository path.
- Create `catalog/units/github-oidc/terragrunt.hcl`.
- Deploy in management account and all workload accounts.
- Update CI workflows to use `aws-actions/configure-aws-credentials` with `role-to-assume` instead of static keys.

---

### 1.6 KMS prevent_destroy Lifecycle

**Why critical**: Accidental KMS key deletion causes irreversible data loss for all resources encrypted with that key (EKS secrets, S3 objects, RDS snapshots). Infra enforces `lifecycle { prevent_destroy = true }` on all KMS keys.

| | |
|---|---|
| Source file (infra) | `modules/kms/main.tf` — `lifecycle { prevent_destroy = true }` block |
| Target file (platform-design) | `terraform/modules/kms/main.tf` |
| Effort | Low |
| Risk | Low — prevents destruction but allows all other operations |

**Specific actions**:
- Add `lifecycle { prevent_destroy = true }` to `aws_kms_key.this` in platform-design's KMS module.
- Verify the platform-design KMS module already enables `enable_key_rotation = true` (it does — confirmed via module code).

---

### 1.7 All Secrets via ESO (Nothing in Git)

**Why critical**: platform-design has ESO deployed but some system components (ArgoCD admin password, Grafana credentials) may not yet route through ExternalSecret objects backed by Secrets Manager. Infra has explicit ExternalSecret manifests for every credential.

| | |
|---|---|
| Source files (infra) | `k8s/system/argocd/external-secret.yaml`, `k8s/system/kube-prometheus-stack/grafana-externalsecret.yaml`, `k8s/system/loki/loki-externalsecret.yaml` |
| Target (platform-design) | Audit `argocd/`, `k8s/` for any hardcoded credentials; create ExternalSecret manifests for each |
| Effort | Medium |
| Risk | Medium — requires Secrets Manager entries to exist before apply |

**Specific actions**:
- Audit all Helm values files and Kubernetes manifests in `argocd/`, `k8s/`, `helm/` for any `stringData`, `data`, or base64-encoded secrets.
- For each credential found, create an ExternalSecret referencing the platform-design ClusterSecretStore.
- Follow the naming pattern from infra: `<component>-secret` → Secrets Manager path `platform/<env>/<component>/<key>`.

---

## Phase 2 — Version Upgrades

Bring platform-design up to infra's proven-stable versions. All items in this phase are version bumps in existing components — no new modules required.

---

### 2.1 External Secrets Operator: v0.14.1 → 2.2.0

**Why first**: This is the most critical version gap. ESO 0.14.x uses the `externalsecrets.io/v1beta1` API which is deprecated. ESO 2.x promotes to `v1` and changes field names. Upgrading after other components are in place is harder.

| | |
|---|---|
| Source (infra) | `versions.hcl` → `external_secrets = "2.2.0"` |
| Target files (platform-design) | `DEPLOYMENTS.md` (shows `v0.14.1`); all ArgoCD `Application` manifests referencing ESO chart |
| File to update | `argocd/bootstrap/applicationsets/infra-appset.yaml` or equivalent ESO app manifest |
| Also update | Any `ExternalSecret` manifests using `v1beta1` API — must migrate to `v1` |
| Effort | High |
| Risk | High — API version change; run in dev first, validate all ExternalSecrets resolve, then promote |

**Migration steps**:
1. Update chart version to `2.2.0` in the ArgoCD Application for ESO.
2. Update all ExternalSecret manifests from `apiVersion: external-secrets.io/v1beta1` to `v1`.
3. Verify field renames: `remoteRef.key` structure is unchanged in v1 but confirm `creationPolicy` behavior.
4. Test in dev, validate all secrets sync, then promote.

---

### 2.2 EKS Cluster: 1.29/1.34 → 1.35

| | |
|---|---|
| Source (infra) | `versions.hcl` → `eks_cluster_version = "1.35"` |
| Target files (platform-design) | `terraform/modules/eks/variables.tf` — default cluster version; `versions/dev/versions.yaml` |
| Effort | High |
| Risk | High — EKS minor version upgrades require node group draining; must be sequential (cannot skip versions) |

**Migration steps**:
1. Upgrade dev from 1.29 → 1.30 → 1.31 → ... → 1.35 sequentially.
2. For each version: plan, upgrade control plane, upgrade managed node groups, validate workloads.
3. Update `versions/dev/versions.yaml`, `versions/staging/versions.yaml`, `versions/prod/versions.yaml` progressively.
4. Update the default in `terraform/modules/eks/variables.tf` only after all envs are on 1.35.

---

### 2.3 Cilium: 1.17.1 → 1.19.2

| | |
|---|---|
| Source (infra) | `versions.hcl` → `cilium = "1.19.2"` |
| Target files (platform-design) | `DEPLOYMENTS.md` (shows `1.17.1`); ArgoCD Application for Cilium |
| Effort | Medium |
| Risk | Medium — CNI upgrades require rolling restart of all pods; test in dev |

---

### 2.4 Karpenter: 1.8.1 → 1.10.0

| | |
|---|---|
| Source (infra) | `versions.hcl` → `karpenter = "1.10.0"` |
| Target files (platform-design) | `DEPLOYMENTS.md`; Karpenter ArgoCD Application manifest; `terraform/modules/karpenter/` |
| Also check | NodePool API compatibility between 1.8 and 1.10 (both use `karpenter.sh/v1`) |
| Effort | Low |
| Risk | Low — patch-level upgrade within same API version |

---

### 2.5 cert-manager: 1.17.2 → 1.20.1

| | |
|---|---|
| Source (infra) | `versions.hcl` → `cert_manager = "1.20.1"` |
| Target files (platform-design) | cert-manager ArgoCD Application manifest in `argocd/bootstrap/` |
| Effort | Low |
| Risk | Low — minor version upgrade |

---

### 2.6 AWS LB Controller: 3.0.0 → 3.1.0

| | |
|---|---|
| Source (infra) | `versions.hcl` → `aws_load_balancer_controller = "3.1.0"` |
| Target files (platform-design) | `DEPLOYMENTS.md` (shows `3.0.0`); ArgoCD Application manifest |
| Effort | Low |
| Risk | Low |

---

### 2.7 kube-prometheus-stack: ~81.2.2 → 82.15.1

| | |
|---|---|
| Source (infra) | `versions.hcl` → `kube_prometheus_stack = "82.15.1"` |
| Target files (platform-design) | prometheus-stack ArgoCD Application manifest |
| Effort | Low |
| Risk | Low — but review release notes for breaking values changes between 81 and 82 |

---

### 2.8 Loki: Reconcile Chart Track

**Context**: infra uses Loki chart 3.7.1 from `grafana/loki`. platform-design shows `loki-stack` app version 3.0 via chart `6.51.0` — this appears to be the `grafana/loki` chart major track 6.x which has different values structure than the 3.x track infra uses.

| | |
|---|---|
| Source (infra) | `versions.hcl` → `loki = "3.7.1"`, SimpleScalable mode, S3 backend |
| Target files (platform-design) | loki-stack ArgoCD Application; any Loki Helm values files |
| Decision needed | Determine if platform-design intentionally uses chart 6.x. If yes, document the divergence. If no, align to 3.7.1 |
| Effort | Medium |
| Risk | Medium — values schema differs between chart tracks; migration may require Loki data path changes |

---

### 2.9 Tempo: 1.24.3 (distributed) → 2.10.3

| | |
|---|---|
| Source (infra) | `versions.hcl` → `tempo = "2.10.3"`, single-binary mode |
| Target files (platform-design) | tempo ArgoCD Application manifest |
| Decision needed | infra uses single-binary mode; platform-design uses distributed. Distributed is valid for higher scale. Align chart version to 2.10.3 regardless of mode |
| Effort | Medium |
| Risk | Medium — Tempo 2.x has breaking changes in TraceQL and storage config from 1.x |

---

### 2.10 Terraform and Terragrunt: Pin to Exact Versions

**Why this matters**: platform-design uses `>= 1.11.0` for Terraform and `>= 0.68.0` for Terragrunt. This allows any future minor/patch version to run. Infra pins exact versions to eliminate version drift between developers and CI.

| | |
|---|---|
| Source (infra) | `versions.hcl` → `terraform_version = "1.14.8"`, `terragrunt_version = "0.99.5"` |
| Target file (platform-design) | `terragrunt/root.hcl` — `terragrunt_version_constraint` and `generate "versions"` block |
| Effort | Low |
| Risk | Low |

**Specific actions**:
- In `terragrunt/root.hcl`, change `terragrunt_version_constraint = ">= 0.68.0"` to `= "0.99.5"` (exact pin).
- In the `generate "versions"` block, change `required_version = ">= 1.11.0"` to `= "1.14.8"`.
- Update `terragrunt/mise.toml` (if present) to lock the same versions.

---

## Phase 3 — Platform Enhancement Patterns

These are design patterns from infra that platform-design should adopt. They are not blocking (platform-design works without them) but represent production-hardened patterns.

---

### 3.1 VPC Endpoints (PrivateLink)

**Why adopt**: Without VPC endpoints, traffic to S3, ECR, SSM, CloudWatch, STS, and other AWS services traverses the public internet or requires NAT Gateway (cost + security exposure). Infra deploys 10+ endpoints per VPC.

| | |
|---|---|
| Source (infra) | `_envcommon/vpc-endpoints.hcl` — uses `terraform-aws-modules/vpc//modules/vpc-endpoints` v6.6.0 |
| Target (platform-design) | Create `catalog/units/vpc-endpoints/terragrunt.hcl` |
| Also add | Unit to `terragrunt/dev/eu-west-1/platform/terragrunt.stack.hcl` and equivalent per-region stacks |
| Effort | Medium |
| Risk | Low — additive; endpoints do not break existing connectivity |

**Endpoints to include** (per infra's list): `s3` (Gateway), `dynamodb` (Gateway), `ssm`, `ssmmessages`, `ec2messages`, `ec2`, `ecr.api`, `ecr.dkr`, `sts`, `sns`, `sqs`, `logs`, `monitoring`.

---

### 3.2 AWS Config CIS Managed Rules

**Why adopt**: platform-design's Config module records changes but does not evaluate compliance. Infra's `config-org` module adds 10 CIS-required managed rules (MFA on root, password policy, CloudTrail enabled, VPC flow logs, etc.).

| | |
|---|---|
| Source (infra) | `modules/config-org/main.tf` — `aws_config_config_rule` resources for CIS rules |
| Target (platform-design) | `terraform/modules/aws-config/main.tf` — add `aws_config_config_rule` blocks |
| Effort | Medium |
| Risk | Low — Config rules detect but do not remediate |

**Rules to add**: `root-account-mfa-enabled`, `iam-password-policy`, `iam-user-mfa-enabled`, `access-keys-rotated`, `cloud-trail-enabled`, `cloud-trail-log-file-validation-enabled`, `cloud-trail-encryption-enabled`, `vpc-flow-logs-enabled`.

---

### 3.3 Auto-Shutdown Lambda (Dev Cost Control)

**Why adopt**: platform-design has no mechanism to stop dev EC2/EKS nodes outside business hours. Infra's EventBridge + Lambda approach stops nodes at 19:00 UTC and restarts at 07:30 UTC Mon–Fri.

| | |
|---|---|
| Source (infra) | `modules/auto-shutdown/main.tf` — Lambda + EventBridge Scheduler, tag-based EC2 stop/start |
| Target (platform-design) | Create `terraform/modules/auto-shutdown/` (copy infra module) |
| Also create | `catalog/units/auto-shutdown/terragrunt.hcl` |
| Add to stack | `terragrunt/dev/eu-west-1/platform/terragrunt.stack.hcl` — add `unit "auto-shutdown"` |
| Effort | Low |
| Risk | Low — opt-in via `AutoShutdown=true` tag; no change unless tag is applied |

---

### 3.4 Budgets Module (Per-Account Alerts)

**Why adopt**: No per-account spend visibility means cost overruns in dev or staging go undetected until the monthly bill.

| | |
|---|---|
| Source (infra) | `modules/budgets/main.tf` |
| Target (platform-design) | Create `terraform/modules/budgets/` + `catalog/units/budgets/terragrunt.hcl` |
| Effort | Low |
| Risk | Low — monitoring only, no infrastructure change |

---

### 3.5 CloudWatch Alarms Module

**Why adopt**: platform-design has no CloudWatch alarms. Infra has 8 alarms covering billing, EKS API errors, EC2 CPU/memory, ALB 5xx, and S3 state bucket size.

| | |
|---|---|
| Source (infra) | `modules/cloudwatch-alarms/main.tf` |
| Target (platform-design) | Create `terraform/modules/cloudwatch-alarms/` + `catalog/units/cloudwatch-alarms/terragrunt.hcl` |
| Effort | Low |
| Risk | Low |

---

### 3.6 ArgoCD SSO via Dex + IAM Identity Center

**Why adopt**: platform-design's ArgoCD module has `enable_dex = false` by default and no IAM Identity Center OIDC configuration. This means all ArgoCD access is via local admin accounts, which is not acceptable for production.

| | |
|---|---|
| Source (infra) | `k8s/system/argocd/values.yaml` — `dex.config` block with IAM Identity Center SAML app + OIDC connector |
| Target (platform-design) | `terraform/modules/argocd/variables.tf` — expose Dex config as variable; `argocd/cluster-envs/prod/` — add values patch |
| Also add | ExternalSecret for Dex OIDC client secret |
| Effort | Medium |
| Risk | Medium — SSO misconfiguration can lock out all users; test in dev with a break-glass admin account |

**Steps**:
1. In `terraform/modules/argocd/main.tf`, expose the Dex config block through a `var.dex_config` string variable.
2. Create an ArgoCD values overlay for prod that enables Dex with IAM Identity Center SAML.
3. Create an ExternalSecret for `argocd-dex-secret` backed by Secrets Manager.
4. Follow infra's RBAC pattern: map IAM IC groups to ArgoCD roles (admin/developer/readonly).

---

### 3.7 ArgoCD Slack Notifications

**Why adopt**: No notifications means silent ArgoCD sync failures. Infra configures AlertManager → Slack and ArgoCD notifications → Slack.

| | |
|---|---|
| Source (infra) | `k8s/system/argocd/values.yaml` — `notifications.triggers`, `notifications.templates`, ESO-backed `slack-token` secret |
| Target (platform-design) | Add notifications block to ArgoCD values in `argocd/cluster-envs/prod/` |
| Also add | ExternalSecret for `argocd-notifications-secret` with `slack-token` |
| Effort | Low |
| Risk | Low |

---

### 3.8 Karpenter Business-Hours Scale-to-Zero (Dev)

**Why adopt**: platform-design's dev Karpenter NodePool has no schedule. Nodes run 24/7. Infra's dev NodePool disrupts at 20:00 UTC and scales back at 07:00 UTC Mon–Fri using `karpenter.sh/v1` `spec.disruption.budgets` with time windows.

| | |
|---|---|
| Source (infra) | `k8s/system/karpenter/nodepool-default.yaml` — `disruption.budgets` with `schedule` field |
| Target (platform-design) | `terraform/modules/karpenter-nodepools/main.tf` — add `schedule` to dev NodePool budget |
| Effort | Low |
| Risk | Low — only affects dev cluster; workloads must tolerate preemption (they should already via Karpenter) |

---

### 3.9 Tagging: Owner, CostCenter, TerragruntPath, Repository

**Why adopt**: platform-design's `root.hcl` generates `Environment`, `ManagedBy`, `Account`, `Region` tags. It is missing `Owner`, `CostCenter`, `TerragruntPath`, and `Repository` which infra includes. These are required for cost allocation and audit tracing.

| | |
|---|---|
| Source (infra) | `terragrunt.hcl` — `default_tags` block including `Owner`, `CostCenter`, `TerragruntPath`, `Repository` |
| Target (platform-design) | `terragrunt/root.hcl` — `generate "provider"` block, `default_tags` section |
| Effort | Low |
| Risk | Low — tag additions are non-breaking |

**Specific actions**:
- Add `Owner`, `CostCenter` to `account.hcl` per account (platform-design's `_org/account.hcl` already has `organization_name` but not cost fields).
- Add `TerragruntPath = path_relative_to_include()` and `Repository = "100rd/platform-design"` to root.hcl provider default_tags.
- Add `Project` tag — currently missing from platform-design (infra sets this from `common.hcl`).

---

### 3.10 PodDisruptionBudgets and Resource Quotas

**Why adopt**: Infra enforces PDBs on all system components and namespace-level resource quotas. This prevents accidental disruption during node rolling and resource starvation across teams.

| | |
|---|---|
| Source (infra) | `k8s/overlays/prod/` PDB patches; namespace quota manifests |
| Target (platform-design) | Add PDB overlays to `argocd/cluster-envs/prod/`; add ResourceQuota manifests per namespace |
| Effort | Medium |
| Risk | Low for PDBs; Medium for quotas (quotas can block deployments if set too tight) |

---

### 3.11 tflint in CI

**Why adopt**: infra runs tflint on every PR to catch module-level issues (deprecated arguments, missing required variables, naming convention violations) that Checkov and Trivy miss.

| | |
|---|---|
| Source (infra) | `.github/workflows/terraform-checks.yml` — `tflint` job with `--recursive` |
| Source config (infra) | `.tflint.hcl` |
| Target (platform-design) | Add `tflint` job to `.github/workflows/terraform-validate.yml`; create `.tflint.hcl` |
| Effort | Low |
| Risk | Low — CI-only |

---

### 3.12 Terragrunt Plan and Apply Workflows

**Why adopt**: platform-design has `terraform-validate.yml` (fmt + validate only) but no plan or apply workflows. infra has `terraform-plan.yml` (PR comment with plan output) and `terraform-apply.yml` (main branch apply with approval gate).

| | |
|---|---|
| Source (infra) | `.github/workflows/terraform-plan.yml`, `.github/workflows/terraform-apply.yml` |
| Target (platform-design) | Create equivalent workflows; adapt for multi-region by parameterizing `ACCOUNT` and `REGION` |
| Effort | Medium |
| Risk | Medium — apply workflow requires careful IAM OIDC scoping |

---

## Phase 4 — Multi-Region Value: Preserve and Enhance

These are features unique to platform-design that represent genuine architectural advances over infra. They should not be removed, and several are candidates for backporting to infra.

---

### 4.1 Keep: Multi-Region Architecture (4 EU Regions)

**Value**: platform-design supports `eu-central-1`, `eu-west-1`, `eu-west-2`, `eu-west-3` via the `terragrunt/dev/eu-{region}/` directory hierarchy. This is the primary differentiation from infra (single region).

**Do not change**: The directory hierarchy, `region.hcl` per region, and the stack per-region deployment model.

**Potential backport to infra**: Document the region.hcl pattern so infra could add a second region if needed.

---

### 4.2 Keep: Kargo Progressive Delivery

**Value**: Kargo 1.2.0 provides GitOps-native promotion through dev → staging → prod with approval gates, image verification, and warehouse/stage abstractions. infra has no equivalent — it relies on manual ArgoCD sync.

**Do not change**: `kargo/projects/`, `kargo/stages/`, `kargo/warehouses/`.

**Enhancement**: Wire Kargo stages to the Phase 3.6 ArgoCD SSO so Kargo UI uses the same IAM Identity Center identities.

---

### 4.3 Keep: Custom DNS Failover Controllers

**Value**: The Go-based `failover-controller/`, `dns-sync/`, and `dns-monitor/` implement multi-region DNS failover logic that AWS Route53 health checks alone cannot handle for the platform's architecture. This is custom IP and not present in infra.

**Do not change**: These controllers and their CRDs.

**Enhancement**: Add ServiceMonitors for `dns-monitor` and `failover-controller` to feed metrics into the prometheus-stack.

---

### 4.4 Keep: Falco Runtime Security

**Value**: Falco provides kernel-level syscall monitoring via eBPF that Checkov and Trivy (static) cannot replicate. This is a material security capability gap in infra.

**Do not change**: `terraform/modules/falco/`.

**Potential backport to infra**: Add a `modules/falco/` and deploy via ArgoCD `k8s/apps/system/falco.yaml` in the infra repo. This would be the highest-value security addition to infra.

---

### 4.5 Keep: Thanos Long-Term Storage

**Value**: Thanos provides 1-year metric retention on S3, indefinite storage for compliance, and multi-cluster query federation. infra's prometheus-stack uses local PVC only (30-day default).

**Do not change**: Thanos deployment, object store config, retention policies.

**Enhancement**: Ensure the Thanos compactor and store gateway have ExternalSecrets for S3 bucket credentials (Phase 1.7 pattern).

**Potential backport to infra**: Add Thanos to infra's shared account kube-prometheus-stack. This is a Medium effort, Medium risk addition that would give infra long-term metric storage for compliance.

---

### 4.6 Keep: Pyroscope Continuous Profiling

**Value**: Continuous profiling surfaces CPU and memory hotspots in production that metrics and traces cannot. infra has no profiling capability.

**Do not change**: `apps/pyroscope/` or equivalent Pyroscope ArgoCD Application.

---

### 4.7 Keep: Multi-Arch Karpenter (ARM64/Graviton)

**Value**: Graviton3 instances offer 20–40% cost reduction for compute-bound workloads at equivalent performance. The `architectures` variable in platform-design's karpenter-nodepools module enables this with no additional infrastructure.

**Do not change**: The `architectures` input variable.

**Enhancement**: Explicitly set `architectures = ["amd64", "arm64"]` in the dev NodePool to build confidence before enabling in prod.

---

### 4.8 Keep: OPA Gatekeeper + Kyverno

**Value**: Platform-design has two layers of admission control. Gatekeeper enforces organizational policy (require labels, prohibit privileged containers). Kyverno enforces mutation defaults (add resource limits, inject sidecars). infra has neither.

**Do not change**: `checkov-policies/` custom rules complement these runtime policies.

**Enhancement**: Document which policies map to which CIS/PCI-DSS controls, creating a compliance traceability matrix.

---

### 4.9 Keep: Auto-Generated DEPLOYMENTS.md

**Value**: The `generate-inventory.yml` workflow produces a single source of truth for every deployed component version. infra has no equivalent — version tracking is manual via `versions.hcl`.

**Do not change**: The `generate-inventory.yml` workflow and `deployments.json` schema.

**Enhancement**: Fix the `DEPLOYMENTS.md` header template — it currently contains a literal `$(date ...)` shell expression that was not evaluated at generation time.

---

### 4.10 Keep: Version Manifests per Environment

**Value**: `versions/dev/versions.yaml`, `versions/staging/versions.yaml`, `versions/prod/versions.yaml` provide per-environment application version pins independent of infrastructure versions. This enables safe, independent promotion of application images.

**Do not change**: The `versions/` directory structure and `VersionManifest` schema.

---

## Summary: Implementation Priority Queue

| Priority | Item | Phase | Effort | Risk |
|---|---|---|---|---|
| P0 | CIS Checkov + Trivy in CI | 1.1 | Low | Low |
| P0 | IAM Access Analyzer + S3 block + EBS encryption | 1.2 | Low | Low |
| P0 | ESO upgrade: v0.14.1 → 2.2.0 | 2.1 | High | High |
| P1 | Missing SCPs (deny-guardduty, deny-s3-public, require-ebs-enc, deny-suspended) | 1.3 | Low | Medium |
| P1 | Suspended OU | 1.4 | Low | Low |
| P1 | GitHub OIDC (keyless CI auth) | 1.5 | Medium | Low |
| P1 | KMS prevent_destroy | 1.6 | Low | Low |
| P1 | EKS upgrade 1.29→1.35 | 2.2 | High | High |
| P1 | All secrets via ESO audit | 1.7 | Medium | Medium |
| P2 | Cilium upgrade 1.17.1→1.19.2 | 2.3 | Medium | Medium |
| P2 | Karpenter upgrade 1.8.1→1.10.0 | 2.4 | Low | Low |
| P2 | VPC Endpoints | 3.1 | Medium | Low |
| P2 | ArgoCD SSO via Dex + IAM IC | 3.6 | Medium | Medium |
| P2 | Tagging: Owner, CostCenter, TerragruntPath, Repository | 3.9 | Low | Low |
| P2 | cert-manager upgrade | 2.5 | Low | Low |
| P2 | AWS LB Controller upgrade | 2.6 | Low | Low |
| P2 | kube-prometheus-stack upgrade | 2.7 | Low | Low |
| P3 | Auto-shutdown Lambda | 3.3 | Low | Low |
| P3 | Budgets module | 3.4 | Low | Low |
| P3 | CloudWatch alarms module | 3.5 | Low | Low |
| P3 | Karpenter business-hours scale-to-zero | 3.8 | Low | Low |
| P3 | ArgoCD Slack notifications | 3.7 | Low | Low |
| P3 | AWS Config CIS managed rules | 3.2 | Medium | Low |
| P3 | Terraform + Terragrunt exact version pins | 2.10 | Low | Low |
| P3 | tflint in CI | 3.11 | Low | Low |
| P3 | Terragrunt plan + apply workflows | 3.12 | Medium | Medium |
| P3 | PodDisruptionBudgets + ResourceQuotas | 3.10 | Medium | Low |
| P4 | Loki chart track reconciliation | 2.8 | Medium | Medium |
| P4 | Tempo 1.24.3 → 2.10.3 | 2.9 | Medium | Medium |
| P4 | WireGuard encryption (Cilium) | — | Low | Medium |
| P4 | Backport Falco to infra | 4.4 | Medium | Low |
| P4 | Backport Thanos to infra | 4.5 | Medium | Medium |
