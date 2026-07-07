# SPEC-05 — Security

> Portable reverse-engineering of this platform's security estate. A senior platform
> team can rebuild the same defense-in-depth posture for a new client from this file
> alone. All client-identifying values are placeholders (see §5); replace them, do not
> invent real account IDs, ARNs, domains, or emails.

## 1. Scope & non-goals

This spec captures the platform's **security controls end to end**: the AWS Organization
guardrail plane (SCPs, RCPs, EC2 declarative policies, break-glass), the multi-account
audit/logging foundation (CloudTrail, Config, GuardDuty, Security Hub, dedicated
`security` and `log-archive` accounts), workload identity (EKS Pod Identity / IRSA with
ABAC), secrets management (External Secrets Operator + Secrets Manager + KMS + automated
rotation), Kubernetes runtime security (default-deny network policy, admission control,
securityContext standards, runtime eBPF observability), and the CI/CD supply-chain +
policy-as-code gates (Checkov, Conftest/OPA, Access Analyzer, Trivy, cosign/SBOM,
Harden-Runner, zizmor). It is organized as a **six-layer defense-in-depth map**:
`org → account → network → cluster → workload → pipeline`.

**Non-goals.** Network topology (VPC/TGW/subnet design) lives in the networking spec;
this spec only references the *security-relevant* slices (data perimeter, inter-VPC
segmentation intent, WAF). Cluster provisioning, GitOps mechanics, cost, and
observability internals live in their own specs and are cross-referenced in §9. This spec
does not cover application-level authnz inside individual services.

## 2. Architecture

### 2.1 Defense-in-depth map (six layers)

```
                        ┌──────────────────────────────────────────────────────────┐
LAYER 0  ORG            │  AWS Organizations (management account)                    │
(preventive,            │   • SCPs  (principal-side) — deny leave-org, root use,     │
 org-wide)              │            region lock, CloudTrail/GuardDuty tamper,       │
                        │            S3-public, unencrypted-EBS, org data perimeter  │
                        │   • RCPs  (resource-side) — deny external principals on    │
                        │            S3/STS/KMS/SecretsManager/SQS                    │
                        │   • EC2 Declarative Policies — IMDSv2, block public AMI/EBS │
                        │   • Break-glass IAM user (prevent_destroy + MFA + alarm)   │
                        └───────────────┬──────────────────────────────────────────┘
                                        │ inherited by every account/OU
        ┌───────────────────────────────┼───────────────────────────────┐
LAYER 1 │ ACCOUNT   security acct        │  log-archive acct   workload accts (dev/…/prod)
(detect,│  • GuardDuty deleg-admin       │  • central log bucket   • CloudTrail→log-archive
 audit) │  • Security Hub (CIS/PCI/FSBP) │    (Object Lock+KMS)     • Config→log-archive
        │  • Config aggregator           │  • VPC Flow / EKS audit  • IAM Identity Center SSO
        └───────────────────────────────┴───────────────────────────────┘
LAYER 2  NETWORK   • default-deny SGs + NACL backstop • TGW segmented route tables
(perimeter)        • WAF (managed rules + rate-limit) on internet-facing serving fronts
                   • Cilium identity-based CiliumClusterwideNetworkPolicy default-deny
LAYER 3  CLUSTER   • Admission: Gatekeeper + Kyverno + ValidatingAdmissionPolicy (VAP)
(admission)        • Pod Security Admission (restricted) • image signature verification
                   • Bottlerocket immutable, read-only-root, SELinux node OS
LAYER 4  WORKLOAD  • EKS Pod Identity (ABAC session tags) / IRSA (legacy)
(identity+data)    • ESO + Secrets Manager + KMS CMK • least-privilege bucket-scoped IAM
                   • securityContext: runAsNonRoot, drop ALL caps, readOnlyRootFS, no-priv-esc
                   • Tetragon eBPF runtime tracing policies
LAYER 5  PIPELINE  • Checkov + Conftest/OPA on plan JSON • Access Analyzer policy-diff gate
(supply chain)     • Trivy + CodeQL + gitleaks + cosign keyless sign + Syft SBOM attest
                   • Harden-Runner egress monitoring • zizmor Actions SAST • SHA-pinned uses:
```

### 2.2 Account topology (security-relevant)

Two dedicated non-workload accounts under the `Security` OU implement separation of duties:

- **`security`** — delegated administrator for GuardDuty, Security Hub, (and Detective /
  Inspector / Macie when enabled); cross-region aggregation home is `{{PRIMARY_REGION}}`.
  Runs no EKS/RDS (`enable_eks = false`, `enable_rds = false`).
- **`log-archive`** — holds the single centralized, immutable log bucket (Object Lock +
  KMS + replication). Every other account ships CloudTrail, Config snapshots, VPC Flow
  Logs, and EKS audit/authenticator logs here via cross-account write policies.

The **management** account owns the Organization, all guardrail policies, the org
CloudTrail trail, the KMS keys, the break-glass user, and IAM Identity Center.

### 2.3 Policy evaluation order (the mental model reviewers must hold)

For any API call, AWS evaluates in this order — an explicit `Deny` at any layer is final:

```
Organizations SCP  →  Resource-based policy  →  Identity-based (IAM) policy
        │                                               │
        └────────────►  Resource Control Policy (RCP) ◄─┘   (RCP evaluates AFTER the others)
```

SCPs bound what a **caller inside the org** may do; RCPs bound what an **external
principal** may do to *our* resources. They are the two halves of the AWS data perimeter.

## 3. Decision record

| Decision | Rationale | Trade-off accepted | Source ADR |
|---|---|---|---|
| Canonical 5-OU split (Production / Non-Production / Deployments / Suspended / Sandbox) layered over functional OUs (Security / Infrastructure / Workloads) | AFT vending and sandboxes need distinct SCP profiles without touching workload OUs | Alias mapping (`Prod`↔`Production`) adds cognitive load; +12 live SCP attachments; chose doc-mapping over a state-migrating rename | ADR-0001 OU split |
| SCP guardrail set attached per-OU + broad SCPs at root to dodge the 5-SCP-per-target cap | AWS hard-limits 5 SCPs/target incl. inherited `FullAWSAccess`; broad controls (S3-public, EBS-encryption, data-perimeter) sit at root | Root slots are scarce (data-perimeter burns one); exemption ARNs must be maintained | ADR-0001, ADR-0017 |
| EKS public API endpoint kept, gated by an **explicit CIDR allow-list** variable (fail-closed `[]`, never implicit `0.0.0.0/0`); prod private-only | CI runners have dynamic IPs and need API access without bastion/VPN; externalizing the list makes the open default visible in review | Non-prod may carry a documented `0.0.0.0/0`; accepted risk vs NAT-EIP/bastion cost | ADR-0010 |
| Break-glass IAM user protected by `prevent_destroy` **and** `force_destroy = false`, MFA-enforced, usage-alarmed | `force_destroy` only fails at apply; `prevent_destroy` errors at plan before any API call — last-resort access must survive `terraform destroy` | `terraform destroy` always fails while a break-glass user exists until the lifecycle block is removed via reviewed PR (intentional friction) | ADR-0011 |
| Deny-by-default inter-VPC model: segmented TGW route tables, default-deny SGs, prod NACL backstop, optional inspection VPC (Network Firewall) | Merging estates + cross-estate VPN could create a transitive dev→prod path; TGW route tables are the single reviewed segmentation point | More route/SG/NACL bookkeeping; VPN sub-pool membership is change-controlled | ADR-0013 |
| Tier-1 CI supply-chain hardening: dep-scan, secrets-scan, SAST, image signing, manifest validation, smoke — **zero new long-lived secrets** | ADR-0015 baseline (Trivy OS scan + SBOM) misses app-dep CVEs, secrets, SAST, provenance; keyless OIDC avoids key sprawl | +4–7 min/build (SAST long pole); more moving parts | ADR-0016 |
| Resource-side data perimeter (**RCPs**) + EC2 Declarative Policies + full-IAM SCPs + Access Analyzer CI gate | Perimeter was principal-side only; nothing protected resources from external principals; root SCP slots were full; policies were reviewed by eye | Two new policy types + new eval-order mental model; Access Analyzer checks are a paid feature | ADR-0017 |
| **EKS Pod Identity** as default workload identity (IRSA → legacy), least-privilege via **ABAC** session tags | IRSA trust is per-cluster (non-portable roles, role sprawl); Pod Identity reuses one role across clusters; ABAC scopes by injected tags | Coexistence window; ABAC is condition-heavy (wrong tag key/case is a new bug class); Fargate stays on IRSA | ADR-0018 |
| **Kyverno + ValidatingAdmissionPolicy** alongside Gatekeeper; image-signature verification at **admission** (not GitOps) | ArgoCD can only verify GnuPG-signed git commits, not cosign/OCI signatures; VAP runs in-process via CEL (no webhook) for trivial checks | Two admission engines + VAP to operate; `verifyImages` adds admission latency | ADR-0020 |
| CI runtime hardening: **zizmor** (Actions SAST) + **Harden-Runner** (runner egress monitoring), audit → block | Matches the 2025 `tj-actions/changed-files` class: workflows were never SAST-linted; runners had zero runtime egress visibility | Block mode needs a maintained egress allow-list; zizmor surfaces a backlog | ADR-0022 |
| ArgoCD operational hardening (PreDelete hooks, shallow clone, server-side diff/apply, progressive ApplicationSet rollout) on the running 3.3.6 | All four ship in the current version for free; fix deletion ordering, repo-server cost, spurious `OutOfSync`, and the missing dev→prod rollout gradient | Server-side apply changes field-ownership semantics teams must learn | ADR-0024 |
| **Bottlerocket** as EKS node OS (immutable, read-only-root, SELinux-enforcing, no SSH/shell/pkg-mgr) | AL2023 default carries a large mutable host attack surface invisible to in-cluster controls | No SSH debugging (admin container, disabled by default); two-volume layout; FIPS/GPU are separate variants | ADR-0030 |
| Automated secret rotation: Secrets Manager rotation Lambda + ESO auto-refresh of pods | Static long-lived secrets are standing-credential risk; PCI-DSS 3.6.4/8.3.9 require a cryptoperiod; rotated value must reach running pods | Rotation Lambda is real code to own (VPC ENIs, RDS reachability); `refreshInterval` adds `GetSecretValue` cost | ADR-0031 |
| Control Tower landing zone + AFT for account vending | AFT hard-requires a deployed Control Tower landing zone (the load-bearing prerequisite ADR-0017 omitted) | Migrating a live populated org; +2 management accounts; home-region lock-in | ADR-0035 |
| SOC2 posture: GCP org-policy parity, keyless cross-cloud WIF, control-to-evidence matrix, ML on-call | Controls were AWS/K8s-heavy and never mapped to an audit framework; GCP had no deny-list plane; cross-cloud identity was static-key | Org-policy is high-blast-radius; WIF setup non-trivial; matrix must be maintained | ADR-0040 |
| WAF-fronted, model-aware inference serving front (Gateway API Inference Extension + Endpoint Picker on Envoy Gateway) | A naive L4 `ClusterIP` LB is model/cache-blind; WAF adds managed rule groups + per-client rate limiting at the public edge | Inference extension is young (CRD pin required); WAF may false-positive on long prompts (start in count mode) | ADR-0047 |

## 4. Implementation blueprint

### 4.1 Directory layout (security-bearing paths)

```
terragrunt/_org/                      # Organization + guardrail plane (management acct)
  account.hcl                         #   mgmt account id, org name, member accounts
  _global/organization/               #   OU tree + member accounts
  _global/scps/                       #   principal-side SCPs (→ modules/scps)
  _global/rcps/                       #   resource-side RCPs (→ modules/rcps), staged rollout
  _global/break-glass-user/           #   emergency IAM user (→ modules/break-glass-user)
  _global/cloudtrail/                 #   org-wide trail → log-archive bucket
  _global/guardduty-org/              #   all protection plans, delegated admin
  _global/security-hub/               #   CIS + PCI-DSS + AWS FSBP standards
  _global/aws-config/                 #   recorder incl. global (IAM) resources
  _global/iam-baseline/               #   password policy + enforce-MFA + root-key Config rule
  _global/sso/                        #   IAM Identity Center permission sets + assignments
terragrunt/security/account.hcl       # security account (GuardDuty/SecurityHub deleg-admin home)
terragrunt/log-archive/account.hcl    # centralized immutable log bucket
terraform/modules/scps|rcps|break-glass-user|iam-baseline|waf|secret-rotation|...
checkov-policies/*.json               # custom Checkov Well-Architected checks
tests/opa/*.rego                      # Conftest/OPA policies (run on plan JSON)
network-policies/                     # baseline K8s NetworkPolicy + Cilium clusterwide deny
apps/infra/{gatekeeper,kyverno,tetragon,cluster-secret-store}/   # runtime security
catalog/units/pod-identity-*/         # Pod Identity associations (ESO, LB-ctrl, ...)
.github/workflows/{conftest-opa,policy-access-check,container-build}.yml
.github/actions/{harden-runner,cosign-sign,syft-sbom,sast-codeql,secrets-scan}/
docs/break-glass-procedure.md         # the runbook §4.5 distills
```

### 4.2 Guardrail inventory (control · layer · enforced by · file)

| Control | Layer | Enforced by | File |
|---|---|---|---|
| Deny leave organization | org | SCP `DenyLeaveOrganization` (all non-root OUs) | `terraform/modules/scps/main.tf` |
| Deny root user in member accounts | org | SCP `DenyRootAccountUsage` (`workload_ou_names`: NonProd, Prod, Sandbox) | `modules/scps/main.tf` |
| Region lock (EU + us-east-1 globals) | org | SCP `RestrictToEURegions` (exempts OAAR + `{{PROJECT}}-terraform-*`) | `modules/scps/main.tf` |
| Deny CloudTrail tamper (no exemptions) | org | SCP `DenyDisableCloudTrail` | `modules/scps/main.tf` |
| Deny GuardDuty tamper (no exemptions) | org | SCP `DenyGuardDutyChanges` | `modules/scps/main.tf` |
| Deny S3 public-access changes (terraform-exempt) | org (root) | SCP `DenyS3PublicAccess` | `modules/scps/main.tf` |
| Require EBS encryption (no exemptions) | org (root) | SCP `RequireEBSEncryption` (`ec2:Encrypted=false`) | `modules/scps/main.tf` |
| Identity perimeter (`aws:PrincipalOrgID`) | org (root) | SCP `DataPerimeter-DenyExternalPrincipals` | `modules/scps/main.tf` |
| Quarantine suspended accounts | org | SCP `DenyAllSuspended` (OAAR carve-out) | `modules/scps/main.tf` |
| Resource perimeter on S3/STS/KMS/SecretsMgr/SQS | org | RCP `RCP-DataPerimeter-DenyExternalAccess` (staged→root) | `modules/rcps/main.tf` |
| IMDSv2 required, block public AMI/EBS snapshot | org | EC2 Declarative Policies (retires `require_imdsv2` SCP) | ADR-0017 (pending) |
| Break-glass destroy protection + MFA + alarm | org | `prevent_destroy`, deny-without-MFA inline policy, CloudWatch alarm | `modules/break-glass-user/main.tf` |
| Root access-key detection | account | Config rule `IAM_ROOT_ACCESS_KEY_CHECK` | `modules/iam-baseline/main.tf` |
| Strong password policy + enforce-MFA | account | `aws_iam_account_password_policy` + `enforce_mfa` policy | `modules/iam-baseline/main.tf` |
| Org CloudTrail (KMS-encrypted) → log-archive | account | `modules/cloudtrail` (depends on org + KMS) | `_org/_global/cloudtrail/` |
| Config recorder (all + global IAM) → log-archive | account | `modules/aws-config` | `_org/_global/aws-config/` |
| GuardDuty all plans (S3/EKS audit+runtime/EBS malware/RDS/Lambda) | account | `modules/guardduty-org`, delegated admin | `_org/_global/guardduty-org/` |
| Security Hub (CIS + PCI-DSS + AWS FSBP) | account | `modules/security-hub` (after GuardDuty+Config) | `_org/_global/security-hub/` |
| Centralized immutable logs (Object Lock+KMS+replication) | account | `_envcommon/centralized-logging.hcl` | `terragrunt/log-archive/` |
| Least-privilege SSO permission sets | account | IAM Identity Center (`PT4H`/`PT8H` sessions, prod = ReadOnly for engineers) | `_org/_global/sso/` |
| K8s default-deny ingress+egress | network | `NetworkPolicy default-deny-all` | `network-policies/default-deny-all.yaml` |
| Cilium identity-based clusterwide deny | network | `CiliumClusterwideNetworkPolicy default-deny-<ns>` | `network-policies/gpu-inference/00-default-deny.yaml` |
| WAF (managed rules + rate limit + logging) | network | `aws_wafv2_web_acl` (`rate_limit` default 2000/5-min) | `terraform/modules/waf/main.tf` |
| Require securityContext (runAsNonRoot, no priv-esc, non-privileged) | cluster | Gatekeeper `K8sRequireSecurityContext` (enforce=deny) | `apps/infra/gatekeeper/templates/constraints/require-security-context.yaml` |
| Image signature verification, block `:latest`, require limits | cluster | Kyverno `ImageValidatingPolicy` + VAP (CEL) | `apps/infra/kyverno/templates/vap/` |
| Immutable node OS | cluster | Bottlerocket (`ami_family`/`amiSelectorTerms`) | `catalog/units/*-nodes`, `*-nodepools` |
| Workload identity (Pod Identity + ABAC) | workload | `PodIdentityAssociation` + `aws:PrincipalTag/*` conditions | `catalog/units/pod-identity-*/` |
| Secrets from Secrets Manager (no plaintext in Git) | workload | ESO `ClusterSecretStore` + `ExternalSecret` | `apps/infra/cluster-secret-store/` |
| Automated secret rotation | workload | Secrets Manager rotation Lambda + ESO refresh | `terraform/modules/secret-rotation/` |
| Runtime eBPF tracing (exec, privileged syscalls, sensitive files) | workload | Tetragon `TracingPolicy` | `apps/infra/tetragon/templates/` |
| Custom Well-Architected IaC checks | pipeline | Checkov custom policies (S3 SSE, IAM password, RDS backup, gp3) | `checkov-policies/*.json` |
| OPA guardrails on plan JSON | pipeline | Conftest (S3-public, SG-ingress, encryption-at-rest, required-tags, no-hardcoded-creds) | `tests/opa/*.rego` |
| Policy-diff cannot widen access | pipeline | IAM Access Analyzer `CheckNoNewAccess`/`CheckAccessNotGranted` | `.github/workflows/policy-access-check.yml` |
| Image CVE scan (CRITICAL/HIGH) | pipeline | Trivy (`aquasecurity/trivy-action`) → SARIF | `.github/workflows/container-build.yml` |
| Keyless image signing + SBOM attestation | pipeline | cosign (GitHub OIDC / Fulcio+Rekor) + Syft | `.github/actions/{cosign-sign,syft-sbom}` |
| Runner egress monitoring | pipeline | StepSecurity Harden-Runner (audit→block) | `.github/actions/harden-runner` |
| Actions workflow SAST | pipeline | zizmor → Code Scanning | `.github/workflows/zizmor.yml` |
| Secrets / SAST / dependency scan | pipeline | gitleaks, CodeQL, pip-audit/npm-audit/osv-scanner | `.github/actions/{secrets-scan,sast-codeql,*-dep-scan}` |

### 4.3 Org guardrails — SCP & RCP shape (sanitized)

Nine SCP resources live in `modules/scps/main.tf`. The two perimeter-critical ones:

```hcl
# Principal-side identity perimeter — attached at ROOT (applies to every account).
# IfExists semantics prevent false-trips on STS calls lacking a resolved OrgID.
resource "aws_organizations_policy" "deny_external_principals" {
  name = "DataPerimeter-DenyExternalPrincipals"
  type = "SERVICE_CONTROL_POLICY"
  content = jsonencode({ Version = "2012-10-17", Statement = [{
    Sid = "DenyNonOrgPrincipals", Effect = "Deny", Action = "*", Resource = "*"
    Condition = {
      StringNotEqualsIfExists = { "aws:PrincipalOrgID" = var.organization_id }   # {{ORG_ID}}
      BoolIfExists            = { "aws:PrincipalIsAWSService" = "false" }         # service carve-out
      ArnNotLike = { "aws:PrincipalArn" = [
        "arn:aws:iam::*:role/OrganizationAccountAccessRole",
        "arn:aws:iam::*:role/{{PROJECT}}-terraform-*",
      ] }
    }
  }] })
}
```

```hcl
# Resource-side perimeter (RCP) — deny external principals acting on OUR resources.
# RCPs have a SEPARATE slot budget from the 5/5 SCP cap. Staged in a Policy-Staging
# OU, then PROMOTED to root additively (for_each over target_ou_ids).
resource "aws_organizations_policy" "org_perimeter" {
  name = "RCP-DataPerimeter-DenyExternalAccess"
  type = "RESOURCE_CONTROL_POLICY"
  content = jsonencode({ Version = "2012-10-17", Statement = [{
    Sid = "DenyExternalAccessToResources", Effect = "Deny"
    Principal = { AWS = "*" }
    Action    = ["s3:*", "sts:*", "kms:*", "secretsmanager:*", "sqs:*"]
    Resource  = "*"
    Condition = {
      StringNotEqualsIfExists = { "aws:PrincipalOrgID" = var.organization_id }  # {{ORG_ID}}
      BoolIfExists            = { "aws:PrincipalIsAWSService" = "false" }
    }
  }] })
}
```

**Exemption philosophy** (must be reproduced): security SCPs that protect the audit trail
(`DenyDisableCloudTrail`, `DenyGuardDutyChanges`, `RequireEBSEncryption`) carry **no
exemptions**. Region-lock, S3-public, and the perimeters exempt only
`OrganizationAccountAccessRole` (account vending) and `{{PROJECT}}-terraform-*` (the CI/CD
apply role) — and only where those principals legitimately need it. Broad security SCPs
(`DenyS3PublicAccess`, `RequireEBSEncryption`, `DataPerimeter-*`) attach at **root** to
avoid the 5-SCP-per-OU limit; the rest attach per-OU. `DenyRootAccountUsage` attaches to
`workload_ou_names` (NonProd, Prod, Sandbox); `Deployments` is excluded (its accounts run
CI/AFT tooling under programmatic principals).

### 4.4 Break-glass user (ADR-0011)

```hcl
resource "aws_iam_user" "this" {
  name          = "break-glass-${var.account_name}"
  path          = "/break-glass/"
  force_destroy = false                    # apply-time backstop
  lifecycle { prevent_destroy = true }     # plan-time protection — removal needs a reviewed PR
}
# Inline "deny everything unless aws:MultiFactorAuthPresent" policy + AdministratorAccess
# (effective only AFTER the user enrolls MFA and calls sts:GetSessionToken --serial-number).
# CloudWatch metric filter on { $.userIdentity.userName = "break-glass-<acct>" } → alarm → SNS.
```
Access key and console login are **opt-in** (`create_access_key`/`create_console_login`
default `false`): flip on a single bootstrap apply, capture the secret into the team
password manager, then revert.

### 4.5 Break-glass procedure (design)

The **management account root** is the most privileged identity (can close the org, edit
SCPs, delete CloudTrail, reach any account via `OrganizationAccountAccessRole`). Day-to-day
uses IAM Identity Center + delegated-admin roles in `security`; root is used **only when no
other path works** (Identity Center/IdP outage, billing-only operations, recovery from a
lockout-inducing SCP, closing the org). Pre-conditions and runbook:

- **Pre-conditions (one-time):** MFA on root (two independent admins hold devices, both
  required); 32+ char generated password in an **offline** password-manager vault
  accessible only to platform-team-leads; **zero** root access keys (Config rule
  `IAM_ROOT_ACCESS_KEY_CHECK` alerts on creation); org CloudTrail covers all root activity;
  an EventBridge rule on `userIdentity.type == "Root"` pages the on-call SNS topic
  (chatops + pager).
- **Procedure:** (1) file a justification ticket + get a second-admin ack; (2) retrieve
  credentials via `scripts/break-glass.sh request --reason …` (records reason to logs,
  never prints/persists the password or MFA); (3) sign in from a clean incognito profile
  with MFA; (4) keep the session < 15 min, do **not** create keys/users or touch
  CloudTrail/GuardDuty/SCPs/the log bucket; (5) sign out + `release` (rotates the password,
  links CloudTrail events to the ticket); (6) post-incident review within 24 h.
- **Related controls:** member-account `DenyLeaveOrganization` / `DenyDisableCloudTrail`
  SCPs do **not** apply to the management root by design — break-glass is the only
  sanctioned path to those operations, which is exactly why every use alarms.

### 4.6 Workload identity — Pod Identity + ABAC (ADR-0018)

```hcl
# Trust: the EKS Pod Identity service principal, account-scoped, WITH sts:TagSession
# (required so ABAC session tags can be injected).
statement {
  actions    = ["sts:AssumeRole", "sts:TagSession"]
  principals { type = "Service", identifiers = ["pods.eks.amazonaws.com"] }
  condition { test = "StringEquals", variable = "aws:SourceAccount"
              values = [data.aws_caller_identity.current.account_id] }  # {{PROD_ACCOUNT_ID}} etc.
}
# Permission: bucket-scoped S3 + ABAC — principal AND resource must both be tagged
# platform:system = ml-pipeline. A mis-tagged caller or an untagged bucket is denied.
condition { test = "StringEquals", variable = "aws:PrincipalTag/platform:system", values = [local.platform_system] }
condition { test = "StringEquals", variable = "aws:ResourceTag/platform:system",  values = [local.platform_system] }
```
ESO authenticates via its **own** controller SA bound through a `PodIdentityAssociation`
(not `serviceAccountRef`); no SA may carry both `eks.amazonaws.com/role-arn` (IRSA) and a
Pod Identity association. ABAC scopes on six injected session tags (`eks-cluster-name`,
`kubernetes-namespace`, `kubernetes-service-account`, `kubernetes-pod-name`,
`kubernetes-pod-uid`, `eks-cluster-arn`). Fargate lacks Pod Identity → stays on IRSA;
Karpenter nodes must run the Pod Identity agent DaemonSet.

### 4.7 Artifact-store IAM / S3-TLS hardening (`aws-ml-artifact-store`, ADR-0048)

The bucket-provisioning module bundles the CIS-aligned S3 baseline every data bucket
should replicate: `BucketOwnerEnforced` (IAM-only, no ACLs); all-four public-access-block;
a bucket policy `DenyInsecureTransport` (`aws:SecureTransport=false` → CIS 2.1.1); SSE-KMS
(AES256 fallback) with `bucket_key_enabled`; versioning (audit chain); lifecycle
STANDARD-IA → Glacier-IR → Expire; a **standalone managed** IAM policy (CIS 1.16, not
inline) scoped to *this* bucket + ABAC; `prevent_destroy` on the bucket. Resources are
gated behind `create_resources = false` (apply only after explicit human approval).

### 4.8 Secrets — ESO + Secrets Manager + KMS + rotation

- **`ClusterSecretStore`** (`external-secrets.io/v1`) provider `aws` / `service:
  SecretsManager`, region `{{SECRETS_REGION}}`, auth via the ESO controller SA
  (`external-secrets/external-secrets`). Multi-cloud: a parallel `gcp-secrets-manager`
  store exists for GCP-backed secrets (e.g. the MLflow DB connection).
- **`ExternalSecret`** manifests materialize each secret with a `refreshInterval` (e.g.
  `1h`); the remote key path convention is `/<platform-system>/<name>` (e.g.
  `/ml-pipeline/mlflow-db-connection`). No plaintext secret ever lives in Git (ADR-0006).
- **Rotation** (`modules/secret-rotation`): `aws_secretsmanager_secret` (customer-managed
  KMS CMK) + `aws_secretsmanager_secret_rotation` (`automatically_after_days` or cron) +
  a rotation Lambda (custom handler or AWS RDS single/alternating-user template). IAM is
  scoped to the single secret ARN + its CMK; the Lambda runs in-VPC
  (`AWSLambdaVPCAccessExecutionRole`) to reach private RDS. Stakater Reloader (or an ESO
  content checksum) rolls consuming pods when the value changes.

### 4.9 Runtime security — network, admission, node OS, eBPF

- **Network:** apply `default-deny-all` (ingress+egress) **first**, then layer
  `allow-from-same-namespace` and `allow-dns-egress` (UDP/TCP 53 to `kube-system`). On
  Cilium clusters, `CiliumClusterwideNetworkPolicy` binds to **pod identity (labels)**, not
  IPs — policy survives pod restarts, Karpenter replacement, and spot eviction. The
  clusterwide default-deny permits only intra-namespace, CoreDNS, kube-apiserver, and
  Hubble-relay flows.
- **Admission:** Gatekeeper `K8sRequireSecurityContext` (`enforcementAction: deny`,
  graduated warn→deny after an audit soak; `excludedNamespaces` = kube-system, kube-public,
  gatekeeper-system, monitoring, external-secrets) forbids `runAsNonRoot != true`,
  `allowPrivilegeEscalation`, and `privileged`. Kyverno (v1.18.1) adds `ImageValidatingPolicy`
  (keyless cosign verification against a Fulcio identity + Rekor inclusion, `mutateDigest`,
  `failurePolicy: Enforce` in prod), securityContext mutation, and default-deny NetworkPolicy
  generation. VAP (CEL, in-process) blocks `:latest` and requires CPU/memory limits.
- **Node OS:** Bottlerocket — read-only root, SELinux-enforcing, no SSH/shell/package
  manager; two-volume gp3-encrypted layout (`/dev/xvda` OS, `/dev/xvdb` data); config via
  userData TOML (no bash bootstrap). FIPS and NVIDIA-GPU are separate pinned variants.
- **securityContext standard** (workload default, e.g. the inference Endpoint Picker):
  `runAsNonRoot: true`, `runAsUser: <nobody>`, `allowPrivilegeEscalation: false`,
  `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`, plus **bounded** resource
  requests/limits so no ext-proc/sidecar can OOM-pressure a node. **Documented exception:**
  the DCGM GPU-metrics exporter needs `runAsNonRoot: false` + `SYS_ADMIN` for device
  access — it still pins `readOnlyRootFilesystem: true` to bound the exception.
- **Runtime eBPF:** Tetragon `TracingPolicy` objects observe process exec, privileged
  syscalls, and sensitive-file access.

### 4.10 Policy-as-code & supply chain (pipeline layer)

- **Checkov** custom checks (`checkov-policies/*.json`) encode Well-Architected rules: S3
  SSE present (`WA_AWS_1`, MEDIUM), IAM password requires numbers (`WA_SEC_IAM_1`, HIGH),
  RDS backup retention > 0 (`WA_REL_RDS_1`, MEDIUM), EBS = gp3 (`WA_COST_EBS_1`, LOW).
- **Conftest/OPA** (`tests/opa/*.rego`, run on `terragrunt show -json tfplan`): no public
  S3 (ACL + all-four public-access-block), no unrestricted SG ingress (`0.0.0.0/0` /
  `::/0`, with a **port-443 carve-out**), encryption-at-rest across 10+ resource types,
  required tags (`Environment`/`Team`/`ManagedBy`), no hardcoded credentials (allow-lists
  Secrets-Manager/SSM references + `(sensitive value)`). The `conftest-opa.yml` workflow
  also runs `opa check --strict` + `opa test` so the `*_test.rego` unit tests actually
  execute in CI.
- **Access Analyzer gate** (`policy-access-check.yml`): on any change to `modules/{scps,rcps}`,
  `CheckNoNewAccess` proves the diff grants no new effective access and
  `CheckAccessNotGranted` proves named sensitive actions stay denied. **Gate on the JSON
  `result` field, not the CLI exit code** (the CLI can exit 0 on a FAIL). Advisory first,
  flip `ADVISORY: "false"` to block.
- **Container supply chain** (`container-build.yml`): Harden-Runner (audit) as the *first*
  step → Trivy CRITICAL/HIGH → SARIF upload → Syft SBOM → push by digest → **cosign keyless
  sign + SBOM attestation** via the job's GitHub OIDC identity. All third-party `uses:` are
  SHA-pinned with a version comment; AWS auth is OIDC only (no long-lived keys). zizmor
  SASTs the workflows themselves; gitleaks/CodeQL/pip-audit/npm-audit/osv-scanner cover
  secrets, SAST, and dependencies (ADR-0016/0022).

### 4.11 Ordering / dependencies (what must exist before what)

1. **Organization** (OUs + member accounts) → everything else in `_org/`.
2. **KMS** keys → CloudTrail, Config, log-archive bucket encryption.
3. **CloudTrail + Config** → **GuardDuty** → **Security Hub** (findings aggregation order).
4. **`RESOURCE_CONTROL_POLICY` + EC2-declarative policy types enabled** in the org →
   RCP/declarative modules can attach.
5. RCP: attach to the **Policy-Staging OU first**, soak, then additively promote to root.
6. **`eks-pod-identity-agent` addon** + ESO upgraded to v2.6.0 → Pod Identity units.
7. `catalog/units/github-oidc` deployed + `TERRAFORM_PLAN_ROLE_ARN` set → the Conftest gate
   runs (else it skips with an informational PR comment).
8. Network `default-deny-all` applied **before** any allow policy.

## 5. Parameterization table

| Placeholder | Meaning | Default in this estate | Resize guidance |
|---|---|---|---|
| `{{ORG}}` | org / company slug | `platform` | naming prefix for buckets, WAF ACLs |
| `{{PROJECT}}` | project/repo slug in role ARNs | `platform-design` | drives `{{PROJECT}}-terraform-*` SCP exemptions |
| `{{ORG_ID}}` | AWS Organizations id | `o-…` | perimeter SCP/RCP condition value |
| `{{MGMT_ACCOUNT_ID}}` | management account | `000000000000` (placeholder) | owns org, guardrails, trail, KMS, break-glass |
| `{{SECURITY_ACCOUNT_ID}}` | security account | `777777777777` (placeholder) | GuardDuty/Security Hub delegated admin |
| `{{LOG_ARCHIVE_ACCOUNT_ID}}` | log-archive account | `888888888888` (placeholder) | centralized immutable log bucket |
| `{{PROD_ACCOUNT_ID}}`, `{{DEV_ACCOUNT_ID}}`, … | workload accounts | per-account `account.hcl` | one Pod-Identity trust scope each |
| `{{PRIMARY_REGION}}` | home / aggregation region | `eu-west-1` | GuardDuty/Config aggregator home; region-lock set |
| `{{DR_REGION}}` | DR region | (per estate) | replication target for log-archive |
| `{{SECRETS_REGION}}` | ESO Secrets Manager region | `eu-central-1` | set on `ClusterSecretStore` |
| `{{ROOT_EMAIL_DOMAIN}}` | root-account email domain | `example.com` | `aws+<role>@{{ROOT_EMAIL_DOMAIN}}` |
| `{{LOG_ARCHIVE_BUCKET}}` | central log bucket | `{{ORG}}-log-archive-{{LOG_ARCHIVE_ACCOUNT_ID}}-{{PRIMARY_REGION}}` | globally-unique name |
| `allowed_regions` | SCP region allow-list | EU + `us-east-1` (globals) | set to client compliance geos |
| `cluster_endpoint_public_access_cidrs` | EKS API allow-list | prod `[]` (private), dev `["0.0.0.0/0"]` | tighten to CI IP ranges |
| `rate_limit` (WAF) | per-IP requests / 5-min | `2000` | raise for high-QPS inference |
| `log_retention_days` (WAF) | WAF log retention | `365` | set to compliance retention |
| `automatically_after_days` | secret rotation period | per-secret | PCI cryptoperiod |
| SSO `session_duration` | permission-set TTL | `PT4H` (admin/billing) / `PT8H` (else) | shorten for stricter regimes |
| `workload_ou_names` | OUs getting `DenyRootAccount` | `["NonProd","Prod","Sandbox"]` | add new workload OUs |

**Pinned tool versions** (from `terragrunt/versions.hcl` / `.tool-versions`): Terraform
`1.14.8`, Terragrunt `1.0.8`, AWS provider `~> 6.0`; CI pins Conftest `0.57.0`, OPA
`1.17.1`, Kyverno `1.18.1`, ArgoCD `3.3.6` (chart `9.5.1`). Bump patch/minor via green-CI
PR; majors need an ADR.

## 6. Best practices distilled

1. **Two perimeters, not one.** Pair a principal-side SCP (`aws:PrincipalOrgID`) with a
   resource-side RCP on S3/STS/KMS/SecretsManager/SQS. An SCP alone cannot stop a public
   bucket or over-broad KMS grant from punching out of the org; the RCP closes that gap and
   spends a *separate* slot budget. — *Why: SCPs gate callers, RCPs gate your resources.*
2. **Spend root SCP slots deliberately.** AWS caps 5 SCPs per target (incl. inherited
   `FullAWSAccess`). Put broad org-wide controls (S3-public, EBS-encryption, data-perimeter)
   at root and OU-specific ones per-OU. Prefer RCPs and EC2 declarative policies to relieve
   the cap. — *Why: you will hit 5/5 and be unable to add a control mid-incident.*
3. **No exemptions on audit-trail controls.** CloudTrail/GuardDuty tamper denies and
   mandatory-encryption denies must have zero carve-outs; only region-lock and the
   perimeters exempt the vending role and the CI apply role. — *Why: an exemption on the
   audit trail is an exfiltration path.*
4. **Protect emergency access at plan time.** `prevent_destroy` on the break-glass user
   errors before any API call; `force_destroy=false` is only the apply-time backstop. Keep
   the access key opt-in and alarm every use. — *Why: `terraform destroy` must never be able
   to silently delete your last-resort identity.*
5. **Machine-check every policy diff.** Replace review-by-eye of SCP/RCP edits with IAM
   Access Analyzer `CheckNoNewAccess`/`CheckAccessNotGranted`, and **gate on the JSON
   `result` field, not the exit code**. — *Why: a reviewer cannot reliably reason about
   deny-logic diffs; the CLI can exit 0 on a FAIL.*
6. **Workload identity by attribute, not by role-per-workload.** Use EKS Pod Identity with
   ABAC session tags so one role is reused across clusters and least-privilege is expressed
   as `aws:PrincipalTag`/`aws:ResourceTag` equality. Require `sts:TagSession` in the trust
   policy. — *Why: IRSA role sprawl is non-portable and unauditable at scale.*
7. **Verify image signatures at admission, not at GitOps sync.** ArgoCD verifies GnuPG git
   commits, not cosign/OCI signatures — put keyless verification (Fulcio identity + Rekor
   inclusion, `mutateDigest`, `failurePolicy: Enforce` in prod) in Kyverno. — *Why: the
   GitOps layer structurally cannot check container provenance.*
8. **Default-deny the network, then allow narrowly.** Apply `default-deny-all` first; on
   Cilium bind policy to pod identity (labels) so it survives IP churn from restarts, spot
   eviction, and Karpenter. — *Why: IP-based policy breaks the moment a pod moves.*
9. **Shrink the host, not just the container.** Bottlerocket (read-only root, SELinux, no
   SSH/shell/pkg-mgr, atomic updates) removes a mutable host attack surface that in-cluster
   controls cannot see. Standardize `runAsNonRoot`, drop ALL capabilities,
   `readOnlyRootFilesystem`, and **bounded** resources; document each exception (e.g. DCGM)
   and keep every other hardening flag on. — *Why: a compromised container on a mutable host
   is a foothold; on an immutable host it is contained.*
10. **No standing credentials, anywhere.** Secrets live only in Secrets Manager (ESO
    materializes them, ADR-0006 keeps Git plaintext-free), rotate on a defined cryptoperiod
    with a rotation Lambda + ESO refresh, and encrypt with customer-managed KMS CMKs. CI
    signs keylessly via OIDC and adds **zero** new long-lived secrets. — *Why: a leaked
    static secret is valid until someone notices; a rotated/federated one self-heals.*
11. **Enforce TLS and public-access-block on every bucket.** `BucketOwnerEnforced`,
    all-four public-access-block, and a `DenyInsecureTransport` bucket policy
    (`aws:SecureTransport=false`) are the non-negotiable S3 baseline (CIS 2.1.1). — *Why:
    SSE at rest is worthless if the object travels in plaintext.*
12. **Ship security gates advisory, graduate to blocking.** RCP staged in a Policy-Staging
    OU → root; Gatekeeper warn → deny after an audit soak; Harden-Runner audit → block;
    Access Analyzer + Conftest advisory → merge-blocking; WAF count → block. — *Why: a
    fail-closed control shipped blocking on day one causes an outage and gets disabled.*

## 7. Known pitfalls

- **5-SCP-per-OU cap is real and inherited.** `FullAWSAccess` counts. Placing a control at
  the wrong level (OU vs root) or adding one control too many silently fails to attach.
- **RCPs evaluate *after* identity/SCP/resource policy** — a new mental model. A
  mis-scoped RCP deny is final and can break log delivery / cross-service calls; that is why
  it must be staged in a small OU first (keep the AWS-service-principal carve-out).
- **`prevent_destroy` blocks `terraform destroy` for the whole account** while a break-glass
  user exists — expected, but surprises operators tearing down an environment.
- **Both workload-identity mechanisms on one SA is undocumented/unsupported.** After a Pod
  Identity cutover, ensure no SA still carries `eks.amazonaws.com/role-arn`. Fargate cannot
  use Pod Identity; Karpenter nodes must run the Pod Identity agent DaemonSet.
- **ABAC is case- and key-sensitive.** A wrong tag key or a resource missing
  `platform:system` yields a silent `AccessDenied`, not a plan error — a new bug class.
- **The Conftest gate is a no-op without OIDC.** It skips (with a PR comment) until
  `catalog/units/github-oidc` is deployed and `TERRAFORM_PLAN_ROLE_ARN` is set — don't
  mistake "skipped" for "passed".
- **Access Analyzer custom policy checks are a paid feature** — the workflow only runs on
  PRs touching `modules/{scps,rcps}` to bound cost.
- **WAF false-positives on long inference prompts.** Start managed rules + rate-limit in
  count mode and tune before flipping to block.
- **Bottlerocket has no SSH/shell.** Debugging requires the admin/control container
  (disabled by default); DaemonSets assuming a writable root or host paths may break —
  pilot on a fresh node group.
- **Rotation fires immediately on enable** (`rotate_immediately` defaults true) — every
  consumer must already read from Secrets Manager, or auth breaks on first rotation; a
  Lambda that cannot reach private RDS leaves rotation stuck in `AWSPENDING`.
- **AFT hard-requires a deployed Control Tower landing zone** (ADR-0017 omitted this;
  ADR-0035 corrects it). Enrolling a live org must delete pre-existing Config recorders
  before Audit/Log-Archive enrolment, and reconcile CT managed-SCPs against the 5/5 cap.
- **As-built divergence (confirm intent):** the ESO `ClusterSecretStore` targets a
  different region (`{{SECRETS_REGION}}`, `eu-central-1` as-built) than primary infra
  (`{{PRIMARY_REGION}}`, `eu-west-1`); may be deliberate secrets-region isolation or drift
  — a rebuild must decide explicitly.

## 8. Acceptance checklist

- [ ] `terragrunt run --all plan` is clean from an empty management account after
  Organization + KMS exist; SCP/RCP modules plan with `mock_outputs` before the org applies.
- [ ] All nine SCPs attach without exceeding 5 per target; broad controls verified at root.
- [ ] A non-org principal is denied on S3/STS/KMS/SecretsManager/SQS (RCP live at root); an
  AWS service principal (log delivery) is **not** denied.
- [ ] A member-account root call is denied; disabling CloudTrail/GuardDuty is denied with no
  exemption; creating an unencrypted EBS volume is denied.
- [ ] `terraform destroy` on any account with a break-glass user **fails** at plan; a
  simulated break-glass sign-in raises the CloudWatch alarm → SNS within the expected delay.
- [ ] GuardDuty (all plans), Config (incl. global IAM), Security Hub (CIS+PCI+FSBP) are
  enabled; findings aggregate in `security`; logs land in the `log-archive` Object-Lock bucket.
- [ ] `IAM_ROOT_ACCESS_KEY_CHECK` reports compliant (root has no access key); password
  policy + enforce-MFA applied.
- [ ] A PR that widens an SCP/RCP fails `CheckNoNewAccess` (gate reads JSON `result`); a PR
  adding a public S3 ACL / `0.0.0.0/0` non-443 SG ingress / unencrypted store fails Conftest.
- [ ] A container image is pushed by digest, cosign-signed keylessly, and carries a signed
  SBOM attestation; an unsigned image is rejected at admission in prod.
- [ ] `default-deny-all` (and the Cilium clusterwide deny) is applied before any allow;
  a pod without a compliant securityContext is rejected by Gatekeeper.
- [ ] Every workload authenticates via Pod Identity/IRSA with no static keys; ABAC denies a
  mis-tagged caller; ESO materializes secrets with no plaintext in Git.

## 9. Dependencies on other specs

- **SPEC-00 Overview** — global placeholder registry (`{{ORG}}`, account IDs, regions).
- **SPEC-01 Foundation / IaC** — Terragrunt structure, `versions.hcl` pins, `root.hcl`
  backend, and the module/unit conventions this spec's security modules follow.
- **SPEC — Organization / Landing Zone** — OU tree, member accounts, Control Tower + AFT
  vending (ADR-0001, ADR-0035) that this spec's guardrails attach to.
- **SPEC — Networking** — VPC/TGW segmentation, inspection VPC, and the LB/Gateway objects
  that WAF and the inference serving front bind to (ADR-0013, ADR-0047).
- **SPEC — Clusters (EKS/Bottlerocket/Cilium)** — node OS, CNI identity model, and the
  admission stack this spec configures (ADR-0003, ADR-0030).
- **SPEC — GitOps / ArgoCD** — how `network-policies`, `gatekeeper`, `kyverno`, `tetragon`,
  and `cluster-secret-store` are delivered and the ArgoCD hardening (ADR-0006, ADR-0024).
- **SPEC — CI/CD Pipelines** — reusable workflows, SHA-pinning, and the supply-chain gates
  (ADR-0015, ADR-0016, ADR-0022) this spec's policy checks plug into.
- **SPEC — Observability** — GuardDuty/Security Hub/CloudTrail routing and the SOC2
  control-to-evidence matrix + on-call (ADR-0026, ADR-0040).
```
