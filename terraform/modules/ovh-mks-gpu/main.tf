# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud Managed Kubernetes Service (MKS) GPU Cluster & Node Pools Module
# ---------------------------------------------------------------------------------------------------------------------
# Provisions an OVHcloud MKS cluster in `GRA11` with:
#   - `STANDARD` plan (enables Cilium eBPF CNI by default)
#   - vRack Private Network attachment + Public Cloud Gateway SNAT routing
#   - System CPU node pool (`b3-16` / `b3-8`) for ArgoCD, Volcano, and system controllers
#   - GPU Inference node pools (`l40s-90`, `h100-380`, `l4-90`) with scale-to-zero (`min_nodes = 0`)
#     and native Kubernetes node labels & taints via `template`
# ---------------------------------------------------------------------------------------------------------------------

resource "ovh_cloud_project_kube" "this" {
  service_name       = var.service_name
  name               = var.cluster_name
  region             = var.region
  version            = var.kubernetes_version
  plan               = var.cluster_plan
  private_network_id = var.private_network_id
  nodes_subnet_id    = var.nodes_subnet_id
  update_policy      = var.update_policy

  private_network_configuration {
    default_vrack_gateway              = var.default_vrack_gateway
    private_network_routing_as_default = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# System CPU Node Pool — hosts ArgoCD, Cilium operator, and schedulers
# ---------------------------------------------------------------------------------------------------------------------

resource "ovh_cloud_project_kube_nodepool" "system" {
  service_name  = var.service_name
  kube_id       = ovh_cloud_project_kube.this.id
  name          = "system"
  flavor_name   = var.system_pool.flavor_name
  desired_nodes = var.system_pool.desired_nodes
  min_nodes     = var.system_pool.min_nodes
  max_nodes     = var.system_pool.max_nodes
  autoscale     = true

  template {
    metadata {
      annotations = {}
      finalizers  = []
      labels = merge(var.labels, {
        "node-role" = "system"
      })
    }
    spec {
      unschedulable = false
      taints        = []
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Node Pools (l40s-90, h100-380, l4-90)
# ---------------------------------------------------------------------------------------------------------------------

resource "ovh_cloud_project_kube_nodepool" "gpu" {
  for_each = var.gpu_node_pools

  service_name   = var.service_name
  kube_id        = ovh_cloud_project_kube.this.id
  name           = replace(each.key, "_", "-") # OVH MKS disallows underscores in nodepool names
  flavor_name    = each.value.flavor_name
  desired_nodes  = each.value.desired_nodes
  min_nodes      = each.value.min_nodes
  max_nodes      = each.value.max_nodes
  autoscale      = each.value.autoscale
  anti_affinity  = each.value.anti_affinity
  monthly_billed = false

  template {
    metadata {
      annotations = {}
      finalizers  = []
      labels = merge(
        var.labels,
        {
          "node-role"     = "gpu"
          "gpu-inference" = "true"
          "cluster-type"  = "gpu-inference"
          "ovh.gpu/pool"  = each.key
        },
        each.value.labels,
      )
    }
    spec {
      unschedulable = false
      taints        = each.value.taints
    }
  }
}
