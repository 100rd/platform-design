module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

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
