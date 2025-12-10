include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../terraform/modules/vpc"
}

inputs = {
  name = "cell-01-vpc"
  cidr = "10.1.0.0/16" # Dedicated CIDR for Cell 01
  
  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.1.1.0/24", "10.1.2.0/24"]
  public_subnets  = ["10.1.101.0/24", "10.1.102.0/24"]
  
  enable_nat_gateway = true
  single_nat_gateway = true
  
  tags = {
    Cell = "cell-01"
  }
}
