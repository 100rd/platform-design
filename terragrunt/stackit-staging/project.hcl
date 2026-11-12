locals {
  project_id   = "00000000-0000-0000-0000-000000000000" # TODO: Replace with STACKIT Project UUID
  project_name = "stackit-staging"
  environment  = "staging"
  owner        = "team-ml-platform"

  # ---------------------------------------------------------------------------
  # STACKIT SKE GPU Inference Cluster Configuration
  # ---------------------------------------------------------------------------
  gpu_inference_config = {
    cluster_name           = "ske-gpu-inf"
    kubernetes_version_min = "1.31"
    ipv4_prefix_length     = 22

    # Native STACKIT Observability (Argus)
    enable_observability    = true
    observability_plan_name = "Observability-Monitoring-Medium-EU01"

    # Reused Helm / K8s addon toggles
    gpu_operator_enabled            = true
    gpu_driver_managed_by_operator  = true # SKE Ubuntu nodes rely on GPU Operator for NVIDIA drivers
    gpu_toolkit_managed_by_operator = true
    dcgm_enabled                    = true
    scheduling_enabled              = true
    scheduler                       = "volcano"
    argocd_ha_enabled               = false
    inference_gateway_enabled       = false

    # System CPU pool (hosts ArgoCD, Cilium operator, Volcano controller)
    system_pool = {
      name           = "system"
      machine_type   = "c1.4"
      os_name        = "flatcar"
      os_version_min = "4081.2.1"
      minimum        = 2
      maximum        = 4
      volume_type    = "storage_premium_perf4"
      volume_size    = 50
    }

    # GPU Inference Node Pools (Ubuntu + NVIDIA GPU Operator)
    gpu_node_pools = {
      gpu-l40s = {
        machine_type   = "g3i.4" # NVIDIA L40S 48GB GPU flavor
        os_name        = "ubuntu"
        os_version_min = "22.04"
        minimum        = 0 # Scale-to-zero when idle
        maximum        = 4
        volume_type    = "storage_premium_perf6"
        volume_size    = 200
        labels = {
          "gpu-type"               = "l40s"
          "nvidia.com/gpu.product" = "NVIDIA-L40S"
          "workload-type"          = "inference"
        }
        taints = [
          { key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }
        ]
      }

      gpu-h100 = {
        machine_type   = "g4i.8" # NVIDIA H100 80GB GPU flavor
        os_name        = "ubuntu"
        os_version_min = "22.04"
        minimum        = 0
        maximum        = 2
        volume_type    = "storage_premium_perf6"
        volume_size    = 300
        labels = {
          "gpu-type"               = "h100"
          "nvidia.com/gpu.product" = "NVIDIA-H100-80GB-HBM3"
          "workload-type"          = "heavy-inference"
        }
        taints = [
          { key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }
        ]
      }

      gpu-l4 = {
        machine_type   = "g2i.2" # NVIDIA L4 24GB GPU flavor
        os_name        = "ubuntu"
        os_version_min = "22.04"
        minimum        = 0
        maximum        = 4
        volume_type    = "storage_premium_perf4"
        volume_size    = 150
        labels = {
          "gpu-type"               = "l4"
          "nvidia.com/gpu.product" = "NVIDIA-L4"
          "workload-type"          = "embeddings"
        }
        taints = [
          { key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }
        ]
      }
    }
  }
}
