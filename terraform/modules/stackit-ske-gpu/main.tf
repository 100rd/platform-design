# ---------------------------------------------------------------------------------------------------------------------
# STACKIT Kubernetes Engine (SKE) GPU Cluster & Node Pools Module
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a Gardener-based STACKIT SKE cluster with:
#   - Native Cilium eBPF CNI over an isolated STACKIT routed network
#   - System CPU node pool (Flatcar / Ubuntu) for ArgoCD, Volcano, and system controllers
#   - GPU Inference node pools (L40S, H100, L4) with scale-to-zero (`minimum = 0`),
#     premium SSD storage (`storage_premium_perf6`), and native Kubernetes labels & taints
#   - Optional integration with STACKIT Observability (Argus) via `extensions.observability`
#   - Auto-refreshing admin `stackit_ske_kubeconfig` parsed for downstream Helm/K8s providers
# ---------------------------------------------------------------------------------------------------------------------

locals {
  system_node_pool = {
    name               = var.system_pool.name
    machine_type       = var.system_pool.machine_type
    os_name            = var.system_pool.os_name
    os_version_min     = var.system_pool.os_version_min
    minimum            = var.system_pool.minimum
    maximum            = var.system_pool.maximum
    max_surge          = 1
    max_unavailable    = 0
    availability_zones = var.availability_zones
    volume_type        = var.system_pool.volume_type
    volume_size        = var.system_pool.volume_size
    labels = merge(var.labels, {
      "node-role" = "system"
    })
    taints = []
  }

  gpu_node_pool_list = [
    for pool_name, pool in var.gpu_node_pools : {
      name               = pool_name
      machine_type       = pool.machine_type
      os_name            = pool.os_name
      os_version_min     = pool.os_version_min
      minimum            = pool.minimum
      maximum            = pool.maximum
      max_surge          = pool.max_surge
      max_unavailable    = 0
      availability_zones = coalesce(pool.availability_zones, [var.availability_zones[0]])
      volume_type        = pool.volume_type
      volume_size        = pool.volume_size
      labels = merge(
        var.labels,
        {
          "node-role"     = "gpu"
          "gpu-inference" = "true"
          "cluster-type"  = "gpu-inference"
          "ske.gpu/pool"  = pool_name
        },
        pool.labels,
      )
      taints = pool.taints
    }
  ]

  parsed_kubeconfig = yamldecode(stackit_ske_kubeconfig.this.kube_config)
}

resource "stackit_ske_cluster" "this" {
  project_id             = var.project_id
  name                   = var.cluster_name
  region                 = var.region
  kubernetes_version_min = var.kubernetes_version_min

  network = {
    id = var.network_id
    control_plane = {
      access_scope = var.control_plane_access_scope
    }
  }

  node_pools = concat([local.system_node_pool], local.gpu_node_pool_list)

  maintenance = {
    enable_kubernetes_version_updates    = var.auto_upgrade_enabled
    enable_machine_image_version_updates = var.auto_upgrade_enabled
    start                                = "03:00:00Z"
    end                                  = "05:00:00Z"
  }

  extensions = var.observability_instance_id != null ? {
    observability = {
      enabled     = true
      instance_id = var.observability_instance_id
    }
  } : null
}

resource "stackit_ske_kubeconfig" "this" {
  project_id   = var.project_id
  cluster_name = stackit_ske_cluster.this.name
  region       = var.region
  expiration   = 86400
  refresh      = true
}
