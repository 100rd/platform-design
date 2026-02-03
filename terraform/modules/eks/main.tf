module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15" # Updated 2026-01-28 from 21.8.0

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = true

  # Authentication mode for EKS v21+
  authentication_mode = "API_AND_CONFIG_MAP"

  # ---------------------------------------------------------------------------
  # Cluster Addons
  # vpc-cni is DISABLED by default — Cilium CNI is used instead.
  # Set enable_vpc_cni = true to use AWS VPC CNI (legacy mode).
  # ---------------------------------------------------------------------------
  cluster_addons = merge(
    var.enable_vpc_cni ? {
      vpc-cni = {
        most_recent = true
      }
    } : {},
    {
      coredns = {
        most_recent = true
        # CoreDNS needs Cilium to be ready before pods can communicate
        configuration_values = var.enable_vpc_cni ? null : jsonencode({
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
  )

  subnet_ids = var.private_subnet_ids
  vpc_id     = var.vpc_id

  # Enable IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # ---------------------------------------------------------------------------
  # System node group for Karpenter controller and cluster-critical workloads
  # Uses Bottlerocket by default for Cilium CNI compatibility.
  # ---------------------------------------------------------------------------
  eks_managed_node_groups = {
    system = {
      name           = "${var.cluster_name}-system"
      ami_type       = var.enable_vpc_cni ? "AL2023_x86_64_STANDARD" : "BOTTLEROCKET_x86_64"
      instance_types = var.karpenter_controller_instance_types

      min_size     = var.karpenter_controller_min_size
      max_size     = var.karpenter_controller_max_size
      desired_size = var.karpenter_controller_desired_size

      capacity_type = "ON_DEMAND"
      subnet_ids    = var.private_subnet_ids

      # Prevent Karpenter from managing these nodes
      labels = {
        "karpenter.sh/controller" = "true"
        "node.kubernetes.io/purpose" = "system"
      }

      taints = concat(
        [{
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }],
        # Cilium taint to prevent scheduling until agent is ready
        var.enable_vpc_cni ? [] : [{
          key    = "node.cilium.io/agent-not-ready"
          value  = "true"
          effect = "NO_SCHEDULE"
        }]
      )

      tags = merge(
        var.tags,
        {
          Name = "${var.cluster_name}-system-node"
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
  version = "~> 21.15" # Updated 2026-01-28 from 21.8.0

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
