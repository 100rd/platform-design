locals {
  project_id   = "my-gcp-project-staging"  # TODO: Replace with actual GCP project ID
  project_name = "gcp-staging"
  environment  = "staging"

  # GPU Video Analysis Cluster Configuration
  gpu_analysis_config = {
    # GKE system node pool sizing
    gke_machine_type    = "e2-standard-4"
    gke_min_node_count  = 1
    gke_max_node_count  = 3

    # GPU Node Pools
    gpu_node_pools = {
      gpu-inference = {
        machine_type = "g2-standard-8"
        accelerator_type  = "nvidia-l4"
        accelerator_count = 1
        disk_size_gb      = 200
        disk_type         = "pd-ssd"
        spot              = false  # On-demand for SLA
        min_node_count    = 0
        max_node_count    = 4
        initial_node_count = 1
        labels = {
          "gpu-type"      = "l4"
          "workload-type" = "inference"
        }
        taints = [
          { key = "nvidia.com/gpu", value = "true", effect = "NO_SCHEDULE" }
        ]
      }

      gpu-preprocessing = {
        machine_type = "n1-standard-8"
        accelerator_type  = "nvidia-tesla-t4"
        accelerator_count = 1
        disk_size_gb      = 200
        disk_type         = "pd-ssd"
        spot              = true  # Spot for cost optimization
        min_node_count    = 0
        max_node_count    = 4
        initial_node_count = 0
        labels = {
          "gpu-type"      = "t4"
          "workload-type" = "preprocessing"
        }
        taints = [
          { key = "nvidia.com/gpu", value = "true", effect = "NO_SCHEDULE" }
        ]
      }

      cpu-coordination = {
        machine_type = "n2-standard-4"
        accelerator_type  = null
        accelerator_count = 0
        disk_size_gb      = 100
        disk_type         = "pd-ssd"
        spot              = true
        min_node_count    = 0
        max_node_count    = 3
        initial_node_count = 1
        labels = {
          "workload-type" = "coordination"
        }
        taints = []
      }
    }
  }
}
