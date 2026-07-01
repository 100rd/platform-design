# cluster.tf for the EKS Agent Cluster module
# This module creates an EKS control plane without any managed node groups,
# making it suitable for use with Karpenter.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15" # Using the same version as your other module for consistency

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Authentication mode for EKS v21+
  authentication_mode = "API_AND_CONFIG_MAP"

  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # ---------------------------------------------------------------------------
  # Secrets Encryption — PCI-DSS Req 3.4
  # ---------------------------------------------------------------------------
  cluster_encryption_config = var.kms_key_arn != "" ? {
    provider_key_arn = var.kms_key_arn
    resources        = ["secrets"]
  } : {}

  # ---------------------------------------------------------------------------
  # Control Plane Logging — PCI-DSS Req 10.2
  # ---------------------------------------------------------------------------
  cluster_enabled_log_types = var.cluster_enabled_log_types

  # ---------------------------------------------------------------------------
  # CRITICAL: No Managed Node Groups
  # This is the key difference from the standard 'eks-cluster' module.
  # We pass an empty map to ensure no node groups are created, as Karpenter
  # will be responsible for all node management.
  # ---------------------------------------------------------------------------
  eks_managed_node_groups = {}
  
  # Also disable the self-managed node group which might be created by default in older versions
  create_node_group = false

  # ---------------------------------------------------------------------------
  # Cluster Creator Admin — bootstrap access
  # ---------------------------------------------------------------------------
  enable_cluster_creator_admin_permissions = true

  # ---------------------------------------------------------------------------
  # Access Entries — PCI-DSS Req 7.1, 7.2, 8.5
  # ---------------------------------------------------------------------------
  access_entries = { for k, v in var.access_entries : k => {
    principal_arn     = v.principal_arn
    kubernetes_groups = v.kubernetes_groups
    type              = v.type
  } }

  tags = var.tags
}
