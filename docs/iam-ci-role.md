# Terraform CI/CD IAM Role (GitHub OIDC)

This document describes the IAM roles created by the
`terraform/modules/github-oidc` module for keyless GitHub Actions
authentication, and explains why the Terraform execution role no longer uses
`AdministratorAccess`.

Closes issue #173. Builds on the scoped policies authored under issue #69.

## Background

GitHub Actions assumes AWS IAM roles via OpenID Connect (OIDC) — no long-lived
access keys are stored as repository secrets. The `github-oidc` module is
deployed in the management account and every workload account that CI needs to
reach. It creates one OIDC provider and three roles per account.

## Role types

| Role | Name suffix | OIDC subjects (who can assume) | Permissions | Purpose |
|------|-------------|--------------------------------|-------------|---------|
| **terraform** | `-terraform` | `main` branch + `environment:<account>` + `extra_subjects` | **Scoped per-account-type policy** (see below) | `terraform plan` + `apply` from trusted workflows |
| **readonly** | `-terraform-plan` | `pull_request` | AWS-managed `ReadOnlyAccess` | PR plan-only workflows — safe, no writes |
| **ecr-push** | `-ecr-push` | `main` branch + `refs/tags/*` | Least-privilege ECR push policy | Container build/publish workflows |

Only the **terraform** role changed in issue #173. The `readonly`
(`ReadOnlyAccess`) and `ecr-push` (custom ECR policy) roles are unchanged.

## Why `AdministratorAccess` was removed

The terraform role previously attached
`arn:aws:iam::aws:policy/AdministratorAccess` (`*:*` on `*`). That is the
single most over-privileged grant in the platform: any workflow able to assume
the role — or any compromise of the GitHub Actions supply chain — would have
unrestricted control of the whole AWS account.

Issue #173 replaces that blanket grant with **per-account-type scoped
policies**: the role in each account receives permissions only for the AWS
services that account's Terraform stacks actually manage. This shrinks the blast
radius of a CI compromise from "full account takeover" to "the services this
account already operates", while keeping `plan`/`apply` working everywhere.

The scoped policies are deliberately broader than a human-user policy (Terraform
must be able to **create, modify, and destroy** the resources it manages, so it
uses service-level wildcards such as `s3:*`, `eks:*`, `kms:*`), but they are
bounded by:

1. **Service scoping** — only the services relevant to that account type.
2. **The SCP layer** — e.g. `DenyS3Public`, `RestrictRegions`, `DenyRootAccount`
   (see [`ou-structure.md`](ou-structure.md)) constrain what the role can do
   even within those services.
3. **State-resource scoping** — the `TerraformState` statement is restricted to
   this account's own `*-tfstate-<account>-*` buckets and the
   `*-terraform-locks` DynamoDB table by ARN.

## Scoped permission sets per account type

Defined in `terraform/modules/github-oidc/policies.tf`. Each account receives
**exactly one** policy. Routing is controlled by
`local.dedicated_scoped_accounts = ["log-archive", "network", "shared"]`:
those three get dedicated narrow policies; every other account
(`dev`, `staging`, `prod`, `dr`, `security`, `sandbox`, `management`,
`third-party`) falls through to the broader **workload** policy.

| Account(s) | Policy resource | Service scope |
|------------|-----------------|---------------|
| `log-archive` | `aws_iam_policy.log_archive` | `s3:*`, `kms:*`, `logs:*`, `cloudwatch:*`, scoped IAM, Terraform state |
| `network` | `aws_iam_policy.network` | EC2 networking (`*Vpc*`, `*Subnet*`, `*TransitGateway*`, …), `route53:*`, `route53resolver:*`, `ram:*`, `kms:*`, scoped IAM, Terraform state |
| `shared` | `aws_iam_policy.shared` | `ecr:*`, `kms:*`, `secretsmanager:*`, `s3:*`, scoped IAM (incl. policy management), Terraform state |
| `dev`, `staging`, `prod`, `dr`, `security`, `sandbox`, `management`, `third-party` | `aws_iam_policy.workload` | `eks:*`, `ec2:*`, `elasticloadbalancing:*`, `rds:*`, `s3:*`, `kms:*`, `secretsmanager:*`, `logs:*`/`cloudwatch:*`, `autoscaling:*`, scoped IAM (incl. instance profiles + policy management), Terraform state |

The `workload` policy is the **catch-all default** so the terraform role in
*every* account always has a concrete, non-empty, non-admin policy. This is what
guarantees `plan`/`apply` keeps working across all account types — including the
general-purpose accounts (`dr`, `security`, `sandbox`, `management`,
`third-party`) that do not have a dedicated narrow policy.

### How the wiring works

`policies.tf` declares the four policies with `count` so exactly one is created
per account. `main.tf` resolves the active one and attaches it:

```hcl
locals {
  terraform_scoped_policy_arn = coalesce(
    one(aws_iam_policy.log_archive[*].arn),
    one(aws_iam_policy.network[*].arn),
    one(aws_iam_policy.shared[*].arn),
    one(aws_iam_policy.workload[*].arn),
  )
}

module "terraform_role" {
  # ...
  policies = {
    TerraformScoped = local.terraform_scoped_policy_arn
  }
}
```

`one(...)` returns the single created ARN (or `null` when that policy's
`count` is 0); `coalesce` picks whichever dedicated policy matched, falling back
to the always-present `workload` policy. The result is never `null` and never
`AdministratorAccess`.

## How to extend permissions for a new module

When a new Terraform module needs an AWS service the scoped role cannot yet
reach, `apply` will fail in CI with an `AccessDenied` (or `is not authorized to
perform`) error. To extend:

1. **Identify the account type** that runs the new module
   (`terragrunt/<account>/account.hcl` → `account_name`).
2. **Find the matching policy** in `policies.tf`:
   - `log-archive` / `network` / `shared` → the dedicated policy of that name.
   - any other account → `aws_iam_policy.workload`.
3. **Add a new statement** (preferred) or extend an existing one with the
   minimum actions the module needs. Use a descriptive `Sid` and keep
   `Resource` as tight as practical.
4. If the new account type warrants its own narrow policy, add a new
   `count`-gated `aws_iam_policy` resource, add its name to
   `local.dedicated_scoped_accounts`, and add a matching `one(...)` line to the
   `coalesce` in `main.tf`.
5. **Verify** with `terraform fmt`, `init`, `validate`, and a `plan` for the
   affected account before opening a PR. Never widen a policy back to
   `AdministratorAccess` or `*:*`.

### Refining the scopes over time

The scoped policies start intentionally generous (service-level wildcards) to
guarantee `apply` keeps working on day one. To tighten them:

1. Enable **IAM Access Analyzer** policy generation on the terraform role.
2. Let CI run real `plan`/`apply` cycles for ~30 days to capture actual API
   usage.
3. Replace the wildcard actions with the generated least-privilege action list.

## Security suppressions

`policies.tf` carries `trivy:ignore:AVD-AWS-0345` suppressions on the `s3:*`
statements. These are intentional: a Terraform execution role must be able to
create, configure, and destroy S3 buckets (policies, lifecycle, encryption,
public-access-block). Bucket exposure is prevented by the `DenyS3Public` SCP at
the org layer, not by withholding `s3:*` from Terraform.

## References

- Issue #173 — scope-down Terraform CI/CD IAM role (this change)
- Issue #69 — authored the scoped policies in `policies.tf`
- [`ou-structure.md`](ou-structure.md) — OU hierarchy and SCP attachment matrix
- [`scps.md`](scps.md) — Service Control Policy guardrails
- `terraform/modules/github-oidc/` — module source
- `catalog/units/github-oidc/terragrunt.hcl` — deployment unit
- terraform-aws-modules/iam — upstream module providing the OIDC role primitives
