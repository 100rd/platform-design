locals {
  environment          = "prod"
  single_nat_gateway   = false
  eks_public_access    = false
  eks_instance_types   = ["m6i.2xlarge"]
  eks_min_size         = 3
  eks_max_size         = 10
  eks_desired_size     = 5
  rds_instance_class   = "db.r6g.xlarge"
  rds_allocated_storage = 100
  rds_multi_az         = true
  monitoring_replicas  = 3
}
