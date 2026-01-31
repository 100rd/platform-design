locals {
  account_name          = "prod"
  account_id            = "333333333333" # TODO: Replace with actual AWS account ID
  aws_account_id        = "333333333333" # Alias for reference compatibility
  environment           = "prod"

  # Organization context
  org_account_type     = "workload"
  org_ou               = "Prod"
  management_account   = "000000000000"
  network_account      = "555555555555"

  # Transit Gateway connectivity (shared via RAM from network account)
  enable_tgw_attachment = false          # Enable once TGW is deployed in network account
  transit_gateway_id    = ""             # Populate after network account deployment
  tgw_route_table_id    = ""             # prod route table ID from network account

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

  # --- Scaling stack ---
  karpenter_controller_replicas = 3
  karpenter_log_level           = "warn"
  enable_keda                   = true
  keda_operator_replicas        = 3
  keda_metrics_server_replicas  = 3
  enable_hpa_defaults           = true
  enable_wpa                    = false

  karpenter_nodepools = {
    x86 = {
      enabled              = true
      cpu_limit            = 2000
      memory_limit         = 4000
      spot_percentage      = 70
      instance_families    = ["m6i", "m6a", "m5", "m5a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "300s"
      weight               = 10
    }
    arm64 = {
      enabled              = true
      cpu_limit            = 1000
      memory_limit         = 2000
      spot_percentage      = 70
      instance_families    = ["m6g", "m7g", "c6g", "c7g"]
      architectures        = ["arm64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "300s"
      weight               = 20
    }
    c-series = {
      enabled              = true
      cpu_limit            = 500
      memory_limit         = 1000
      spot_percentage      = 60
      instance_families    = ["c6i", "c6a", "c5", "c5a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "300s"
      weight               = 30
    }
    spot-flexible = {
      enabled              = false
      cpu_limit            = 0
      memory_limit         = 0
      spot_percentage      = 100
      instance_families    = []
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "300s"
      weight               = 40
    }
  }
}
