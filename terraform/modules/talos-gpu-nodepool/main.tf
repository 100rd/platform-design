# ---------------------------------------------------------------------------------------------------------------------
# Talos GPU Node Pool Module (WS-A — ml-infra) — ADR-0049 / ADR-0054
# ---------------------------------------------------------------------------------------------------------------------
# A *logical* GPU node pool over a set of bare-metal machines — the bare-metal analogue of
# gcp-gke-gpu-nodepools MINUS the autoscaler. On owned hardware capacity is FIXED
# (ADR-0054): there is no cloud API that conjures nodes in seconds; a "new node" is a
# PXE/Talos re-image measured in minutes-to-hours. So this module does NOT manage a
# min/max autoscaling range — it binds machines to the GPU-worker class, applies the
# taint/labels Volcano + the device-plugin select on, and OPTIONALLY drives Cluster-API
# (Metal³/Sidero) Machine objects for re-image-based lifecycle.
#
# The GPU node taint + labels are emitted as a label/taint policy carried by a
# kubernetes_manifest (a node-policy ConfigMap the GitOps layer reconciles) — kept free
# of any live-cluster read so plan/validate works against mocked providers, matching the
# gke-gpu-fabric / dranet modules' kubernetes_manifest pattern.
#
# Cluster-API objects (Machine/MetalMachine, ADR-0054) are gated behind
# var.manage_cluster_api so the default posture is a static, pre-provisioned pool and
# nothing reconciles real hardware.
#
# ADR-0028: dotted platform labels on every object and node.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-infra"
      "platform.component"  = "gpu-nodepool"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  # Fixed-capacity GPU pool: the node labels/taints the device-plugin + Volcano select on.
  node_labels = merge(
    local.platform_labels,
    {
      "nvidia.com/gpu.present"      = "true"
      "node.kubernetes.io/gpu-pool" = var.pool_name
      "gpu.platform/model"          = var.gpu_model
    },
  )

  # Cluster-API Machines are created only when explicitly asked (ADR-0054 re-image path).
  cluster_api_machines = var.enabled && var.manage_cluster_api ? { for m in var.machines : m.name => m } : {}
}

# ---------------------------------------------------------------------------------------------------------------------
# GPU node-pool policy — a ConfigMap the GitOps layer applies to taint/label the pool.
# Carries the fixed-capacity intent (size, taints, labels) without reading the live cluster.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "nodepool_policy" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "gpu-nodepool-${var.pool_name}"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    data = {
      "pool_name"      = var.pool_name
      "gpu_model"      = var.gpu_model
      "fixed_capacity" = tostring(length(var.machines))
      # Fixed pool — explicitly no autoscaler (ADR-0054).
      "autoscaling" = "disabled"
      "gpu_taint"   = "${var.gpu_taint_key}=${var.gpu_taint_value}:${var.gpu_taint_effect}"
      "node_labels" = jsonencode(local.node_labels)
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Cluster-API Machine objects (Metal³/Sidero) — re-image-based node lifecycle (ADR-0054).
# Gated OFF by default (manage_cluster_api = false) → static pre-provisioned pool.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "cluster_api_machine" {
  for_each = local.cluster_api_machines

  manifest = {
    apiVersion = "cluster.x-k8s.io/v1beta1"
    kind       = "Machine"
    metadata = {
      name      = each.value.name
      namespace = var.cluster_api_namespace
      labels = merge(local.platform_labels, {
        "cluster.x-k8s.io/cluster-name" = var.cluster_name
      })
    }
    spec = {
      clusterName = var.cluster_name
      bootstrap = {
        dataSecretName = each.value.bootstrap_secret
      }
      infrastructureRef = {
        apiVersion = var.cluster_api_infra_provider == "sidero" ? "infrastructure.cluster.x-k8s.io/v1alpha2" : "infrastructure.cluster.x-k8s.io/v1beta1"
        kind       = var.cluster_api_infra_provider == "sidero" ? "MetalMachine" : "Metal3Machine"
        name       = each.value.name
      }
    }
  }
}
