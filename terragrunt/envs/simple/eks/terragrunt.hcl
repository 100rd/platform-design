# EKS Configuration with Karpenter for Simple Environment
# This creates an EKS cluster with Karpenter autoscaling ready for multi-arch workloads

include {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../terraform/modules/eks"
}

# Dependency on VPC module
dependency "vpc" {
  config_path = "../vpc"

  # Mock outputs for planning
  mock_outputs = {
    vpc_id          = "vpc-mock123456"
    private_subnets = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

locals {
  # Get environment name from parent
  env_vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  env      = local.env_vars.locals.env

  # Cluster configuration
  cluster_name = "simple-eks-cluster"
}

inputs = {
  # Cluster configuration
  cluster_name    = local.cluster_name
  cluster_version = "1.34"  # Latest Kubernetes version

  # VPC configuration from dependency
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnets

  # Karpenter controller node group configuration
  # These nodes run Karpenter controller and system pods
  # Application workloads will run on Karpenter-provisioned nodes
  karpenter_controller_instance_types = ["t3.medium"]
  karpenter_controller_min_size       = 2
  karpenter_controller_max_size       = 3
  karpenter_controller_desired_size   = 2

  # Additional IAM policies for Karpenter nodes (optional)
  # Uncomment to add SSM access for debugging
  # karpenter_node_iam_role_additional_policies = {
  #   AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  # }

  # Tags
  tags = {
    Environment = local.env
    ManagedBy   = "terragrunt"
    Project     = "eks-karpenter-demo"
    Karpenter   = "enabled"
    Purpose     = "Demo EKS cluster with Karpenter and multi-architecture support"
  }
}
