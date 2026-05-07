locals {
  account_name   = "sandbox"
  account_id     = "007027391583"
  aws_account_id = "007027391583" # alias for reference compatibility
  environment    = "sandbox"
  email          = "gerasimowigor@gmail.com"

  # Cost allocation and audit tracing
  owner       = "igor"
  cost_center = "personal-sandbox"

  # Organization context — personal account, not part of an AWS Organization
  org_account_type   = "workload"
  org_ou             = "Sandbox"
  management_account = "007027391583" # self — no management account
  network_account    = "007027391583" # self — no dedicated network account

  # Transit Gateway — not configured in this personal sandbox account
  enable_tgw_attachment = false
  transit_gateway_id    = ""
  tgw_route_table_id    = ""

  # -------------------------------------------------------------------------
  # Cost optimizations — single NAT gateway, minimal node sizing
  # -------------------------------------------------------------------------
  single_nat_gateway = true

  # EKS API server endpoint — public but restricted to user's IP only
  eks_public_access       = true
  eks_public_access_cidrs = ["84.40.153.97/32"] # user's public IP

  eks_instance_types    = ["m6i.xlarge"]
  eks_min_size          = 1
  eks_max_size          = 3
  eks_desired_size      = 2
  rds_instance_class    = "db.t4g.small"
  rds_allocated_storage = 20
  rds_multi_az          = false
  monitoring_replicas   = 1

  # -------------------------------------------------------------------------
  # KMS — IAM user direct access; OrganizationAccountAccessRole does not exist
  # in this personal sandbox account (no AWS Organization membership).
  # -------------------------------------------------------------------------
  kms_admin_arns = ["arn:aws:iam::007027391583:user/igor"]
  kms_user_arns  = ["arn:aws:iam::007027391583:user/igor"]

  # -------------------------------------------------------------------------
  # EKS access entries — no AWS SSO roles in this personal account.
  # enable_cluster_creator_admin_permissions = true in the eks unit grants
  # IAM user igor cluster-admin via the creator pattern; no extra entries needed.
  # -------------------------------------------------------------------------
  eks_access_entries = {}

  # -------------------------------------------------------------------------
  # Cilium
  # -------------------------------------------------------------------------
  cilium_replace_kube_proxy = false

  # -------------------------------------------------------------------------
  # ClusterMesh — disabled; standalone sandbox cluster, no multi-region mesh
  # -------------------------------------------------------------------------
  enable_clustermesh = false
  clustermesh_cluster_ids = {
    "eu-central-1" = 1
  }
  clustermesh_apiserver_replicas = 1
  peer_vpc_cidrs                 = {}

  # -------------------------------------------------------------------------
  # Scaling stack — minimal / disabled for sandbox
  # -------------------------------------------------------------------------
  karpenter_controller_replicas = 1
  karpenter_log_level           = "info"
  enable_keda                   = false
  keda_operator_replicas        = 1
  keda_metrics_server_replicas  = 1
  enable_hpa_defaults           = false
  enable_wpa                    = false

  # -------------------------------------------------------------------------
  # Features not needed / not available in sandbox
  # -------------------------------------------------------------------------
  enable_nlb_ingress        = false
  enable_global_accelerator = false

  # Secrets replication — no replica regions in sandbox
  secrets_config = {
    primary_region       = "eu-central-1"
    replica_regions      = []
    rotation_days        = 90
    replica_kms_key_arns = {}
  }

  # -------------------------------------------------------------------------
  # Common tags applied to all resources in this account
  # -------------------------------------------------------------------------
  default_tags = {
    Project     = "minimal-platform-test"
    Environment = "sandbox"
    Owner       = "igor"
    ManagedBy   = "terragrunt"
    CostCenter  = "personal-sandbox"
  }
}
