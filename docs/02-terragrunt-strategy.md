# Terragrunt Strategy

This document describes how Terragrunt can manage the Terraform modules in this repository.
It focuses on reusable modules, remote state management, and inter-module dependencies.

## Goals

- Keep Terraform modules reusable and versioned
- Provide a clear directory layout for multiple environments
- Use Terragrunt dependencies to pass outputs between modules
- Enable remote state locking in S3 and DynamoDB
- Support GitOps workflows by minimizing manual steps

## Directory Layout

```
terragrunt/
  terragrunt.hcl        # root configuration (backend, provider)
  envs/
    dev/
      terragrunt.hcl    # environment-level settings
      vpc/              # infrastructure layer
        terragrunt.hcl
      eks/
        terragrunt.hcl
    prod/
      ...               # similar structure for production
```

Each component directory (`vpc`, `eks`, etc.) references a module from the `terraform/modules` directory.

## Remote State

The root `terragrunt.hcl` configures an S3 backend and DynamoDB table for state locking. Each module stores its state in a key derived from the directory structure.

## Dependencies

Terragrunt's `dependencies` block links components. For example, the EKS configuration depends on the VPC module and consumes its outputs:

```hcl
dependencies {
  paths = ["../vpc"]
}

inputs = {
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnets
  # additional inputs...
}
```

This ensures modules remain decoupled while allowing data to flow between them.

## Usage

Initialize and apply any module with Terragrunt:

```bash
cd terragrunt/envs/dev/vpc
terragrunt init
terragrunt apply
```

Terragrunt automatically handles remote state configuration and downloads the Terraform modules.

### Spinning up an environment

From the root of an environment directory you can deploy all components with a single command. For example, to bring up the entire development stack run:

```bash
cd terragrunt/envs/dev
terragrunt run-all apply
```

Terragrunt traverses all child directories and applies them in the correct order based on their defined dependencies.

## Benefits

- **Modularity** – each environment references the same Terraform modules
- **Security** – remote state stored securely in S3 with encryption and locking
- **Consistency** – shared backend and provider settings reduce duplication
- **GitOps Ready** – straightforward to integrate with CI/CD pipelines and ArgoCD

