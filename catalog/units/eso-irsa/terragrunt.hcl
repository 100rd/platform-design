# ---------------------------------------------------------------------------------------------------------------------
# ESO IRSA — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Binds the External Secrets Operator Kubernetes service account to an IAM role via IRSA.
# Resolves dependencies for KMS and EKS OIDC provider to generate the correct trust policy.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/eso-irsa"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  environment  = local.account_vars.locals.environment
  aws_region   = local.region_vars.locals.aws_region
}

# DEPENDENCY: EKS (for OIDC Provider ARN)
dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/mock-eks-oidc-id"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# DEPENDENCY: KMS (for Secrets Manager decryption key)
dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "secrets-manager" = "arn:aws:kms:eu-west-1:123456789012:key/mock-secrets-key-id"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  project           = "platform-design"
  environment       = local.environment
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  kms_key_arns      = [dependency.kms.outputs.key_arns["secrets-manager"]]

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
  }
}
