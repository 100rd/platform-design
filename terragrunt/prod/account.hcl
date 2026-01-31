locals {
  account_name          = "prod"
  account_id            = "333333333333" # TODO: Replace with actual AWS account ID
  aws_account_id        = "333333333333" # Alias for reference compatibility
  environment           = "prod"
  single_nat_gateway    = false
  eks_public_access     = false
  eks_instance_types    = ["m6i.2xlarge"]
  eks_min_size          = 3
  eks_max_size          = 10
  eks_desired_size      = 5
  rds_instance_class    = "db.r6g.xlarge"
  rds_allocated_storage = 100
  rds_multi_az          = true
  monitoring_replicas   = 3
}
