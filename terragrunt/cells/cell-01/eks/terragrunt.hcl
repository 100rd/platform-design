include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../terraform/modules/eks"
}

dependency "vpc" {
  config_path = "../vpc"
}

inputs = {
  cluster_name    = "cell-01-eks"
  cluster_version = "1.34"
  
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets
  
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true # For ease of access, can be restricted later
  
  tags = {
    Cell = "cell-01"
  }
}
