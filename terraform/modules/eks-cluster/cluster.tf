module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15" # Updated 2026-01-28 from ~> 20.0

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Authentication mode for EKS v21+
  authentication_mode = "API_AND_CONFIG_MAP"

  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = true

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # ---------------------------------------------------------------------------
  # Secrets Encryption — PCI-DSS Req 3.4 (render PAN unreadable)
  # Encrypts Kubernetes secrets at rest using a KMS CMK via envelope encryption.
  # ---------------------------------------------------------------------------
  cluster_encryption_config = var.kms_key_arn != "" ? {
    provider_key_arn = var.kms_key_arn
    resources        = ["secrets"]
  } : {}

  # ---------------------------------------------------------------------------
  # Control Plane Logging — PCI-DSS Req 10.2
  # Enables all EKS control plane log types for audit trail completeness.
  # ---------------------------------------------------------------------------
  cluster_enabled_log_types = var.cluster_enabled_log_types

  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    default = {
      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      instance_types = var.instance_types
      capacity_type  = "ON_DEMAND"
    }
  }

  # Cluster access entry
  enable_cluster_creator_admin_permissions = true

  tags = var.tags
}
