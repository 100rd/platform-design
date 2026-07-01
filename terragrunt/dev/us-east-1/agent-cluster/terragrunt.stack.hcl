# This stack defines the entire agent-cluster infrastructure.
# Terragrunt will deploy all modules listed here in the correct order based on dependencies.

# By default, all modules in this stack will share the same variables
# from region.hcl and env.hcl
generate "common_vars" {
  path      = "_common_vars.hcl"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
locals {
  # Include the region and env specific variables.
  aws_region = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals.aws_region
  env_vars   = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}
EOF
}


# Define the modules in the stack
modules = {
  "vpc" = {
    path = "./vpc.hcl"
  }

  "eks" = {
    path = "./eks.hcl"
    dependencies = ["vpc"]
  }

  "karpenter" = {
    path = "./karpenter.hcl"
    dependencies = ["eks"]
  }

  "cilium" = {
    path = "./cilium.hcl"
    dependencies = ["eks"]
  }

  "istio" = {
    path = "./istio.hcl"
    dependencies = ["eks"]
  }
  
  "keda" = {
    path = "./keda.hcl"
    dependencies = ["eks"]
  }
}
