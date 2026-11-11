locals {
  organization_id = "00000000-0000-0000-0000-000000000000" # TODO: Replace with Scaleway Organization UUID
  project_id      = "11111111-1111-1111-1111-111111111111" # TODO: Replace with Scaleway Project UUID
  project_name    = "scw-staging"
  environment     = "staging"
  owner           = "team-ml-platform"

  # ---------------------------------------------------------------------------
  # Scaleway GPU Inference Cluster Configuration
  # ---------------------------------------------------------------------------
  gpu_inference_config = {
    # Kapsule Dedicated Control Plane (99.95% SLA, dedicated etcd & API server)
    cluster_type       = "kapsule-dedicated-4"
    kubernetes_version = "1.32"

    # Networking: Private Network + Public Gateway (NAT masquerade for private GPU nodes)
    subnet_cidr           = "10.210.0.0/16"
    enable_public_gateway = true
    public_gateway_type   = "VPC-GW-S"
    bastion_enabled       = false

    # Native Scaleway companion services
    enable_container_registry = true
    enable_cockpit            = true

    # Reused Helm / K8s addon toggles
    gpu_operator_enabled      = true
    dcgm_enabled              = true
    scheduling_enabled        = true
    scheduler                 = "volcano"
    argocd_ha_enabled         = false
    inference_gateway_enabled = false # Enable after Gateway API + InferencePool CRDs are installed

    # System CPU pool (hosts ArgoCD, Cilium operator, Volcano controller)
    system_pool = {
      node_type              = "PRO2-S"
      size                   = 2
      min_size               = 2
      max_size               = 4
      root_volume_type       = "sbs_5k"
      root_volume_size_in_gb = 50
    }

    # GPU Inference Node Pools
    gpu_node_pools = {
      # Primary LLM Inference Pool: NVIDIA L40S (48GB VRAM, FP8, local NVMe scratch)
      gpu-inference-l40s = {
        node_type              = "L40S-1-48G"
        size                   = 1
        min_size               = 0 # Scale-to-zero when idle
        max_size               = 4
        autoscaling            = true
        autohealing            = true
        root_volume_type       = "sbs_15k"
        root_volume_size_in_gb = 200
        use_placement_group    = true
        placement_policy_type  = "low_latency"
        labels = {
          "gpu-type"               = "l40s"
          "nvidia.com/gpu.product" = "NVIDIA-L40S"
          "workload-type"          = "inference"
        }
        taints = [
          { key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }
        ]
      }

      # Heavy LLM Inference Pool (70B+): NVIDIA H100 (80GB HBM3, scale-to-zero by default)
      gpu-inference-h100 = {
        node_type              = "H100-1-80G"
        size                   = 0
        min_size               = 0
        max_size               = 2
        autoscaling            = true
        autohealing            = true
        root_volume_type       = "sbs_15k"
        root_volume_size_in_gb = 300
        use_placement_group    = true
        placement_policy_type  = "low_latency"
        labels = {
          "gpu-type"               = "h100"
          "nvidia.com/gpu.product" = "NVIDIA-H100-80GB-HBM3"
          "workload-type"          = "heavy-inference"
        }
        taints = [
          { key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }
        ]
      }

      # Lightweight / Embeddings / Preprocessing Pool: NVIDIA L4 (24GB VRAM)
      gpu-light-l4 = {
        node_type              = "L4-1-24G"
        size                   = 0
        min_size               = 0
        max_size               = 4
        autoscaling            = true
        autohealing            = true
        root_volume_type       = "sbs_5k"
        root_volume_size_in_gb = 150
        use_placement_group    = false
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
