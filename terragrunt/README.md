# Terragrunt Infrastructure

Multi-account, multi-region AWS infrastructure managed with Terragrunt following the Gruntwork Reference Architecture pattern.

## Structure

```
terragrunt/
├── terragrunt.hcl          # Root: remote state, provider generation, version constraints
├── _envcommon/              # DRY shared module configurations
│   ├── vpc.hcl              # VPC with CIDR map, subnets, NAT gateways
│   ├── eks.hcl              # EKS cluster with managed node groups
│   ├── karpenter.hcl        # Karpenter autoscaler for EKS
│   ├── monitoring.hcl       # Prometheus + Grafana stack
│   ├── rds.hcl              # PostgreSQL RDS instance
│   └── secrets.hcl          # AWS Secrets Manager paths
├── <env>/                   # dev | staging | prod | dr
│   ├── account.hcl          # AWS account ID + name
│   ├── env.hcl              # Environment sizing defaults
│   └── <region>/            # eu-west-1 | eu-west-2 | eu-west-3 | eu-central-1
│       ├── region.hcl       # Region name, short code, AZs
│       ├── vpc/terragrunt.hcl
│       ├── eks/terragrunt.hcl
│       ├── karpenter/terragrunt.hcl
│       ├── monitoring/terragrunt.hcl
│       ├── rds/terragrunt.hcl
│       └── secrets/terragrunt.hcl
```

## Environments

| Environment | AWS Account | Purpose |
|-------------|-------------|---------|
| dev         | 111111111111 | Development and experimentation |
| staging     | 222222222222 | Pre-production validation |
| prod        | 333333333333 | Production workloads |
| dr          | 444444444444 | Disaster recovery |

## Regions

| Region | Short Code | Location |
|--------|-----------|----------|
| eu-west-1 | euw1 | Ireland |
| eu-west-2 | euw2 | London |
| eu-west-3 | euw3 | Paris |
| eu-central-1 | euc1 | Frankfurt |

## CIDR Allocation

No overlaps across any environment/region combination.

| Env     | eu-west-1    | eu-west-2    | eu-west-3    | eu-central-1  |
|---------|-------------|-------------|-------------|---------------|
| dev     | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 | 10.3.0.0/16  |
| staging | 10.10.0.0/16| 10.11.0.0/16| 10.12.0.0/16| 10.13.0.0/16 |
| prod    | 10.20.0.0/16| 10.21.0.0/16| 10.22.0.0/16| 10.23.0.0/16 |
| dr      | 10.30.0.0/16| 10.31.0.0/16| 10.32.0.0/16| 10.33.0.0/16 |

## Dependency Chain

Per region, modules deploy in this order:

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

### Deploy a single module

```bash
cd dev/eu-west-1/vpc
terragrunt apply
```

### Deploy all modules in a region

```bash
cd dev/eu-west-1
terragrunt run-all apply
```

### Deploy entire environment

```bash
cd dev
terragrunt run-all apply
```

### Plan all changes in a region

```bash
cd staging/eu-west-1
terragrunt run-all plan
```

### Validate configuration

```bash
cd dev/eu-west-1/vpc
terragrunt validate
```

### View dependency graph

```bash
cd dev/eu-west-1
terragrunt graph-dependencies
```

## Environment Sizing

| Setting | dev | staging | prod | dr |
|---------|-----|---------|------|----|
| NAT Gateway | Single | HA (per-AZ) | HA (per-AZ) | Single |
| EKS Public Access | Yes | No | No | No |
| EKS Instance Type | m6i.large | m6i.xlarge | m6i.2xlarge | m6i.xlarge |
| EKS Nodes (min/desired/max) | 1/2/3 | 2/3/5 | 3/5/10 | 1/2/5 |
| RDS Instance | db.t4g.medium | db.r6g.large | db.r6g.xlarge | db.r6g.large |
| RDS Multi-AZ | No | Yes | Yes | Yes |
| RDS Storage (GB) | 20 | 50 | 100 | 50 |
| Monitoring Replicas | 1 | 2 | 3 | 1 |

## Prerequisites

- Terraform >= 1.5.0
- Terragrunt >= 0.67.0
- AWS CLI configured with access to target accounts
- IAM role `TerragruntDeployRole` in each account

## Setup

1. Update `account.hcl` files with real AWS account IDs
2. Ensure S3 buckets and DynamoDB tables exist (Terragrunt auto-creates them)
3. Configure AWS credentials for cross-account access
4. Deploy from dev first, then promote through environments
