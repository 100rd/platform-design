# ---------------------------------------------------------------------------------------------------------------------
# Falco — Runtime Security & File Integrity Monitoring
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Falco for runtime threat detection and file integrity monitoring (FIM).
# Uses modern eBPF driver (no kernel module required).
# Includes Falcosidekick for alert routing.
#
# PCI-DSS Requirements:
#   Req 5.1/5.2 — Anti-malware: detect malicious processes (crypto miners, reverse shells)
#   Req 10.2    — Audit logging: system-level event capture
#   Req 11.5    — File Integrity Monitoring: detect unauthorized changes to system binaries
#   Req 11.5.1  — Alert on unauthorized modification of critical system files
#
# Prerequisites:
#   - EKS cluster with eBPF support (Bottlerocket nodes recommended)
#   - Helm provider configured
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "falco" {
  name             = "falco"
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = "https://falcosecurity.github.io/charts"
  chart            = "falco"
  version          = var.chart_version

  wait          = true
  wait_for_jobs = true
  timeout       = 600

  values = [
    yamlencode({
      # Modern eBPF driver — no kernel headers or DKMS required
      driver = {
        kind = var.driver_kind
      }

      # Falco engine configuration
      falco = {
        grpc = {
          enabled = true
        }
        grpc_output = {
          enabled = true
        }
        json_output          = true
        json_include_output_property = true
        log_stderr           = true
        log_syslog           = false
        log_level            = var.log_level
        priority             = var.minimum_priority
        buffered_outputs     = false
        http_output = {
          enabled = var.enable_sidekick
          url     = var.enable_sidekick ? "http://falco-falcosidekick:2801" : ""
        }
      }

      # Kubernetes metadata collection
      collectors = {
        kubernetes = {
          enabled = true
        }
      }

      # Falcosidekick for alert routing (Slack, PagerDuty, CloudWatch, etc.)
      falcosidekick = {
        enabled = var.enable_sidekick
        config = {
          webhook = {
            minimumpriority = var.minimum_priority
          }
        }
      }

      # Resource limits
      resources = {
        requests = {
          cpu    = var.falco_resources.requests.cpu
          memory = var.falco_resources.requests.memory
        }
        limits = {
          cpu    = var.falco_resources.limits.cpu
          memory = var.falco_resources.limits.memory
        }
      }

      # Tolerations — Falco must run on ALL nodes including CDE-tainted nodes
      tolerations = [
        {
          operator = "Exists"
        }
      ]

      # Run on Linux nodes only
      nodeSelector = {
        "kubernetes.io/os" = "linux"
      }

      # Pod labels for network policy targeting
      podLabels = {
        "app.kubernetes.io/part-of" = "falco-security"
        "pci-dss/component"         = "runtime-security"
      }
    })
  ]
}

# Custom Falco rules for PCI-DSS compliance
resource "kubernetes_config_map" "falco_pci_rules" {
  count = var.custom_rules_enabled ? 1 : 0

  metadata {
    name      = "falco-pci-dss-rules"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/part-of" = "falco-security"
      "pci-dss/component"         = "custom-rules"
    }
  }

  data = {
    "pci-dss-rules.yaml" = var.custom_rules_yaml
  }

  depends_on = [helm_release.falco]
}
