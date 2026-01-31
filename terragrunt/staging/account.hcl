locals {
  account_name          = "staging"
  account_id            = "222222222222" # TODO: Replace with actual AWS account ID
  aws_account_id        = "222222222222" # Alias for reference compatibility
  environment           = "staging"
  single_nat_gateway    = false
  eks_public_access     = false
  eks_instance_types    = ["m6i.xlarge"]
  eks_min_size          = 2
  eks_max_size          = 5
  eks_desired_size      = 3
  rds_instance_class    = "db.r6g.large"
  rds_allocated_storage = 50
  rds_multi_az          = true
  monitoring_replicas   = 2

  # --- Scaling stack ---
  karpenter_controller_replicas = 2
  karpenter_log_level           = "info"
  enable_keda                   = true
  keda_operator_replicas        = 2
  keda_metrics_server_replicas  = 2
  enable_hpa_defaults           = true
  enable_wpa                    = false

  karpenter_nodepools = {
    x86 = {
      enabled              = true
      cpu_limit            = 500
      memory_limit         = 1000
      spot_percentage      = 80
      instance_families    = ["m6i", "m6a", "m5", "m5a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "60s"
      weight               = 10
    }
    arm64 = {
      enabled              = true
      cpu_limit            = 300
      memory_limit         = 600
      spot_percentage      = 85
      instance_families    = ["m6g", "m7g", "c6g", "c7g"]
      architectures        = ["arm64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "60s"
      weight               = 20
    }
    c-series = {
      enabled              = true
      cpu_limit            = 200
      memory_limit         = 400
      spot_percentage      = 70
      instance_families    = ["c6i", "c6a", "c5", "c5a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "60s"
      weight               = 30
    }
    spot-flexible = {
      enabled              = true
      cpu_limit            = 200
      memory_limit         = 400
      spot_percentage      = 100
      instance_families    = ["m6i", "m6a", "m5", "c6i", "c6a", "r6i", "r6a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "60s"
      weight               = 40
    }
  }
}
