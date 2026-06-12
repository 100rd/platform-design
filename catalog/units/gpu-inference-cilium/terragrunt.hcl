# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Cilium v1.19 — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Cilium v1.19 in native-routing mode with BGP Control Plane peering
# to AWS Transit Gateway Connect for the gpu-inference cluster.
#
# Key differences from platform Cilium:
#   - Native routing (not ENI IPAM)
#   - BGP Control Plane enabled for TGW Connect peering
#   - Cluster-pool IPAM with Pod CIDR 100.64.0.0/10
#   - L7 proxy disabled (latency-sensitive GPU traffic)
#   - High-scale BPF map tuning (512k LB, 64k policy)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-cilium"
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

dependency "vpc" {
  config_path = "../gpu-inference-vpc"

  mock_outputs = {
    pod_cidr = "100.64.0.0/10"
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
  cilium_version   = "1.19.2"
  cluster_endpoint = replace(dependency.eks.outputs.cluster_endpoint, "https://", "")
  pod_cidr         = dependency.vpc.outputs.pod_cidr

  # High-scale tuning
  operator_replicas  = 2
  bpf_lb_map_max     = "512000"
  bpf_policy_map_max = "65536"

  # BGP peering — enable once TGW Connect peers are configured
  enable_bgp_peering = try(local.gpu_inference_config.enable_bgp_peering, false)
  bgp_local_asn      = try(local.gpu_inference_config.bgp_local_asn, 65100)
  bgp_peers          = try(local.gpu_inference_config.bgp_peers, [])

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
