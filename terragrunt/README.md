# Terragrunt Infrastructure

This directory contains all the Terragrunt code for provisioning the platform's infrastructure on AWS.

## Directory Structure

The structure is designed to be DRY (Don't Repeat Yourself) and easily maintainable.

```
terragrunt/
├── README.md
├── envs/
│   ├── _common/            # Common configurations (backend, providers)
│   │   ├── backend.hcl
│   │   └── providers.hcl
│   ├── dev/                # Development environment
│   │   └── us-east-1/      # Deploys to the us-east-1 region
│   │       ├── env.hcl     # Environment-specific variables
│   │       ├── region.hcl  # Region-specific variables
│   │       └── eks-cluster/  # EKS stack for this env/region
│   │           └── terragrunt.hcl
│   └── prod/               # Production environment (mirrors dev)
│       └── us-east-1/
│           ├── env.hcl
│           ├── region.hcl
│           └── eks-cluster/
│               └── terragrunt.hcl
└── modules/
    ├── aws/                # Terraform modules for provisioning AWS resources
    │   ├── vpc/
    │   ├── eks-cluster/
    │   └── iam/
    └── kubernetes/         # Terraform modules for deploying K8s add-ons
        ├── karpenter/
        ├── cilium/
        ├── istio/
        ├── keda/
        └── external-secrets-operator/
```

### Explanation

- **`envs/`**: Contains the "live" configurations for each environment.
  - `_common/`: Holds shared configurations like the S3 backend for Terraform state, which is included by all other `terragrunt.hcl` files.
  - Each environment (`dev`, `prod`) is further divided by region. This allows for multi-region deployments in the future.
  - The `terragrunt.hcl` files in the leaf directories call the appropriate modules from `modules/` with the correct variables.

- **`modules/`**: Contains reusable Terraform modules.
  - `aws/`: For creating core AWS resources (e.g., a VPC, an EKS cluster, IAM roles).
  - `kubernetes/`: For deploying Kubernetes applications and controllers using the Terraform Helm or Kubernetes provider. This allows us to manage the entire stack, from the VPC to the in-cluster applications, with one tool.
