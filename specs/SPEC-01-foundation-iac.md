# SPEC-01 — Foundation: IaC, Account Topology & State

> Portable reverse-engineering of the platform's Infrastructure-as-Code foundation:
> the AWS Organization + OU topology, the Terragrunt-over-Terraform orchestration
> layer, remote state, version pinning, and the tagging/naming standards that every
> other spec builds on. Follows `CONVENTIONS.md`. All identity is parameterized; no
> real account IDs, buckets, IPs, emails, or org names appear.

---

## 1. Scope & non-goals

**Scope.** This spec defines the *ground floor* a new client stands up before any
cluster or workload exists: (a) the AWS Organization and its Organizational Unit
(OU) split; (b) the canonical multi-account topology (management + security +
log-archive + network + shared + dev/staging/prod/dr + third-party, plus an
optional personal sandbox); (c) the Terragrunt orchestration layer
(`root.hcl` + `versions.hcl` + `common.hcl` + `_envcommon/` inheritance + the
`catalog/units` + `catalog/stacks` model); (d) the Terraform-only remote-state
backend and its bootstrap ordering; (e) exact tool/provider version pins; and
(f) the naming and tagging conventions (ADR-0028 unified taxonomy) that make
FinOps, observability, and incident-response joins work.

**Non-goals.** VPC/CIDR design, Transit Gateway, ClusterMesh, and inter-VPC
security (their own networking spec); EKS/Karpenter/KEDA compute (compute spec);
SCP/RCP/GuardDuty/SecurityHub *contents* (security-guardrails spec — this spec
covers only *where* they attach); GitOps delivery (ArgoCD/Kargo), observability,
and GPU/ML stacks. AWS Control Tower + AFT account vending is a **design-target**
here (ADR-0035) and is described only as the intended evolution of the live
raw-Organizations bootstrap.

---

## 2. Architecture

Two orthogonal axes organize the estate: **AWS accounts/OUs** (isolation +
governance) and the **Terragrunt live tree** (DRY config resolution). They meet
at `account.hcl` / `region.hcl`, which every unit reads via
`find_in_parent_folders`.

```
                          AWS Organization  (management / root account)
                          ├─ enabled policy types: SCP + TAG + RCP
                          └─ OU tree (8 OUs, applied from management):
   Root
   ├── Security            → security, log-archive, third-party
   ├── Infrastructure      → network, shared
   ├── Workloads           (container OU; no direct accounts)
   │   ├── NonProd         → dev, staging          (alias: Non-Production)
   │   └── Prod            → prod, dr              (alias: Production)
   ├── Deployments         → (reserved for AFT/CI — ADR-0035)
   ├── Sandbox             → (per-developer, optional)
   └── Suspended           → (incident-response quarantine)

   Config-resolution chain (every unit, resolved by root.hcl):
   ┌ versions.hcl ─ tool + provider pins (single source of truth)
   ├ common.hcl   ─ project metadata, tag schema, region short codes
   ├ account.hcl  ─ account_id, env, owner, cost_center, sizing knobs
   └ region.hcl   ─ aws_region, region_short, azs
        │
        ▼   include "root" { find_in_parent_folders("root.hcl") }
   root.hcl  ──generate──▶  backend.tf          (S3 + lock per account/region)
             ──generate──▶  provider.tf         (assume_role + default_tags)
             ──generate──▶  versions_override.tf (required_version + providers)
        │
        ▼
   Live tree:  terragrunt/<account>/<region>/<stack>/terragrunt.stack.hcl
        │            references
        ▼
   Catalog:   catalog/units/<unit>/terragrunt.hcl  +  catalog/stacks/<stack>
        │            + _envcommon/<module>.hcl  (source pin + shared inputs)
        ▼
   Modules:   terraform/modules/<module>/   (thin wrappers over upstream modules)
```

**Bootstrap (chicken-and-egg break).** The state backend cannot live in the
state it stores, so `bootstrap/state-backend/` is a **Terraform-only** root
(local state, no Terragrunt) that creates the S3 bucket + DynamoDB lock table
per account. Everything else then runs through Terragrunt against that backend.

---

## 3. Decision record

| Decision | Rationale | Trade-off accepted | Source ADR |
|---|---|---|---|
| **Terragrunt** as the orchestration layer over plain Terraform / workspaces / CDKTF | `_envcommon/` kills per-account duplication; `generate` gives uniform backend + provider + `default_tags`; `dependency` gives cross-module wiring; `run --all` orders applies across accounts | Terragrunt-specific HCL learning curve; harder debugging (generated files); CI installs two tools | `ADR-0004 Terragrunt over plain Terraform` |
| **Terraform-only state backend bootstrap** (dedicated module + script, local state, no Terragrunt wrapper) | Bucket config (versioning, KMS, Object Lock, lifecycle) is auditable IaC, not implicit Terragrunt auto-create | Bootstrap state file is committed to git (bucket/table ARNs only, no secrets); needs a privileged org-admin run | `ADR-0002 Terraform-only state backend` |
| **Canonical OU split**: Production / Non-Production / Deployments / Suspended / Sandbox, layered over functional OUs (Security / Infrastructure / Workloads) | Blast-radius isolation, per-account cost allocation, per-OU SCP profiles; `Deployments` isolates future AFT/CI; `Sandbox` gets its own region-restrict + spend-cap profile | Doc-level alias mapping (`Prod`↔`Production`) adds cognitive load; two extra OUs add SCP-attachment entries (within AWS caps) | `ADR-0001 OU split` (folds in the multi-account strategy) |
| **Unified platform tagging taxonomy** — five `platform:*` AWS tags mirroring five `platform.*` K8s labels, injected via `root.hcl` `default_tags` + `inputs.tags` | One taxonomy joins the AWS plane and the EKS plane for single-pane dashboards, FinOps allocation, and incident correlation | Strict enforcement overhead (untagged resources vanish from dashboards/cost); migration effort to thread `var.tags` everywhere | `ADR-0028 Unified Platform Tagging and Labeling Taxonomy` |
| **Version pins centralized in `versions.hcl`**; every other manifest mirrors it | Single source of truth prevents drift between `required_version`, CI matrix, and tool managers | Mirrors (`.tool-versions`, `.terraform-version`, `.terragrunt-version`, `mise.toml`) must be updated in lockstep | `versions.hcl` bump policy (patch/minor = PR; major = ADR) |
| **AWS Control Tower + AFT** as the *target* landing-zone / vending model | CT is a hard prerequisite of AFT; moves account baselining + guardrail drift to a managed control plane; vending becomes a reviewed `aft-account-request` PR | Live-org migration (not greenfield); two new management accounts; SCP-slot + Config/CloudTrail collisions to reconcile | `ADR-0035 Control Tower + AFT` (supersedes ADR-0017 item-0) |
| **Hub-and-spoke Transit Gateway**, one TGW shared via RAM to workload accounts | Central connectivity + inspection; spoke isolation as the default | Cross-account RAM wiring; blackhole routes for env isolation | `ADR-0005 hub-spoke-transit-gateway` (detailed in networking spec) |

---

## 4. Implementation blueprint

### 4.1 Directory layout

```
<repo-root>/
├── bootstrap/state-backend/           # TF-only, local state — runs FIRST
│   ├── main.tf  variables.tf  outputs.tf  README.md
├── terraform/
│   ├── modules/<module>/              # ~135 thin module wrappers (vpc, eks,
│   │                                  #   organization, scps, kms, state-backend, …)
│   ├── environments/production/       # optional flat root-module example
│   └── README.md  QUICK_START.md
├── terragrunt/
│   ├── root.hcl                       # backend + provider + versions generation
│   ├── versions.hcl                   # SINGLE SOURCE OF TRUTH for versions
│   ├── common.hcl                     # project metadata, tag schema, region codes
│   ├── mise.toml                      # mirrors versions.hcl
│   ├── _envcommon/<module>.hcl        # per-module source pin + shared inputs
│   ├── _org/                          # management account
│   │   ├── account.hcl                # org-wide: member_accounts map, OU placement
│   │   └── _global/<unit>/            # organization, scps, rcps, sso, cloudtrail,
│   │                                  #   guardduty-org, security-hub, aws-config,
│   │                                  #   iam-baseline, budgets, break-glass-user
│   └── <account>/                     # security | log-archive | network | shared |
│       ├── account.hcl                #   dev | staging | prod | dr | third-party | sandbox
│       ├── _global/iam/               # account-wide (non-regional) resources
│       └── <region>/                  # eu-west-1|2|3 | eu-central-1 (+ us-east-1 niche)
│           ├── region.hcl
│           └── <stack>/terragrunt.stack.hcl
├── catalog/units/<unit>/terragrunt.hcl
├── catalog/stacks/<stack>/terragrunt.stack.hcl
├── .tool-versions  .terraform-version  .terragrunt-version   # mirror versions.hcl
├── .tflint.hcl  .yamllint.yml
└── docs/adrs/  docs/ou-structure.md  docs/account-vending.md
```

### 4.2 Version pins (exact — from `versions.hcl`, the single source of truth)

| Tool / provider | Pin | Constraint form |
|---|---|---|
| Terraform / OpenTofu | `1.14.8` | `required_version = "= 1.14.8"` |
| Terragrunt | `1.0.8` | `terragrunt_version_constraint = "= 1.0.8"` |
| `hashicorp/aws` | `~> 6.0` | generated into `versions_override.tf` |
| `hashicorp/helm` | `~> 2.12` | |
| `hashicorp/kubernetes` | `~> 2.30` | |
| `null` / `random` / `tls` | `~> 3.2` / `~> 3.6` / `~> 4.0` | |
| TFLint AWS ruleset | `0.35.0` | `.tflint.hcl` |

Mirrors that MUST match exactly: `.tool-versions` (`terraform 1.14.8`,
`terragrunt 1.0.8`), `.terraform-version` (`1.14.8`), `.terragrunt-version`
(`1.0.8`), `terragrunt/mise.toml`. Bump policy: patch/minor = PR + green CI on a
non-prod env first; major = ADR + multi-env soak.

### 4.3 `root.hcl` — the load-bearing generation logic (sanitized excerpt)

```hcl
locals {
  versions     = read_terragrunt_config(find_in_parent_folders("versions.hcl"))
  common       = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  is_sandbox          = local.account_name == "sandbox"      # escape-hatch branch
  state_bucket_region = try(local.account_vars.locals.state_bucket_region, local.aws_region)

  platform_tags = {                                          # ADR-0028 taxonomy
    "platform:system"     = try(local.account_vars.locals.platform_system, local.common.locals.default_platform_system)
    "platform:component"  = try(local.account_vars.locals.platform_component, local.common.locals.default_platform_component)
    "platform:env"        = local.environment
    "platform:owner"      = try(local.account_vars.locals.owner, local.common.locals.default_owner)
    "platform:managed-by" = local.common.locals.platform_managed_by   # "terragrunt"
  }
}

remote_state {
  backend  = "s3"
  generate = { path = "backend.tf", if_exists = "overwrite_terragrunt" }
  config = merge(
    {
      bucket  = local.is_sandbox ? "{{ORG}}-terraform-state-${local.account_id}" : "tfstate-${local.account_name}-${local.aws_region}"
      key     = "${local.environment}/${path_relative_to_include()}/terraform.tfstate"
      region  = local.state_bucket_region
      encrypt = true
    },
    local.is_sandbox
      ? { use_lockfile = true,  dynamodb_table = null, dynamodb_table_tags = null }   # S3 native lock
      : { use_lockfile = false, dynamodb_table = "terraform-locks-${local.account_name}" }  # DynamoDB (legacy)
  )
}
```

The provider is generated with a conditional `assume_role` (org accounts assume
`{{DEPLOY_ROLE}}`; sandbox uses direct IAM-user creds) and `default_tags`
carrying both the legacy cost/audit keys and the five `platform:*` keys:

```hcl
generate "provider" {
  path = "provider.tf"  if_exists = "overwrite_terragrunt"
  contents = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"
      %{if !local.is_sandbox}
      assume_role { role_arn = "arn:aws:iam::${local.account_id}:role/{{DEPLOY_ROLE}}" }
      %{endif}
      default_tags { tags = { Environment = "${local.environment}", ManagedBy = "terragrunt",
        Owner = "${local.owner}", CostCenter = "${local.cost_center}",
        "platform:system" = "${local.platform_system}", "platform:env" = "${local.environment}", ... } }
    }
  EOF
}
```

### 4.4 `_envcommon` inheritance pattern (the DRY core)

Each `_envcommon/<module>.hcl` fixes the **module source** and **shared default
inputs** once; per-env units include it with `merge_strategy = "deep"` and
override only what differs.

```hcl
# _envcommon/eks.hcl  (shared across every <env>/<region>/eks unit)
locals {
  module_source = "${get_repo_root()}/<repo-subpath>/terraform/modules/eks"
  defaults = {
    cluster_version            = "1.34"
    endpoint_private_access    = true
    endpoint_public_access     = false     # non-prod may flip, with caution
    enabled_cluster_log_types  = ["api","audit","authenticator","controllerManager","scheduler"]
    secrets_encryption_enabled = true
  }
}
terraform { source = local.module_source }
dependency "vpc" {                         # VPC must exist before EKS
  config_path  = "../vpc"
  mock_outputs = { vpc_id = "vpc-mock0123", private_subnet_ids = ["subnet-mock1","subnet-mock2"] }
  mock_outputs_allowed_terraform_commands = ["init","validate","plan"]
}
inputs = { cluster_version = local.defaults.cluster_version, vpc_id = dependency.vpc.outputs.vpc_id, ... }
```

Consuming unit (only the delta):
```hcl
include "root"      { path = find_in_parent_folders("root.hcl") }
include "envcommon" { path = find_in_parent_folders("_envcommon/eks.hcl"), expose = true, merge_strategy = "deep" }
inputs = { cluster_name = "platform-dev-euw1", node_groups = { general = { instance_types = ["m6i.large"], desired_size = 2 } } }
```

`_envcommon` bump policy: adding a backward-compatible default = PR + CI;
changing a default = list every consumer (`grep -r "_envcommon/<module>.hcl" terragrunt/`)
+ non-prod soak; changing the module `source` = **ADR** (it rewrites every
consumer's state address).

### 4.5 Account topology (canonical set)

| Folder | OU | Account-ID placeholder | Purpose |
|---|---|---|---|
| `_org/` | Root | `{{MGMT_ACCOUNT_ID}}` | Organization management / landing-zone hub |
| `security/` | Security | `{{SECURITY_ACCOUNT_ID}}` | Delegated admin: GuardDuty, SecurityHub, Detective, Inspector, Macie |
| `log-archive/` | Security | `{{LOGARCHIVE_ACCOUNT_ID}}` | Central immutable log bucket (CloudTrail, Config, VPC Flow, EKS audit) |
| `network/` | Infrastructure | `{{NETWORK_ACCOUNT_ID}}` | Transit Gateway hub, Route53 resolver, inspection VPC |
| `shared/` | Infrastructure | `{{SHARED_ACCOUNT_ID}}` | ECR, Route53 private zones, ACM authority, Service Catalog |
| `dev/` | NonProd | `{{DEV_ACCOUNT_ID}}` | Development workloads |
| `staging/` | NonProd | `{{STAGING_ACCOUNT_ID}}` | Pre-production (canonical name `stage`) |
| `prod/` | Prod | `{{PROD_ACCOUNT_ID}}` | Production workloads |
| `dr/` | Prod | `{{DR_ACCOUNT_ID}}` | Disaster recovery for prod |
| `third-party/` | Security | `{{THIRDPARTY_ACCOUNT_ID}}` | Vendor IAM principals (narrow cross-org trust) |
| `sandbox/` | Sandbox | `{{SANDBOX_ACCOUNT_ID}}` | *Optional* personal-account escape hatch (see §7) |

Account IDs in the estate use the repeated-digit documentation shape
(`000000000000`, `111111111111`, …) with `# TODO: replace` markers. **Two
sources of truth exist and must stay in sync**: each account's own
`terragrunt/<name>/account.hcl` **and** the `member_accounts` map in
`terragrunt/_org/account.hcl` (used to create the accounts and place them in
OUs). Every `account.hcl` declares `account_name`, `account_id`, `email`,
`org_ou`, `environment`, `owner`, `cost_center`; workload accounts add sizing
knobs (NAT posture, EKS node groups, RDS class, Karpenter nodepools, …).

### 4.6 Region + CIDR standard

Region short codes (`common.hcl` `region_short_codes`): `eu-west-1→euw1`
(Ireland/primary), `eu-west-2→euw2` (London), `eu-west-3→euw3` (Paris),
`eu-central-1→euc1` (Frankfurt). Non-overlapping `/16` per env×region:

| Env | eu-west-1 | eu-west-2 | eu-west-3 | eu-central-1 |
|---|---|---|---|---|
| dev | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 | 10.3.0.0/16 |
| staging | 10.10.0.0/16 | 10.11.0.0/16 | 10.12.0.0/16 | 10.13.0.0/16 |
| prod | 10.20.0.0/16 | 10.21.0.0/16 | 10.22.0.0/16 | 10.23.0.0/16 |
| dr | 10.30.0.0/16 | 10.31.0.0/16 | 10.32.0.0/16 | 10.33.0.0/16 |

### 4.7 Bootstrap ordering (zero → running)

```
0. Prereqs: management account exists; org-admin creds; mise install (pins from mise.toml).
1. AWS Organization + OUs + member accounts:
     terragrunt apply  terragrunt/_org/_global/organization   (from management account)
     → enables SCP + TAG_POLICY + RESOURCE_CONTROL_POLICY; creates 8 OUs; for_each member accounts.
2. State backend per account (TF-only, LOCAL state, run before any Terragrunt unit):
     ./scripts/deploy-state-backends.sh apply           # assumes OrganizationAccountAccessRole
     order: management → network → dev/staging/prod/dr (rest any order)
     → creates s3://tfstate-<account>-<region> (+ terraform-locks-<account>), prevent_destroy=true.
3. Guardrails from management: scps (dep: organization), rcps, sso, cloudtrail, config-org,
     guardduty-org, security-hub, iam-baseline, budgets, break-glass-user.
4. Network account: transit-gateway → RAM share → per-spoke tgw-attachment.
5. Workload accounts, per region, dependency-ordered by Terragrunt:
     Phase 1 (parallel): vpc, secrets
     Phase 2: eks (dep vpc)
     Phase 3 (parallel): karpenter (dep eks), monitoring (dep eks), rds (dep vpc+eks+secrets)
     Deploy dev first, then promote config through staging → prod → dr.
```

Deploy a whole stack: `cd terragrunt/dev/eu-west-1/platform && terragrunt stack apply`.
Whole environment: `cd terragrunt/dev && terragrunt run --all apply`.

---

## 5. Parameterization table

| Placeholder | Meaning | Default / shape in this estate | Resize guidance |
|---|---|---|---|
| `{{ORG}}` | Org slug (used in sandbox state bucket) | private slug → e.g. `acme` | Lowercase DNS-safe; used in global-unique S3 names |
| `{{VCS_ORG}}` / `{{REPO}}` | Git org / repo (`repository` local) | `{{VCS_ORG}}/{{REPO}}` | Any Git host org |
| `{{PROJECT}}` | `project_name` in `common.hcl` | e.g. `platform-design` | Free-form; appears in the `Project` tag |
| `{{MGMT_ACCOUNT_ID}}` … `{{SANDBOX_ACCOUNT_ID}}` | 12-digit AWS account IDs (11 accounts) | repeated-digit doc shape + TODO | Replace all; keep `_org` `member_accounts` in sync |
| `{{PRIMARY_REGION}}` | Primary region / SecurityHub aggregator home | `eu-west-1` | Also the Control-Tower home region (permanent) |
| `{{SECONDARY_REGIONS}}` | Additional active regions | `eu-west-2`, `eu-west-3`, `eu-central-1` | Add region folder + `region.hcl` + CIDR row |
| `{{DEPLOY_ROLE}}` | Cross-account deploy role assumed by CI | `TerragruntDeployRole` | Must exist in every non-sandbox account |
| `{{STATE_BUCKET}}` | State bucket name | `tfstate-<account>-<region>` (org); `{{ORG}}-terraform-state-<id>` (sandbox) | One bucket per account per region |
| `{{ACCOUNT_EMAIL}}` | Root email per account | `aws+<name>@{{DOMAIN}}` | Use plus-addressing on one mailbox |
| `{{SANDBOX_EMAIL}}` / `{{SANDBOX_USER}}` / `{{OPERATOR_IP}}` | Sandbox root email / IAM user / operator public IP allow-list | *(sanitized)* / `sandbox-admin` / `{{OPERATOR_IP}}/32` | Sandbox only; never ship a real personal IP or account |

**Sizing knobs** (all in `account.hcl`, per environment):

| Setting | dev | staging | prod | dr |
|---|---|---|---|---|
| NAT gateway | single | per-AZ (HA) | per-AZ (HA) | single |
| EKS public access | yes (`0.0.0.0/0` — dev only) | no | no (private; break-glass CIDR allow-list) | no |
| EKS instance type | `m6i.large` | `m6i.xlarge` | `m6i.2xlarge` | `m6i.xlarge` |
| EKS nodes (min/desired/max) | 1/2/3 | 2/3/5 | 3/5/10 | 1/2/5 |
| RDS class / multi-AZ / GB | `db.t4g.medium` / no / 20 | `db.r6g.large` / yes / 50 | `db.r6g.xlarge` / yes / 100 | `db.r6g.large` / yes / 50 |
| Karpenter controller replicas | 2 | 2 | 3 | 2 |
| CDE isolation (PCI-DSS) | off | off | on (dedicated nodepool + taint) | off |
| TGW / ClusterMesh cluster-IDs | TGW off | mesh on (euw1=1, euc1=2) | per-region | off |

Other knobs: KMS key inventory (`_envcommon/kms.hcl` — 10 CMKs: cloudtrail,
aws-config, s3-data, eks-secrets, ebs, rds, sns, sqs, logs, backup; rotation on,
30-day deletion window); TGW `amazon_side_asn_base = 64512`; budgets
(`monthly_budget_amount` default `10000` USD, alerts at 50/80/100/110%,
anomaly detection at `20` USD); central-log lifecycle (90d → Glacier 365d →
expire 2555d/7y, Object Lock `GOVERNANCE` 365d).

---

## 6. Best practices distilled

1. **One version source of truth.** All version literals live in `versions.hcl`;
   every tool manifest mirrors it. *Why:* a single edit can't leave
   `required_version`, the CI matrix, and `mise`/`asdf` disagreeing — the most
   common "works on my machine" failure in multi-account IaC.
2. **Generate backend + provider + versions; never hand-write them.** `root.hcl`
   `generate` blocks produce `backend.tf`, `provider.tf`, `versions_override.tf`
   for every unit. *Why:* uniform `default_tags`, uniform `assume_role`, uniform
   state keys — zero copy-paste drift across ~135 modules.
3. **Fix the module source + shared inputs in `_envcommon/`, override only the
   delta in the unit.** *Why:* bumping a cross-cutting default (e.g. a new EKS
   log type) is one edit, inherited everywhere, instead of N unit edits.
4. **Account-per-isolation, OU-per-policy-profile.** Map accounts onto OUs whose
   SCP profile matches their risk (NonProd/Prod/Sandbox deny-root; Deployments
   runs programmatic IAM). *Why:* blast-radius isolation and clean per-OU SCP
   math (AWS caps SCPs per OU).
5. **Break the state chicken-and-egg explicitly.** Bootstrap the backend with a
   TF-only, local-state module (`bootstrap/state-backend`) before any Terragrunt
   unit runs; `prevent_destroy = true` on the bucket + lock table. *Why:*
   auditable bucket config (versioning, KMS, Object Lock) and no accidental loss
   of every unit's state.
6. **One state bucket per account per region, one lock table per account.**
   Key = `<env>/<path_relative_to_include()>/terraform.tfstate`. *Why:* a lost or
   corrupted bucket is scoped to one account/region, and state keys are
   collision-free by construction.
7. **Tag once, at the root, with the unified taxonomy.** Inject the five
   `platform:*` keys via `default_tags` **and** `inputs.tags` so both
   provider-applied and module-`var.tags`-applied resources carry them; enforce
   with a TFLint `aws_resource_missing_tags` rule. *Why:* AWS tags and K8s labels
   share keys byte-for-byte, so Grafana/YACE/OpenCost joins and incident triage
   work across planes.
8. **Merge tags later-wins: legacy → `platform:*` defaults → unit `tags`.** A unit
   that owns a logical service sets `tags["platform:system"]="auth"` and wins
   without clobbering the other four keys. *Why:* per-service ownership without
   losing the org-wide taxonomy.
9. **Cross-unit data via `dependency` + `mock_outputs`, never hardcoded ARNs.**
   Mocks are scoped to `["init","validate","plan"]` so plans work before the
   dependency exists. *Why:* `run --all plan` stays green on an empty account and
   real outputs flow at apply.
10. **Deploy dev first, promote config through staging → prod → dr.** *Why:*
    every version/default bump soaks in low-risk environments before prod.
11. **Pin the operator blast radius.** Prod EKS endpoints are private by default;
    if public access is ever enabled it is locked to an org-driven CIDR
    allow-list, never `0.0.0.0/0` (dev is the only place `0.0.0.0/0` is
    acceptable). *Why:* the API server is the single highest-value target.
12. **Record every foundational choice as an ADR; never rewrite a ratified one.**
    Supersede forward (ADR-0035 supersedes ADR-0017 item-0) and note corrections
    of record. *Why:* the decision trail survives contributor turnover.

---

## 7. Known pitfalls

1. **Stale version references in prose.** `terragrunt/README.md` ("Terraform >=
   1.11.0, Terragrunt >= 0.68.0"), `mise.toml`'s header comment ("terraform 1.10,
   terragrunt 0.68"), and `root.hcl`'s "Terragrunt v0.68" type-consistency note
   all predate the current pins (**TF 1.14.8 / TG 1.0.8**). Trust `versions.hcl`
   only; treat prose version numbers as non-authoritative and fix them on sight.
2. **As-built divergence: DynamoDB locking is still the non-sandbox default.** `root.hcl` sets
   `use_lockfile = false` + a `terraform-locks-<account>` table for every
   non-sandbox account; only sandbox uses S3-native `use_lockfile = true`.
   Current guidance prefers S3 native locking (DynamoDB is legacy) — plan a
   migration; don't assume the estate already uses it.
3. **The "Setup" step "Terragrunt auto-creates buckets" contradicts ADR-0002.**
   `terragrunt/README.md`'s setup list says the backend is auto-created; ADR-0002
   explicitly rejects that in favor of the `bootstrap/state-backend` module. Use
   the bootstrap module; the README line is stale.
4. **Two sources of truth for account IDs.** Each `account.hcl` **and** the
   `_org` `member_accounts` map both carry IDs; they can drift. Update both in one
   PR when onboarding an account, and keep the placeholder-shape TODO markers
   until real IDs land.
5. **Placeholder admin CIDR must be replaced before public endpoints.**
   `_org/account.hcl` `admin_cidr_allowlist` and prod's `eks_public_access_cidrs`
   ship as `10.0.0.0/8 # PLACEHOLDER — DO NOT ship as-is`. Replace with real
   office/VPN egress CIDRs before ever flipping `eks_public_access` to `true`.
6. **The sandbox account is a real personal-account escape hatch, not a template
   member.** It hardcodes a fixed state bucket in a specific region
   (`state_bucket_region`), skips `assume_role`, uses direct IAM-user creds, and
   disables org features. For a client rebuild, treat `sandbox` as *optional* and
   fully parameterized — never copy its concrete identity, IP, or bucket.
7. **As-built divergence: module sources are path-based, not version-pinned.** `_envcommon` sources
   read `${get_repo_root()}/.../terraform/modules/<m>`; there is no git-ref /
   registry version on the source. Changing a module immediately affects every
   consumer (mitigated only by the "source change = ADR" rule). A hardened
   rebuild should pin sources by Git ref or registry version.
8. **`staging` vs `stage` name mismatch.** The folder is `staging/` but the
   canonical 9-account name is `stage`. Kept for backwards-compat; downstream
   tooling that keys on the canonical name needs the alias.
9. **OU alias cognitive load.** `Prod`↔`Production`, `NonProd`↔`Non-Production`.
   The mapping lives in `docs/ou-structure.md`; renaming would force a state
   migration on SCP attachments and SSO assignments (rejected in ADR-0001).
10. **SCP-slot ceiling.** AWS caps 5 SCPs per OU (plus inheritance-only
    `FullAWSAccess`). The estate runs 5/5 on workload OUs; Control Tower's managed
    SCPs (ADR-0035) collide with this cap — RCPs (ADR-0017) relieve pressure by
    moving controls off the SCP budget.
11. **Control Tower / AFT is design-target, not built.** No `aws_controltower_*`
    resources and no `aft-*` repos exist; the live path is raw AWS Organizations
    via `terraform/modules/organization`. Decide CT-first vs raw-Organizations for
    a new client up front — enrolling a live org into CT later is an L-effort
    migration.
12. **`_org/_global/*` units are single-consumer — don't wrap them in
    `_envcommon`.** Their knobs live in the unit; an `_envcommon` indirection for a
    once-globally-deployed resource is pure overhead (per the `_envcommon` README).

---

## 8. Acceptance checklist

A rebuild passes this spec when:

- [ ] `versions.hcl` is the only file containing a version literal; `.tool-versions`,
      `.terraform-version` (`1.14.8`), `.terragrunt-version` (`1.0.8`), and
      `mise.toml` mirror it exactly; `mise install` yields TF `1.14.8` + TG `1.0.8`.
- [ ] `terragrunt hcl fmt --check` and `terraform fmt -recursive -check` are clean.
- [ ] From a freshly created (empty) account, `bootstrap/state-backend` applies
      with **local** state and creates `tfstate-<account>-<region>` +
      `terraform-locks-<account>` (both `prevent_destroy = true`).
- [ ] After bootstrap, `terragrunt run --all validate` and `terragrunt run --all plan`
      are clean in a workload account with **no** hardcoded outputs (all cross-unit
      refs resolve via `dependency` + `mock_outputs`).
- [ ] The AWS Organization applies from the management account with **8 OUs**
      (Security, Infrastructure, Workloads, NonProd, Prod, Deployments, Sandbox,
      Suspended) and `enabled_policy_types` = SCP + TAG_POLICY + RCP.
- [ ] The SCP attachment matrix matches `docs/ou-structure.md`; `workload_ou_names`
      = `["NonProd","Prod","Sandbox"]`; no OU exceeds 5 attached SCPs.
- [ ] Every taggable AWS resource carries all five `platform:*` keys **and** the
      legacy cost/audit tags; the TFLint `aws_resource_missing_tags` rule passes
      with an empty `exclude`.
- [ ] No real account IDs, ARNs-with-IDs, buckets, hostnames, emails, or non-RFC1918
      IPs appear in any `*.hcl`, `*.tf`, or `.tfvars`.
- [ ] Bootstrap order holds: management account first, then network, then workload
      accounts; a workload region deploys `vpc/secrets → eks → karpenter/monitoring/rds`.
- [ ] Changing a default in one `_envcommon/<module>.hcl` provably propagates to
      every consumer (verified via `grep -r "_envcommon/<module>.hcl" terragrunt/`).
- [ ] No `terraform apply` runs from a feature branch or agent — apply is CI/CD
      only, from `main` after merge.

---

## 9. Dependencies on other specs

This is the foundation spec; every other spec assumes the account topology,
Terragrunt layer, state backend, version pins, and tagging taxonomy defined here.
Downstream specs (numbers per `SPEC-INDEX.md`):

- **SPEC-00 Overview** — owns the shared placeholder registry (`{{ORG}}`,
  `{{DOMAIN}}`, `{{*_ACCOUNT_ID}}`, `{{PRIMARY_REGION}}`, `{{STATE_BUCKET}}`).
  This spec registers foundation-specific placeholders (§5) against it.
- **Networking & Connectivity** — VPC/CIDR (§4.6 here is the allocation table),
  hub-spoke Transit Gateway (ADR-0005), RAM sharing, ClusterMesh, inter-VPC
  security (ADR-0013), VPC Lattice (ADR-0023). Consumes the network account +
  `_envcommon/transit-gateway.hcl` defined here.
- **Security & Guardrails** — SCP/RCP *contents*, GuardDuty/SecurityHub/Config
  delegated-admin, IAM baseline, break-glass (ADR-0011), SSO permission sets,
  centralized logging (ADR-0017, ADR-0028 enforcement side). This spec fixes only
  *where* those attach (the OU tree).
- **Compute & Autoscaling** — EKS (`_envcommon/eks.hcl`), Karpenter (ADR-0007),
  KEDA/HPA/WPA, Bottlerocket (ADR-0030), node strategy (ADR-0046). Consumes the
  per-account sizing knobs in §5.
- **GitOps Delivery** — ArgoCD app-of-apps (ADR-0006), Kargo promotion (ADR-0021),
  and the `versions/` application-version-manifest system (distinct from
  `versions.hcl`: it is the Kargo→ArgoCD image-promotion source of truth, not the
  tool pins).
- **Account Vending (target state)** — Control Tower + AFT (ADR-0035), the
  `Deployments` OU tenant, and `docs/account-vending.md`. Supersedes the raw
  `terraform/modules/organization` bootstrap this spec currently documents.
- **Observability & FinOps** — depends on the ADR-0028 taxonomy (ADR-0026,
  ADR-0027) for the cross-plane joins.
