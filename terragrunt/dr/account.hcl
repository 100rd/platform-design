locals {
  account_name   = "dr"
  account_id     = "444444444444" # TODO: Replace with actual AWS account ID
  aws_account_id = "444444444444" # Alias for reference compatibility
  environment    = "dr"

  # Organization context
  org_account_type   = "workload"
  org_ou             = "Prod"
  management_account = "000000000000"
  network_account    = "555555555555"

  # Transit Gateway connectivity (shared via RAM from network account)
  enable_tgw_attachment = false # Enable once TGW is deployed in network account
  transit_gateway_id    = ""    # Populate after network account deployment
  tgw_route_table_id    = ""    # prod route table ID from network account

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
      spot_percentage      = 50
      instance_families    = ["m6i", "m6a", "m5", "m5a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "600s"
      weight               = 10
    }
    arm64 = {
      enabled              = true
      cpu_limit            = 300
      memory_limit         = 600
      spot_percentage      = 50
      instance_families    = ["m6g", "m7g", "c6g", "c7g"]
      architectures        = ["arm64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "600s"
      weight               = 20
    }
    c-series = {
      enabled              = false
      cpu_limit            = 200
      memory_limit         = 400
      spot_percentage      = 50
      instance_families    = ["c6i", "c6a", "c5", "c5a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "600s"
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
      consolidate_after    = "600s"
      weight               = 40
    }
  }
}
