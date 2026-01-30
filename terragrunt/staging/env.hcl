locals {
  environment          = "staging"
  single_nat_gateway   = false
  eks_public_access    = false
  eks_instance_types   = ["m6i.xlarge"]
  eks_min_size         = 2
  eks_max_size         = 5
  eks_desired_size     = 3
  rds_instance_class   = "db.r6g.large"
  rds_allocated_storage = 50
  rds_multi_az         = true
  monitoring_replicas  = 2
}
