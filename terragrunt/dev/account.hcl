locals {
  account_name          = "dev"
  account_id            = "111111111111" # TODO: Replace with actual AWS account ID
  aws_account_id        = "111111111111" # Alias for reference compatibility
  environment           = "dev"
  single_nat_gateway    = true
  eks_public_access     = true
  eks_instance_types    = ["m6i.large"]
  eks_min_size          = 1
  eks_max_size          = 3
  eks_desired_size      = 2
  rds_instance_class    = "db.t4g.medium"
  rds_allocated_storage = 20
  rds_multi_az          = false
  monitoring_replicas   = 1
}
