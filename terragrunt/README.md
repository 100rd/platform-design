# Terragrunt Infrastructure — Stacks Pattern

Multi-account, multi-region AWS infrastructure managed with Terragrunt Stacks following the Gruntwork Reference Architecture.

## Structure

```
project/platform-design/
├── catalog/                              # Reusable infrastructure catalog
│   ├── units/                            # Terragrunt units (self-contained modules)
│   │   ├── vpc/terragrunt.hcl            # VPC with CIDR map, subnets, NAT gateways
│   │   ├── eks/terragrunt.hcl            # EKS cluster with managed node groups
│   │   ├── karpenter/terragrunt.hcl      # Karpenter autoscaler for EKS
│   │   ├── rds/terragrunt.hcl            # PostgreSQL RDS instance
│   │   ├── monitoring/terragrunt.hcl     # Prometheus + Grafana stack
│   │   └── secrets/terragrunt.hcl        # AWS Secrets Manager paths
│   └── stacks/                           # Composable stack templates
│       └── platform/terragrunt.stack.hcl # Full platform: VPC+EKS+Karpenter+RDS+Monitoring+Secrets
│
├── terragrunt/                           # Live infrastructure config
│   ├── root.hcl                          # Root: remote state, provider generation, includes
│   ├── versions.hcl                      # Pinned tool + provider versions (single source of truth)
│   ├── common.hcl                        # Shared locals (project metadata, tag conventions)
│   ├── mise.toml                         # Tool version pinning (terraform 1.10, terragrunt 0.68)
│   ├── _envcommon/                       # Shared per-module configs
│   │   ├── eks.hcl
│   │   ├── vpc.hcl
│   │   ├── kms.hcl
│   │   ├── transit-gateway.hcl
│   │   ├── budgets.hcl
│   │   ├── centralized-logging.hcl
│   │   └── README.md
│   ├── <account>/                        # _org | security | log-archive | network | shared
│   │   │                                 # | dev | staging | prod | dr | third-party
│   │   ├── account.hcl                   # AWS account_id, email, org_ou, sizing defaults
│   │   ├── _global/                      # Account-wide resources (not region-specific)
│   │   │   └── iam/terragrunt.hcl        # IAM roles, policies, cross-account access
│   │   └── <region>/                     # eu-west-1 | eu-west-2 | eu-west-3 | eu-central-1
│   │       ├── region.hcl                # Region name, short code, AZs
│   │       └── platform/                 # Stack deployment
│   │           └── terragrunt.stack.hcl  # References catalog units
│
└── terraform/modules/                    # Custom Terraform modules (referenced by catalog units)
```

## Accounts

The Control Tower landing zone (issue #157) defines nine accounts. Each top-level
folder under `terragrunt/` corresponds to one AWS account and carries `account.hcl`
+ `eu-west-1/region.hcl`. OU placement is defined in #158.

| Folder         | AWS Account  | OU              | Purpose                                            |
|----------------|--------------|-----------------|----------------------------------------------------|
| `_org/`        | 000000000000 | Root            | Organization management account (Control Tower hub) |
| `security/`    | 777777777777 | Security        | Delegated admin: GuardDuty, SecurityHub, Detective, Inspector, Macie |
| `log-archive/` | 888888888888 | Security        | Centralized log bucket (CloudTrail, Config, VPC Flow, EKS audit)     |
| `network/`     | 555555555555 | Infrastructure  | Transit Gateway hub, Route53 resolver, inspection VPC                |
| `shared/`      | 999999999999 | Infrastructure  | Shared services: ECR, Route53 private zones, ACM authority           |
| `dev/`         | 111111111111 | Non-Production  | Development workloads                                                |
| `staging/`     | 222222222222 | Non-Production  | Pre-production validation (canonical name: `stage`)                  |
| `prod/`        | 333333333333 | Production      | Production workloads                                                 |
| `dr/`          | 444444444444 | Production      | Disaster recovery for prod                                           |
| `third-party/` | 121212121212 | Security        | Vendor IAM principals (Datadog, Vanta, Snyk) — narrow cross-org trust |

**Account.hcl shape**: every per-account file declares `account_name`, `account_id`,
`email`, `org_ou`, `environment`, `owner`, `cost_center`. Sizing knobs (NAT posture,
EKS node groups, RDS class, etc.) live in workload accounts only.

> Note: this repo originally used `staging/` for pre-prod; Control Tower / source
> reference call it `stage`. We keep `staging/` for backwards compatibility — it
> satisfies the `stage` slot in the canonical 9-account structure.

## Regions

| Region       | Short Code | Location  |
|-------------|-----------|-----------|
| eu-west-1    | euw1      | Ireland   |
| eu-west-2    | euw2      | London    |
| eu-west-3    | euw3      | Paris     |
| eu-central-1 | euc1      | Frankfurt |

## CIDR Allocation

No overlaps across any environment/region combination.

| Env     | eu-west-1     | eu-west-2     | eu-west-3     | eu-central-1   |
|---------|--------------|--------------|--------------|----------------|
| dev     | 10.0.0.0/16  | 10.1.0.0/16  | 10.2.0.0/16  | 10.3.0.0/16   |
| staging | 10.10.0.0/16 | 10.11.0.0/16 | 10.12.0.0/16 | 10.13.0.0/16  |
| prod    | 10.20.0.0/16 | 10.21.0.0/16 | 10.22.0.0/16 | 10.23.0.0/16  |
| dr      | 10.30.0.0/16 | 10.31.0.0/16 | 10.32.0.0/16 | 10.33.0.0/16  |

## Dependency Chain

Per region, units deploy in this order (managed automatically by Terragrunt):

```
Phase 1 (parallel): vpc, secrets
Phase 2:            eks (depends on vpc)
Phase 3 (parallel): karpenter (depends on eks)
                     monitoring (depends on eks)
                     rds (depends on vpc, eks, secrets)
```

## Remote State

- **S3 Bucket**: `tfstate-{account_name}-{region}` (one per account per region)
- **DynamoDB Table**: `terraform-locks-{account_name}` (one per account)
- **State Key**: `{environment}/{path_relative_to_include()}/terraform.tfstate`

## Usage

### Deploy a full platform stack

```bash
cd terragrunt/dev/eu-west-1/platform
terragrunt stack apply
```

### Plan all units in a stack

```bash
cd terragrunt/dev/eu-west-1/platform
terragrunt stack plan
```

### Validate a stack

```bash
cd terragrunt/dev/eu-west-1/platform
terragrunt stack validate
```

### Deploy a single unit from a stack

```bash
cd terragrunt/dev/eu-west-1/platform/vpc
terragrunt apply
```

### Deploy entire environment (all regions)

```bash
cd terragrunt/dev
terragrunt run-all apply
```

### View dependency graph

```bash
cd terragrunt/dev/eu-west-1/platform
terragrunt graph-dependencies
```

## Environment Sizing

All sizing parameters are defined in each environment's `account.hcl`:

| Setting                       | dev         | staging      | prod          | dr           |
|-------------------------------|-------------|-------------|---------------|-------------|
| NAT Gateway                   | Single      | HA (per-AZ) | HA (per-AZ)  | Single      |
| EKS Public Access             | Yes         | No          | No            | No          |
| EKS Instance Type             | m6i.large   | m6i.xlarge  | m6i.2xlarge   | m6i.xlarge  |
| EKS Nodes (min/desired/max)   | 1/2/3       | 2/3/5       | 3/5/10        | 1/2/5       |
| RDS Instance                  | db.t4g.medium| db.r6g.large| db.r6g.xlarge | db.r6g.large|
| RDS Multi-AZ                  | No          | Yes         | Yes           | Yes         |
| RDS Storage (GB)              | 20          | 50          | 100           | 50          |
| Monitoring Replicas           | 1           | 2           | 3             | 1           |

## Prerequisites

- Terraform >= 1.11.0
- Terragrunt >= 0.68.0
- AWS CLI configured with access to target accounts
- IAM role `TerragruntDeployRole` in each account

## Setup

1. Install tool versions: `mise install` (uses `mise.toml`)
2. Update `account.hcl` files with real AWS account IDs
3. Ensure S3 buckets and DynamoDB tables exist (Terragrunt auto-creates them)
4. Configure AWS credentials for cross-account access
5. Deploy from dev first, then promote through environments

## Catalog Architecture

The catalog separates **what** to deploy (units) from **where** to deploy it (live tree):

- **Units** (`catalog/units/`) — Self-contained Terragrunt configurations that define a single infrastructure component. They read hierarchy files (`account.hcl`, `region.hcl`) from the live tree via `find_in_parent_folders`.
- **Stacks** (`catalog/stacks/`) — Compose multiple units into a deployable group. The `platform` stack includes all 6 infrastructure units.
- **Live tree** (`terragrunt/`) — Environment and region directories containing `account.hcl`, `region.hcl`, and `terragrunt.stack.hcl` files that reference the catalog.

## Root skeleton — versions.hcl, common.hcl, _envcommon/

The root layout is split across three sibling files for separation of concerns:

| File           | Owns                                                                 |
|----------------|----------------------------------------------------------------------|
| `root.hcl`     | Remote state, provider generation, version generation, retry policy, default tags. |
| `versions.hcl` | Pinned tool + provider versions. **Single source of truth** — no version literal lives anywhere else. |
| `common.hcl`   | Repo-wide locals: project metadata, tag schema, canonical region catalog. |
| `_envcommon/`  | One file per module (`eks.hcl`, `vpc.hcl`, `kms.hcl`, ...) holding the module source pin, common inputs, and shared dependency declarations. New per-env units include from here. See [`_envcommon/README.md`](_envcommon/README.md). |

### Directory-vs-Helm-values disambiguation

Two top-level directories use the word "env":

- `terragrunt/<env>/...` — the **canonical Terragrunt live tree** (this README's subject). All Terraform-driven AWS resources live here.
- `envs/<env>/values/...` — **Helm values overrides** consumed by ArgoCD ApplicationSets and Kargo (see `argocd/` and `kargo/`). These are NOT Terragrunt configs and never include `root.hcl`.

There is no parallel Terragrunt layout. Any new IaC unit goes under
`terragrunt/<env>/<region>/<module>/` and includes the shared `_envcommon/<module>.hcl` config.

## Layout decision (issue #156)

The canonical layout described above (`root.hcl` + `versions.hcl` + `common.hcl` + `_envcommon/` + per-env hierarchy) is mandatory for every new Terragrunt unit. Existing units that pre-date this skeleton continue to work without modification — the skeleton is additive: `root.hcl` reads `versions.hcl` and `common.hcl` for its version constraints and tag values, which means existing units that include `root.hcl` automatically pick up the new pins.

When migrating an existing unit to use `_envcommon`:
1. Replace inline `terraform { source = ... }` with `include "envcommon" { path = find_in_parent_folders("_envcommon/<module>.hcl") ... }`.
2. Strip duplicated default inputs from the unit's own `inputs` block.
3. `terragrunt run-all plan` shows zero diff if `_envcommon` defaults match the previously-inline values.
