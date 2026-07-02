# This stack defines the entire agent-cluster infrastructure.
# It follows the v1 Terragrunt standard for defining stacks.

# Include the root configuration which sets up the backend.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Common inputs that will be merged into every module in this stack.
inputs = {
  # Read variables from env and region specific files
  aws_region      = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals.aws_region
  cluster_name    = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.cluster_name
  cluster_version = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.cluster_version
  tags            = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Stack Components
# ---------------------------------------------------------------------------------------------------------------------

# Deploys the VPC network.
unit "vpc" {
  source = "../../../../terraform/modules/vpc"

  # These inputs are specific to the VPC module.
  inputs = {
    name = "agent-cluster-${read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.environment}"
    cidr = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.vpc_cidr
    azs  = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.azs
    private_subnets = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.private_subnets
    public_subnets  = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.public_subnets
    
    private_subnet_tags = {
      "karpenter.sh/discovery" = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.cluster_name
    }
  }
}

# Deploys the EKS control plane (without nodes).
unit "eks" {
  source = "../../../../terraform/modules/eks-agent-cluster"
  dependencies = ["vpc"]

  inputs = {
    vpc_id     = dependency.vpc.outputs.vpc_id
    subnet_ids = dependency.vpc.outputs.private_subnets
  }
}

# Deploys Karpenter for node auto-scaling.
unit "karpenter" {
  source = "../../../../terraform/modules/karpenter"
  dependencies = ["eks"]

  inputs = {
    oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  }
}

# Deploys Cilium CNI.
unit "cilium" {
  source = "../../../../terraform/modules/cilium"
  dependencies = ["eks"]
}

# Deploys Istio Service Mesh.
unit "istio" {
  source = "../../../../terraform/modules/istio"
  dependencies = ["eks"]
}

# Deploys KEDA for event-driven autoscaling.
unit "keda" {
  source = "../../../../terraform/modules/keda"
  dependencies = ["eks"]
}
