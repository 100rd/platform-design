# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Volcano v1.8 — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Volcano batch scheduler as a secondary scheduler on the gpu-inference
# cluster. Includes gang scheduling, bin-packing, fair-share queues,
# and DRA plugin integration for GPU resource allocation.
#
# Key capabilities:
#   - Gang scheduling for multi-pod GPU jobs (ensures all-or-nothing allocation)
#   - Bin-packing to maximise GPU node utilisation
#   - Fair-share queues: training (weight 10), inference (weight 5), batch (weight 2)
#   - DRA plugin for Kubernetes Dynamic Resource Allocation (GPU device partitioning)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-volcano"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment          = local.account_vars.locals.environment
  aws_region           = local.region_vars.locals.aws_region
  gpu_inference_config = try(local.account_vars.locals.gpu_inference_config, {})
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
    provider "helm" {
      kubernetes {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
        exec {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_name}"]
        }
      }
    }

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
  chart_version = try(local.gpu_inference_config.volcano_chart_version, "1.8.2")

  scheduler_replicas  = 2
  controller_replicas = 2

  # Queue weights — higher value = proportionally more cluster resources
  training_queue_weight  = try(local.gpu_inference_config.volcano_training_queue_weight, 10)
  inference_queue_weight = try(local.gpu_inference_config.volcano_inference_queue_weight, 5)
  batch_queue_weight     = try(local.gpu_inference_config.volcano_batch_queue_weight, 2)

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
