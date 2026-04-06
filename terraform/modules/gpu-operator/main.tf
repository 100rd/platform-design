# ---------------------------------------------------------------------------------------------------------------------
# NVIDIA GPU Operator v26.3 with DRA Driver
# ---------------------------------------------------------------------------------------------------------------------
# Deploys NVIDIA GPU Operator via Helm with DRA (Dynamic Resource Allocation)
# enabled, replacing the traditional device-plugin model. The DRA driver
# publishes GPU attributes via ResourceSlice objects for topology-aware scheduling.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "gpu_operator" {
  name             = "gpu-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "gpu-operator"
  version          = var.chart_version
  namespace        = "gpu-operator"
  create_namespace = true
  timeout          = 600

  values = [
    yamlencode({
      # DRA driver — replaces device-plugin for GPU allocation
      dra = {
        enabled = true
        version = var.dra_driver_version
      }

      # Disable legacy device plugin (DRA replaces it)
      devicePlugin = {
        enabled = false
      }

      # GPU driver — pre-installed in AMI (Bottlerocket NVIDIA)
      driver = {
        enabled = var.driver_enabled
      }

      # Container toolkit
      toolkit = {
        enabled = true
      }

      # DCGM Exporter (deployed separately in Phase 5)
      dcgmExporter = {
        enabled = var.dcgm_exporter_enabled
      }

      # GPU Feature Discovery
      gfd = {
        enabled = true
      }

      # Node Feature Discovery
      nfd = {
        enabled = true
      }

      # CDI (Container Device Interface) for DRA
      cdi = {
        enabled = true
      }

      operator = {
        # Node selector — only deploy on GPU nodes
        nodeSelector = {
          "node-role" = "gpu"
        }

        # Tolerations for GPU taint
        tolerations = [
          {
            key      = "nvidia.com/gpu"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]

        # Operator resource limits
        resources = {
          limits = {
            cpu    = var.operator_cpu_limit
            memory = var.operator_memory_limit
          }
        }
      }
    })
  ]
}
