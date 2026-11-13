# ---------------------------------------------------------------------------------------------------------------------
# Scaleway Kapsule Dedicated GPU Cluster & Node Pools Module
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a Scaleway Kapsule Kubernetes cluster (Dedicated control plane by default) with:
#   - Cilium eBPF CNI over Scaleway VPC Private Network
#   - Cluster Autoscaler tuned for GPU inference (binpacking estimator, least-waste expander,
#     ignore_daemonsets_utilization for GPU Operator / DCGM DaemonSets so pools can scale to 0)
#   - System CPU node pool (private nodes, SBS volume) for control/GitOps workloads (ArgoCD)
#   - Low-latency Placement Groups + GPU node pools (L40S, H100, L4) with scale-to-zero
#     and native Kapsule tag-driven K8s node labels/taints (noprefix=..., taint=...)
# ---------------------------------------------------------------------------------------------------------------------

locals {
  base_tags = [for k, v in var.tags : "${k}=${v}"]
}

resource "scaleway_k8s_cluster" "this" {
  project_id                  = var.project_id
  name                        = var.cluster_name
  type                        = var.cluster_type
  version                     = var.kubernetes_version
  region                      = var.region
  cni                         = "cilium"
  private_network_id          = var.private_network_id
  delete_additional_resources = var.delete_additional_resources

  tags = concat(local.base_tags, [
    "cluster-type=gpu-inference",
    "cni=cilium",
  ])

  autoscaler_config {
    disable_scale_down              = false
    scale_down_delay_after_add      = var.scale_down_delay_after_add
    scale_down_unneeded_time        = var.scale_down_unneeded_time
    estimator                       = "binpacking"
    expander                        = "least-waste"
    ignore_daemonsets_utilization   = true
    balance_similar_node_groups     = true
    expendable_pods_priority_cutoff = -10
  }

  auto_upgrade {
    enable                        = var.auto_upgrade_enabled
    maintenance_window_start_hour = 3
    maintenance_window_day        = "sunday"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# System CPU Node Pool — hosts ArgoCD, Cilium operator, VictoriaMetrics, and schedulers
# ---------------------------------------------------------------------------------------------------------------------

resource "scaleway_k8s_pool" "system" {
  cluster_id             = scaleway_k8s_cluster.this.id
  name                   = "system"
  node_type              = var.system_pool.node_type
  size                   = var.system_pool.size
  min_size               = var.system_pool.min_size
  max_size               = var.system_pool.max_size
  autoscaling            = true
  autohealing            = true
  public_ip_disabled     = var.public_ip_disabled
  root_volume_type       = var.system_pool.root_volume_type
  root_volume_size_in_gb = var.system_pool.root_volume_size_in_gb
  zone                   = var.zone

  tags = concat(local.base_tags, [
    "noprefix=node-role=system",
  ])

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Placement Groups for Low-Latency Multi-GPU Locality
# ---------------------------------------------------------------------------------------------------------------------

resource "scaleway_instance_placement_group" "gpu" {
  for_each = {
    for k, v in var.gpu_node_pools : k => v if v.use_placement_group
  }

  project_id  = var.project_id
  name        = "${var.cluster_name}-${each.key}-pg"
  zone        = coalesce(each.value.zone, var.zone)
  policy_type = each.value.placement_policy_type
  policy_mode = "optional"
  tags        = local.base_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Node Pools (L40S-1-48G, H100-1-80G, L4-1-24G, etc.)
# ---------------------------------------------------------------------------------------------------------------------

resource "scaleway_k8s_pool" "gpu" {
  for_each = var.gpu_node_pools

  cluster_id             = scaleway_k8s_cluster.this.id
  name                   = each.key
  node_type              = each.value.node_type
  size                   = each.value.size
  min_size               = each.value.min_size
  max_size               = each.value.max_size
  autoscaling            = each.value.autoscaling
  autohealing            = each.value.autohealing
  public_ip_disabled     = var.public_ip_disabled
  root_volume_type       = each.value.root_volume_type
  root_volume_size_in_gb = each.value.root_volume_size_in_gb
  zone                   = coalesce(each.value.zone, var.zone)
  placement_group_id     = each.value.use_placement_group ? scaleway_instance_placement_group.gpu[each.key].id : null

  # Scaleway Kapsule translates pool tags with `noprefix=` and `taint=` prefixes directly
  # into Kubernetes node labels and taints (essential for scale-from-zero with Cluster Autoscaler).
  tags = concat(
    local.base_tags,
    [
      "noprefix=node-role=gpu",
      "noprefix=gpu-inference=true",
      "noprefix=k8s.scaleway.com/gpu-pool=${each.key}",
    ],
    [for lk, lv in each.value.labels : "noprefix=${lk}=${lv}"],
    [for t in each.value.taints : "taint=${t.key}=${t.value}:${t.effect}"],
  )

  lifecycle {
    create_before_destroy = true
  }
}
