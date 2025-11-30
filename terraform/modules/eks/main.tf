module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.8.0"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  # Authentication mode for EKS v21+
  authentication_mode = "API_AND_CONFIG_MAP"

  # Enable cluster addons required for Karpenter
  cluster_addons = {
    vpc-cni = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  subnet_ids = var.private_subnet_ids
  vpc_id     = var.vpc_id

  # Enable IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # Single managed node group for Karpenter controller and system pods
  # Karpenter will manage all other application workloads
  eks_managed_node_groups = {
    karpenter = {
      name           = "${var.cluster_name}-karpenter"
      instance_types = var.karpenter_controller_instance_types

      min_size     = var.karpenter_controller_min_size
      max_size     = var.karpenter_controller_max_size
      desired_size = var.karpenter_controller_desired_size

      capacity_type = "ON_DEMAND"
      subnet_ids    = var.private_subnet_ids

      # Prevent Karpenter from managing these nodes
      labels = {
        "karpenter.sh/controller" = "true"
      }

      taints = [{
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]

      tags = merge(
        var.tags,
        {
          Name = "${var.cluster_name}-karpenter-node"
        }
      )
    }
  }

  # Tags for security group discovery by Karpenter
  node_security_group_tags = merge(
    var.tags,
    {
      "karpenter.sh/discovery" = var.cluster_name
    }
  )

  tags = var.tags
}

# Karpenter submodule for IAM roles and infrastructure
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.8.0"

  cluster_name = module.eks.cluster_name

  # Enable Pod Identity (default in v21+)
  enable_pod_identity             = true
  create_pod_identity_association = true

  # Create IAM role for Karpenter-provisioned nodes
  create_node_iam_role          = true
  node_iam_role_use_name_prefix = false

  # Enable native spot termination handling
  enable_spot_termination = true

  # Additional IAM policies for nodes (e.g., SSM, CloudWatch)
  node_iam_role_additional_policies = var.karpenter_node_iam_role_additional_policies

  tags = var.tags
}
