# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform Cilium CNI — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Cilium as the CNI for the minimal-platform EKS cluster.
# Must be deployed AFTER minimal-platform-eks-cluster and BEFORE minimal-platform-eks-nodes.
#
# Deploy order:
#   vpc -> kms -> eks-cluster -> cilium (this unit) -> eks-nodes
#
# Key differences from the standard cilium catalog unit:
#   - enable_clustermesh = false (Decision 3: this stack is standalone, not part
#     of the multi-region mesh; saves ClusterMesh API server cost)
#   - cluster_name derived from dependency.eks_cluster.outputs.cluster_name (not hardcoded)
#   - cluster_oidc_issuer_url + cluster_oidc_provider_arn wired for IRSA
#     (Cilium operator needs EC2 ENI APIs; IRSA role created by the module)
#   - generate "k8s_providers" block for helm + kubernetes providers
#   - Extended mock_outputs covering cluster_certificate_authority_data,
#     cluster_name, cluster_oidc_issuer_url, and oidc_provider_arn
#
# Changed in Round 10.5: dependency renamed from "eks" (../eks) to
# "eks_cluster" (../eks-cluster) to reflect the cluster/nodes split.
# ---------------------------------------------------------------------------------------------------------------------

# Include root.hcl to activate remote_state (S3 backend generation) and provider
# generation. Without this block, terragrunt ignores root.hcl entirely — no
# backend.tf is generated and state falls back to local storage, which is lost
# on any cache clean (rm -rf .terragrunt-cache / .terragrunt-stack).
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/modules/cilium"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.account_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Minimal Platform EKS Cluster (control plane only)
# Points to eks-cluster unit — the split unit that has no node groups.
# This ensures Cilium is deployed after the control plane is ready but
# before any nodes join, breaking the CNI chicken-and-egg cycle.
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    cluster_endpoint                   = "https://XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX.gr7.eu-central-1.eks.amazonaws.com"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURCVENDQWUyZ0F3SUJBZ0lVV05KeEZHYWJ2Q1IvaHhzRkFoaVd4ZmpUa3hnd0RRWUpLb1pJaHZjTkFRRUwKQlFBd0VqRVFNQTRHQTFVRUF3d0hiVzlqYXkxallUQWVGdzB5TmpBMk1USXdPVFUyTkRWYUZ3MHlOekEyTVRJdwpPVFUyTkRWYU1CSXhFREFPQmdOVkJBTU1CMjF2WTJzdFkyRXdnZ0VpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElCCkR3QXdnZ0VLQW9JQkFRQ3BIWjFtbzRPN3FHWC9yK1hVZ2k1MmZoWW9oa1ZHdGNQM3FTY0FSa0I2ZlZsWnJ3ejUKQmtwRUE3VEdNKzVpYWVOcVU3NnFpRzBHOHEzS1lSbjBVaHdrak91NFBqd2dTekdsUVlGY0RKR3ZXWlJOeHNxWgp3ME1PcEhZYnY5anFpRzY2eE5hVmRnQmIvam9KMFZWQVh4QTJwdkM5YkpldWJEdTVvNnREbFNadDRTRDZYcmxMCkZTUHo0NVpUZXlTZ0tvUzhvdkVLNDNpMU1ianovUTUzS0d0SnNBaHZvREJ1bENLT21SK1pBZzNONDEzR0gyQS8KMG9iZ09uamxPYlpiRjdaLzl6SFcwMTQ4R0duOFMxY2V4VXM5ckVVaHNNRFQ3VGhWV1dyNU1zN01wNjdYLzBjLwo5OFgvM0k2aUd5cVlVNWFXTWo3WUx6VnVEUHNOcTJ0YnhnZWZBZ01CQUFHalV6QlJNQjBHQTFVZERnUVdCQlJLCiszWlFYd3pWTHhSSksrSnRtbWtydDJqTU9UQWZCZ05WSFNNRUdEQVdnQlJLKzNaUVh3elZMeFJKSytKdG1ta3IKdDJqTU9UQVBCZ05WSFJNQkFmOEVCVEFEQVFIL01BMEdDU3FHU0liM0RRRUJDd1VBQTRJQkFRQUR0VHFuSmZkVAovVjJjNU03THZvK0VVSHVaUVM3RzBoMHhDWnBBNC9TS2RHU2VSNWdmUThZa3V5MzdJRXM0MEk2Qy9pazZoUXZqCjhRcEswY2NybStvZmQ1OENmU1JaSnFOdjU0SCs1QmlibFF0YWRCa3JSQ1lVNlJMVG9wRHAwV3AydGJJK3BTdlMKQysrU2FGd1NNekRnRUNxQXlTMDZEeDA4eXNjK0cxbXFuaExCT0EwdnJLa1VwaWtaVFpyZC96Sk85Q2tPMmh4MApFNkZtTXVMTU9taHlhbWI1VVNCTktRRjBtc2FmaUtoOVRJTUlhTGdtVnVoWjQ4QmxhUUVvN1VNUW01OWtVVU5iCmIyc1RoK0RhK29PV212ZXd3WGdYN2NROEtGZVlVNXA3QVFrNkxjaVE4MDY1QkMyeTBNUThJVGxUQk5YcUJacjkKYVRnZFVvOFBMRkwvCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
    cluster_name                       = "staging-eu-central-1-minimal-platform"
    cluster_oidc_issuer_url            = "https://oidc.eks.eu-central-1.amazonaws.com/id/MOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCK"
    oidc_provider_arn                  = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/MOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCK"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# Kubernetes / Helm providers for Cilium deployment
# ---------------------------------------------------------------------------------------------------------------------

generate "k8s_providers" {
  path      = "k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "helm" {
      kubernetes {
        host                   = "${dependency.eks_cluster.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks_cluster.outputs.cluster_certificate_authority_data}")
        exec {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks_cluster.outputs.cluster_name}"]
        }
      }
    }

    provider "kubernetes" {
      host                   = "${dependency.eks_cluster.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks_cluster.outputs.cluster_certificate_authority_data}")
      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", "${dependency.eks_cluster.outputs.cluster_name}"]
      }
    }

    provider "kubectl" {
      host                   = "${dependency.eks_cluster.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks_cluster.outputs.cluster_certificate_authority_data}")
      load_config_file       = false
      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", "${dependency.eks_cluster.outputs.cluster_name}"]
      }
    }
  PROVIDERS
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  # Identity — required for IRSA role naming and OIDC trust policy
  cluster_name              = dependency.eks_cluster.outputs.cluster_name
  cluster_oidc_issuer_url   = dependency.eks_cluster.outputs.cluster_oidc_issuer_url
  cluster_oidc_provider_arn = dependency.eks_cluster.outputs.oidc_provider_arn

  cluster_endpoint = replace(dependency.eks_cluster.outputs.cluster_endpoint, "https://", "")

  # Round 13: Cilium operator needs AWS_REGION env var to call EC2 ENI APIs
  aws_region = local.aws_region

  cilium_version = "1.16.5"

  replace_kube_proxy = local.account_vars.locals.cilium_replace_kube_proxy

  # Hubble observability
  enable_hubble    = true
  enable_hubble_ui = true

  # Prometheus integration — requires ServiceMonitor CRD from prometheus-operator.
  # Disabled for this minimal stack (no monitoring deployed). Re-enable when
  # prometheus-operator is added to the stack.
  enable_service_monitor = false

  # ENI prefix delegation for higher pod density
  enable_prefix_delegation = true

  # Bandwidth manager for QoS
  enable_bandwidth_manager = true

  # Default deny policy — PCI-DSS Req 1.2
  # Round 13 finding: even kubectl_manifest validates CRD at apply time, and
  # CRDs don't propagate to API discovery instantly after helm_release completes.
  # Need time_sleep between helm and kubectl_manifest, or null_resource with
  # kubectl retries. Tracked as Round 14 fix; disabled for now to unblock
  # full apply chain validation.
  enable_default_deny = false

  # WireGuard transparent encryption — PCI-DSS Req 4.1
  enable_encryption = true
  encryption_type   = "wireguard"

  # HA for operator
  operator_replicas = local.environment == "prod" ? 2 : 1

  # Decision 3: ClusterMesh disabled — this stack is standalone and does not
  # participate in the multi-region service mesh.
  enable_clustermesh             = false
  cluster_mesh_name              = ""
  cluster_mesh_id                = 0
  clustermesh_apiserver_replicas = 2

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
