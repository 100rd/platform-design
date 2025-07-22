# Terragrunt Configuration

This directory contains an example Terragrunt layout for managing the Terraform modules in this repository.
See `../docs/02-terragrunt-strategy.md` for details on the approach.

- `terragrunt.hcl` – root configuration with backend and provider settings.
- `envs/` – environment-specific folders (e.g., `dev`, `prod`). Each component within an environment references a Terraform module.
- `dependencies` blocks pass outputs between modules, keeping them decoupled and reusable.

To deploy, change into a component directory and run Terragrunt commands:

```bash
cd terragrunt/envs/dev/vpc
terragrunt init && terragrunt apply
```
