# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference DRA DeviceClass Definitions — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Kubernetes DeviceClass and ResourceClaimTemplate resources for
# DRA-based GPU allocation on the gpu-inference EKS cluster.
#
# Resources created:
#   DeviceClasses:
#     - nvidia-h100-sxm5     — CEL selector for H100 SXM5 (p5.48xlarge)
#     - nvidia-a100-80gb     — CEL selector for A100 80GB (p4d.24xlarge)
#   ResourceClaimTemplates:
#     - single-gpu-inference     — 1x H100 for inference
#     - full-node-training       — 8x H100 ExactCount for training (NVLink island)
#     - prioritized-gpu-inference — H100 preferred, A100 fallback
#
# Requires: EKS 1.35+ with DRA feature gate enabled (GA in 1.35).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-dra"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.account_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region
}

dependency "eks" {
  config_path = "../gpu-inference-eks"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURCVENDQWUyZ0F3SUJBZ0lVV05KeEZHYWJ2Q1IvaHhzRkFoaVd4ZmpUa3hnd0RRWUpLb1pJaHZjTkFRRUwKQlFBd0VqRVFNQTRHQTFVRUF3d0hiVzlqYXkxallUQWVGdzB5TmpBMk1USXdPVFUyTkRWYUZ3MHlOekEyTVRJdwpPVFUyTkRWYU1CSXhFREFPQmdOVkJBTU1CMjF2WTJzdFkyRXdnZ0VpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElCCkR3QXdnZ0VLQW9JQkFRQ3BIWjFtbzRPN3FHWC9yK1hVZ2k1MmZoWW9oa1ZHdGNQM3FTY0FSa0I2ZlZsWnJ3ejUKQmtwRUE3VEdNKzVpYWVOcVU3NnFpRzBHOHEzS1lSbjBVaHdrak91NFBqd2dTekdsUVlGY0RKR3ZXWlJOeHNxWgp3ME1PcEhZYnY5anFpRzY2eE5hVmRnQmIvam9KMFZWQVh4QTJwdkM5YkpldWJEdTVvNnREbFNadDRTRDZYcmxMCkZTUHo0NVpUZXlTZ0tvUzhvdkVLNDNpMU1ianovUTUzS0d0SnNBaHZvREJ1bENLT21SK1pBZzNONDEzR0gyQS8KMG9iZ09uamxPYlpiRjdaLzl6SFcwMTQ4R0duOFMxY2V4VXM5ckVVaHNNRFQ3VGhWV1dyNU1zN01wNjdYLzBjLwo5OFgvM0k2aUd5cVlVNWFXTWo3WUx6VnVEUHNOcTJ0YnhnZWZBZ01CQUFHalV6QlJNQjBHQTFVZERnUVdCQlJLCiszWlFYd3pWTHhSSksrSnRtbWtydDJqTU9UQWZCZ05WSFNNRUdEQVdnQlJLKzNaUVh3elZMeFJKSytKdG1ta3IKdDJqTU9UQVBCZ05WSFJNQkFmOEVCVEFEQVFIL01BMEdDU3FHU0liM0RRRUJDd1VBQTRJQkFRQUR0VHFuSmZkVAovVjJjNU03THZvK0VVSHVaUVM3RzBoMHhDWnBBNC9TS2RHU2VSNWdmUThZa3V5MzdJRXM0MEk2Qy9pazZoUXZqCjhRcEswY2NybStvZmQ1OENmU1JaSnFOdjU0SCs1QmlibFF0YWRCa3JSQ1lVNlJMVG9wRHAwV3AydGJJK3BTdlMKQysrU2FGd1NNekRnRUNxQXlTMDZEeDA4eXNjK0cxbXFuaExCT0EwdnJLa1VwaWtaVFpyZC96Sk85Q2tPMmh4MApFNkZtTXVMTU9taHlhbWI1VVNCTktRRjBtc2FmaUtoOVRJTUlhTGdtVnVoWjQ4QmxhUUVvN1VNUW01OWtVVU5iCmIyc1RoK0RhK29PV212ZXd3WGdYN2NROEtGZVlVNXA3QVFrNkxjaVE4MDY1QkMyeTBNUThJVGxUQk5YcUJacjkKYVRnZFVvOFBMRkwvCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

generate "k8s_providers" {
  path      = "k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "kubernetes" {
      host                   = "${dependency.eks.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_name}"]
      }
    }
  PROVIDERS
}

inputs = {
  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
