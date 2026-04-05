# ---------------------------------------------------------------------------------------------------------------------
# GitHub Actions OIDC — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Creates the GitHub OIDC provider and three IAM roles (terraform, readonly, ecr-push)
# for keyless CI authentication. Deploy in the management account and all workload accounts
# that CI workflows need to access.
#
# After deploying, update GitHub Actions workflows to use:
#   - uses: aws-actions/configure-aws-credentials@v4
#     with:
#       role-to-assume: <terraform_role_arn output>
#       aws-region: eu-west-1
#
# This replaces long-lived IAM access keys stored as GitHub secrets.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/github-oidc"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name = local.account_vars.locals.account_name
  environment  = local.account_vars.locals.environment
}

inputs = {
  project      = "platform-design"
  account_name = local.account_name
  repository   = "100rd/platform-design"
  branch       = "main"

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
  }
}
