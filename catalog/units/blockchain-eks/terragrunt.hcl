# ---------------------------------------------------------------------------------------------------------------------
# Blockchain EKS Cluster — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a dedicated EKS cluster for blockchain HPC workloads (Ethereum execution,
# consensus, and MEV trading).
#
# Key differences from platform EKS:
#   - Always private endpoint (no public access)
#   - System node group sizing from blockchain_config
#   - Tagged with ClusterRole = "blockchain"
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "tfr:///terraform-aws-modules/eks/aws?version=21.15.1"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name      = local.account_vars.locals.account_name
  aws_region        = local.region_vars.locals.aws_region
  environment       = local.account_vars.locals.environment
  blockchain_config = local.account_vars.locals.blockchain_config

  cluster_name = "${local.environment}-${local.aws_region}-blockchain"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Blockchain VPC
# ---------------------------------------------------------------------------------------------------------------------

dependency "vpc" {
  config_path = "../blockchain-vpc"

  mock_outputs = {
    vpc_id          = "vpc-00000000000000000"
    private_subnets = ["subnet-00000000000000000", "subnet-11111111111111111", "subnet-22222222222222222"]
    intra_subnets   = ["subnet-33333333333333333", "subnet-44444444444444444", "subnet-55555555555555555"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  cluster_name    = local.cluster_name
  cluster_version = "1.32"

  # Networking
  vpc_id                   = dependency.vpc.outputs.vpc_id
  subnet_ids               = dependency.vpc.outputs.private_subnets
  control_plane_subnet_ids = dependency.vpc.outputs.private_subnets

  # Always private for blockchain clusters — no public access
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  # IRSA
  enable_irsa = true

  # ---------------------------------------------------------------------------
  # Cluster Addons (Cilium deployed separately)
  # ---------------------------------------------------------------------------
  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        tolerations = [
          {
            key      = "node.cilium.io/agent-not-ready"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]
      })
    }
    kube-proxy = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  # ---------------------------------------------------------------------------
  # Node security group tags for Karpenter auto-discovery
  # ---------------------------------------------------------------------------
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  # ---------------------------------------------------------------------------
  # Managed node groups — system group for cluster-critical workloads
  # ---------------------------------------------------------------------------
  eks_managed_node_groups = {
    system = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = try(local.blockchain_config.eks_instance_types, ["m6i.xlarge"])
      min_size       = try(local.blockchain_config.eks_min_size, 2)
      max_size       = try(local.blockchain_config.eks_max_size, 4)
      desired_size   = try(local.blockchain_config.eks_desired_size, 2)

      platform = "bottlerocket"

      taints = {
        cilium = {
          key    = "node.cilium.io/agent-not-ready"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = {
    Environment = local.environment
    ClusterRole = "blockchain"
    ManagedBy   = "terragrunt"
  }
}
