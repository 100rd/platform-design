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

  # --- Scaling stack ---
  karpenter_controller_replicas = 2
  karpenter_log_level           = "info"
  enable_keda                   = true
  keda_operator_replicas        = 1
  keda_metrics_server_replicas  = 1
  enable_hpa_defaults           = false
  enable_wpa                    = false

  karpenter_nodepools = {
    x86 = {
      enabled              = true
      cpu_limit            = 100
      memory_limit         = 200
      spot_percentage      = 80
      instance_families    = ["m6i", "m6a", "m5", "m5a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "30s"
      weight               = 10
    }
    arm64 = {
      enabled              = true
      cpu_limit            = 50
      memory_limit         = 100
      spot_percentage      = 90
      instance_families    = ["m6g", "m7g", "c6g", "c7g"]
      architectures        = ["arm64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "30s"
      weight               = 20
    }
    c-series = {
      enabled              = false
      cpu_limit            = 100
      memory_limit         = 200
      spot_percentage      = 70
      instance_families    = ["c6i", "c6a", "c5", "c5a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "30s"
      weight               = 30
    }
    spot-flexible = {
      enabled              = true
      cpu_limit            = 50
      memory_limit         = 100
      spot_percentage      = 100
      instance_families    = ["m6i", "m6a", "m5", "c6i", "c6a", "r6i", "r6a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "30s"
      weight               = 40
    }
  }
}
