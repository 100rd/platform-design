# ---------------------------------------------------------------------------------------------------------------------
# GCP GPU GKE Cluster — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a private GKE cluster for GPU video analysis workloads using the
# terraform-google-modules/kubernetes-engine private-cluster submodule.
#
# Key features:
#   - Dataplane V2 (Cilium) via ADVANCED_DATAPATH provider
#   - Private nodes with public endpoint (for external kubectl access)
#   - Workload Identity enabled
#   - Default node pool removed in favor of dedicated GPU node pools
#   - System node pool for cluster-critical workloads only
#
# Dependencies: gcp-gpu-vpc
# Requires project.hcl with: project_id, environment, gpu_analysis_config
# Requires region.hcl with: gcp_region, zones
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "tfr:///terraform-google-modules/kubernetes-engine/google//modules/private-cluster?version=35.0.1"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  gcp_project_id      = local.project_vars.locals.project_id
  environment         = local.project_vars.locals.environment
  gcp_region          = local.region_vars.locals.gcp_region
  gpu_analysis_config = local.project_vars.locals.gpu_analysis_config

  cluster_name = "${local.environment}-${local.gcp_region}-gcp-gpu-analysis"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: GCP GPU VPC
# ---------------------------------------------------------------------------------------------------------------------

dependency "vpc" {
  config_path = "../gcp-gpu-vpc"

  mock_outputs = {
    network_name                  = "mock-gpu-vpc"
    subnet_name                   = "mock-gpu-vpc-subnet"
    pods_secondary_range_name     = "mock-gpu-vpc-pods"
    services_secondary_range_name = "mock-gpu-vpc-services"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  project_id = local.gcp_project_id
  name       = local.cluster_name
  region     = local.gcp_region

  # Single zone for GPU locality
  zones = [local.region_vars.locals.zones[0]]

  # Networking — references VPC dependency outputs
  network           = dependency.vpc.outputs.network_name
  subnetwork        = dependency.vpc.outputs.subnet_name
  ip_range_pods     = dependency.vpc.outputs.pods_secondary_range_name
  ip_range_services = dependency.vpc.outputs.services_secondary_range_name

  # Dataplane V2 (Cilium) — handles network policy enforcement
  datapath_provider = "ADVANCED_DATAPATH"

  # Cluster features
  http_load_balancing        = true
  horizontal_pod_autoscaling = true
  network_policy             = false # Dataplane V2 handles network policy

  # Private cluster configuration
  enable_private_nodes    = true
  enable_private_endpoint = false # Need kubectl access from outside VPC
  master_ipv4_cidr_block  = "172.16.0.0/28"

  # Workload Identity
  identity_namespace = "enabled"

  # Release management
  release_channel    = "REGULAR"
  kubernetes_version = "latest"

  # Remove default node pool — GPU pools managed separately
  remove_default_node_pool = true
  initial_node_count       = 1

  # ---------------------------------------------------------------------------
  # System node pool — cluster-critical workloads only (no GPUs)
  # ---------------------------------------------------------------------------
  node_pools = [
    {
      name         = "system"
      machine_type = try(local.gpu_analysis_config.gke_machine_type, "e2-standard-4")
      min_count    = 1
      max_count    = 3
      disk_size_gb = 50
      disk_type    = "pd-standard"
      auto_repair  = true
      auto_upgrade = true
      image_type   = "COS_CONTAINERD"
    },
  ]

  node_pools_labels = {
    all    = {}
    system = { "node-role" = "system" }
  }

  node_pools_taints = {
    all    = []
    system = []
  }

  # ---------------------------------------------------------------------------
  # Cluster resource labels
  # ---------------------------------------------------------------------------
  cluster_resource_labels = {
    environment  = local.environment
    managed-by   = "terragrunt"
    cluster-role = "gpu-analysis"
  }
}
