locals {
  account_name          = "dr"
  account_id            = "444444444444" # TODO: Replace with actual AWS account ID
  aws_account_id        = "444444444444" # Alias for reference compatibility
  environment           = "dr"
  single_nat_gateway    = true
  eks_public_access     = false
  eks_instance_types    = ["m6i.xlarge"]
  eks_min_size          = 1
  eks_max_size          = 5
  eks_desired_size      = 2
  rds_instance_class    = "db.r6g.large"
  rds_allocated_storage = 50
  rds_multi_az          = true
  monitoring_replicas   = 1
}
