# ---------------------------------------------------------------------------------------------------------------------
# EKS Cluster Configuration — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Reusable unit that provisions a managed Kubernetes cluster with IRSA support and a
# "system" managed node group using the terraform-aws-modules/eks/aws registry module.
#
# The cluster is placed in the private subnets of the VPC and tagged for Karpenter discovery.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "tfr:///terraform-aws-modules/eks/aws?version=21.15.1"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  cluster_name = "${local.environment}-${local.aws_region}-platform"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: VPC
# ---------------------------------------------------------------------------------------------------------------------

dependency "vpc" {
  config_path = "../vpc"

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

  # Endpoint access
  # Dev environments allow public access for developer convenience; staging/prod are private only.
  cluster_endpoint_public_access  = local.account_vars.locals.eks_public_access
  cluster_endpoint_private_access = true

  # IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # ---------------------------------------------------------------------------
  # Node security group tags for Karpenter auto-discovery
  # ---------------------------------------------------------------------------
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  # ---------------------------------------------------------------------------
  # Managed node groups
  # The "system" group runs cluster-critical workloads (CoreDNS, kube-proxy, etc.)
  # Instance types and scaling parameters are defined per environment in account.hcl.
  # ---------------------------------------------------------------------------
  eks_managed_node_groups = {
    system = {
      instance_types = local.account_vars.locals.eks_instance_types
      min_size       = local.account_vars.locals.eks_min_size
      max_size       = local.account_vars.locals.eks_max_size
      desired_size   = local.account_vars.locals.eks_desired_size
    }
  }

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
