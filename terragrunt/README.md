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
│   ├── root.hcl                          # Root: remote state, provider generation, versions
│   ├── mise.toml                         # Tool version pinning (terraform 1.10, terragrunt 0.68)
│   ├── <env>/                            # dev | staging | prod | dr
│   │   ├── account.hcl                   # AWS account ID, name, environment, sizing defaults
│   │   ├── _global/                      # Account-wide resources (not region-specific)
│   │   │   └── iam/terragrunt.hcl        # IAM roles, policies, cross-account access
│   │   └── <region>/                     # eu-west-1 | eu-west-2 | eu-west-3 | eu-central-1
│   │       ├── region.hcl                # Region name, short code, AZs
│   │       └── platform/                 # Stack deployment
│   │           └── terragrunt.stack.hcl  # References catalog units
│
└── terraform/modules/                    # Custom Terraform modules (referenced by catalog units)
```

## Environments

| Environment | AWS Account  | Purpose                      |
|-------------|-------------|------------------------------|
| dev         | 111111111111 | Development and experimentation |
| staging     | 222222222222 | Pre-production validation    |
| prod        | 333333333333 | Production workloads         |
| dr          | 444444444444 | Disaster recovery            |

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

- Terraform >= 1.5.0
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
