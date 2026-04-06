# ---------------------------------------------------------------------------------------------------------------------
# GPU Node Tuning — Performance Profile Module
# ---------------------------------------------------------------------------------------------------------------------
# Configures OS-level performance tuning for GPU inference nodes:
# - CPU isolation (isolcpus) via node labels and kubelet config
# - 1GB HugePages pre-allocation
# - NUMA-aware topology manager (single-numa-node policy)
# - Network buffer tuning for NCCL
# - CPU governor set to performance mode
#
# Applied via a combination of:
# - Bottlerocket settings (baked into launch template userdata)
# - Kubernetes node configuration (kubelet flags, sysctl)
# - DaemonSet for runtime tuning validation
# ---------------------------------------------------------------------------------------------------------------------

# ConfigMap with kubelet configuration for GPU nodes
resource "kubernetes_config_map_v1" "gpu_kubelet_config" {
  metadata {
    name      = "gpu-node-kubelet-config"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "gpu-node-tuning"
      "app.kubernetes.io/component" = "kubelet-config"
    }
  }

  data = {
    "kubelet-config.json" = jsonencode({
      topologyManagerPolicy = "single-numa-node"
      cpuManagerPolicy      = "static"
      memoryManagerPolicy   = "Static"
      reservedSystemCPUs    = var.reserved_system_cpus
      kubeReserved = {
        cpu    = var.kube_reserved_cpu
        memory = var.kube_reserved_memory
      }
      systemReserved = {
        cpu    = var.system_reserved_cpu
        memory = var.system_reserved_memory
      }
    })
  }
}

# ConfigMap with sysctl tuning parameters
resource "kubernetes_config_map_v1" "gpu_sysctl_config" {
  metadata {
    name      = "gpu-node-sysctl-config"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "gpu-node-tuning"
      "app.kubernetes.io/component" = "sysctl-config"
    }
  }

  data = {
    "sysctl.conf" = <<-EOT
      # NCCL network buffer tuning
      net.core.rmem_max = 16777216
      net.core.wmem_max = 16777216
      net.ipv4.tcp_rmem = 4096 87380 16777216
      net.ipv4.tcp_wmem = 4096 65536 16777216

      # Disable auto-NUMA balancing (managed explicitly)
      kernel.numa_balancing = 0

      # HugePages
      vm.nr_hugepages = ${var.hugepages_count}

      # Increase max memory map areas for large models
      vm.max_map_count = 1048576
    EOT
  }
}

# ConfigMap with Bottlerocket userdata settings for GPU nodes
resource "kubernetes_config_map_v1" "gpu_bottlerocket_config" {
  metadata {
    name      = "gpu-node-bottlerocket-config"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "gpu-node-tuning"
      "app.kubernetes.io/component" = "bottlerocket-config"
    }
  }

  data = {
    "bottlerocket-settings.toml" = <<-EOT
      [settings.kubernetes]
      topology-manager-policy = "single-numa-node"
      cpu-manager-policy = "static"
      allowed-unsafe-sysctls = ["net.core.*", "net.ipv4.*", "kernel.numa_balancing", "vm.nr_hugepages", "vm.max_map_count"]
      system-reserved = { cpu = "${var.system_reserved_cpu}", memory = "${var.system_reserved_memory}" }
      kube-reserved = { cpu = "${var.kube_reserved_cpu}", memory = "${var.kube_reserved_memory}" }

      [settings.kernel]
      hugepages.hugepagesz = "${var.hugepage_size}"
      hugepages.nr_hugepages = ${var.hugepages_count}

      [settings.kernel.sysctl]
      "net.core.rmem_max" = "16777216"
      "net.core.wmem_max" = "16777216"
      "net.ipv4.tcp_rmem" = "4096 87380 16777216"
      "net.ipv4.tcp_wmem" = "4096 65536 16777216"
      "kernel.numa_balancing" = "0"
      "vm.max_map_count" = "1048576"

      [settings.boot]
      kernel-parameters = [
        "isolcpus=${var.isolated_cpus}",
        "nohz_full=${var.isolated_cpus}",
        "rcu_nocbs=${var.isolated_cpus}",
        "default_hugepagesz=${var.hugepage_size}",
        "hugepagesz=${var.hugepage_size}",
        "hugepages=${var.hugepages_count}",
        "intel_pstate=disable",
        "processor.max_cstate=0",
        "intel_idle.max_cstate=0"
      ]
    EOT
  }
}

# DaemonSet for runtime tuning validation on GPU nodes
resource "kubernetes_daemon_set_v1" "gpu_tuning_validator" {
  metadata {
    name      = "gpu-tuning-validator"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "gpu-node-tuning"
      "app.kubernetes.io/component" = "validator"
    }
  }

  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "gpu-tuning-validator"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "gpu-tuning-validator"
        }
      }

      spec {
        node_selector = {
          "node-role" = "gpu"
        }

        toleration {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        host_pid     = true
        host_network = true

        container {
          name  = "validator"
          image = "busybox:1.37"
          command = [
            "/bin/sh", "-c",
            <<-SCRIPT
              echo "=== GPU Node Tuning Validation ==="
              echo "--- CPU Isolation ---"
              cat /proc/cmdline | tr ' ' '\n' | grep -E 'isolcpus|nohz_full|rcu_nocbs'
              echo "--- HugePages ---"
              cat /proc/meminfo | grep -i huge
              echo "--- NUMA ---"
              ls -la /sys/devices/system/node/
              echo "--- Sysctl ---"
              sysctl net.core.rmem_max net.core.wmem_max kernel.numa_balancing vm.max_map_count
              echo "--- Topology Manager ---"
              cat /var/lib/kubelet/config.yaml 2>/dev/null | grep -A2 topologyManager || echo "kubelet config not accessible"
              echo "=== Validation Complete ==="
              sleep infinity
            SCRIPT
          ]

          resources {
            limits = {
              cpu    = "50m"
              memory = "32Mi"
            }
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
          }

          security_context {
            privileged                = true
            read_only_root_filesystem = true
          }
        }
      }
    }
  }
}
