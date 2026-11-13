locals {
  service_name = "00000000000000000000000000000000" # TODO: Replace with OVHcloud Public Cloud Project ID
  project_name = "ovh-staging"
  environment  = "staging"
  ovh_endpoint = "ovh-eu"
  owner        = "team-ml-platform"

  # ---------------------------------------------------------------------------
  # OVHcloud MKS GPU Inference Cluster Configuration
  # ---------------------------------------------------------------------------
  gpu_inference_config = {
    kubernetes_version = "1.31"
    cluster_plan       = "standard" # Standard plan enables Cilium eBPF CNI by default

    # vRack Private Network + Public Cloud Gateway (SNAT)
    vlan_id        = 140
    subnet_cidr    = "10.215.0.0/16"
    enable_gateway = true
    gateway_model  = "s"

    # Companion services (Managed Harbor Private Registry)
    enable_container_registry = true
    registry_plan_id          = "SMALL"

    # Reused Helm / K8s addon toggles
    gpu_operator_enabled            = true
    gpu_driver_managed_by_operator  = true # OVH MKS nodes install CUDA drivers via NVIDIA GPU Operator
    gpu_toolkit_managed_by_operator = true
    dcgm_enabled                    = true
    scheduling_enabled              = true
    scheduler                       = "volcano"
    argocd_ha_enabled               = false
    inference_gateway_enabled       = false

    # System CPU pool (hosts ArgoCD, Cilium operator, Volcano controller)
    system_pool = {
      flavor_name   = "b3-16"
      desired_nodes = 2
      min_nodes     = 2
      max_nodes     = 4
    }

    # GPU Inference Node Pools (GRA11 hosts H100, L40S, and L4 flavors)
    gpu_node_pools = {
      gpu-l40s = {
        flavor_name   = "l40s-90" # 1x NVIDIA L40S 48GB GPU flavor
        desired_nodes = 1
        min_nodes     = 0 # Scale-to-zero when idle
        max_nodes     = 4
        autoscale     = true
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
        flavor_name   = "h100-380" # 1x NVIDIA H100 80GB GPU flavor
        desired_nodes = 0
        min_nodes     = 0
        max_nodes     = 2
        autoscale     = true
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
        flavor_name   = "l4-90" # 1x NVIDIA L4 24GB GPU flavor
        desired_nodes = 0
        min_nodes     = 0
        max_nodes     = 4
        autoscale     = true
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
