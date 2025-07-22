# Terraform Infrastructure Stack

This directory provisions a basic AWS infrastructure stack consisting of:

- **VPC** with three public and three private subnets across available zones
- **EKS** cluster using two managed node groups:
  - On-demand instances
  - Spot instances
- Optional worker nodes on Hetzner Cloud using `hcloud`

The modules are thin wrappers around the official AWS modules and can be used in
GitOps workflows.

## Usage

```bash
terraform init
terraform plan -out plan.tfplan
terraform apply plan.tfplan
```

Variables such as the AWS region and cluster name can be overridden via a
`terraform.tfvars` file or environment variables.
