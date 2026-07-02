# Environment-specific variables for the 'dev' agent-cluster.
locals {
  environment = "dev"
  
  # Common tags to be applied to all resources in this stack.
  tags = {
    Environment = "dev"
    Project     = "Agent-Cluster"
    ManagedBy   = "Terragrunt"
  }

  # Cluster-specific configuration
  cluster_name    = "agent-cluster-dev"
  cluster_version = "1.29"

  # VPC configuration
  vpc_cidr = "10.10.0.0/16"
  azs      = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
  public_subnets  = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]
}
