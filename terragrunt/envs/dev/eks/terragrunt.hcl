include {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../terraform/modules/eks"
}

dependencies {
  paths = ["../vpc"]
}

inputs = {
  cluster_name    = "${include.local.env}-platform-eks"
  cluster_version = "1.33"

  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnets

  tags = {
    Environment = include.local.env
    ManagedBy   = "terragrunt"
  }
}
