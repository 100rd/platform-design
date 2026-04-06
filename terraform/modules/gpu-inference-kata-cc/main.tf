# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Kata CC — Kata Containers v3.22 + GPU Confidential Computing
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Kata Containers v3.22 RuntimeClass for GPU Confidential Computing (CC)
# workloads on the gpu-inference cluster. Kata CC isolates each pod in a
# hardware-attested micro-VM (TDX or SEV-SNP), preventing host-level access
# to GPU memory containing model weights and inference data.
#
# Resources:
#   - RuntimeClass: kata-cc-gpu  — schedules pods onto CC-capable GPU nodes
#   - CiliumNetworkPolicy         — restricts CC workload egress/ingress
#   - ConfigMap: kata-cc-attestation-config — attestation service settings
# ---------------------------------------------------------------------------------------------------------------------

# RuntimeClass — kata-cc-gpu handler with pod overhead and CC node scheduling
resource "kubernetes_manifest" "kata_cc_runtimeclass" {
  manifest = {
    apiVersion = "node.k8s.io/v1"
    kind       = "RuntimeClass"
    metadata = {
      name = "kata-cc-gpu"
      annotations = {
        "kata-containers.io/version"    = var.kata_version
        "confidential-computing/tee"    = var.attestation_tee_type
        "confidential-computing/vendor" = "nvidia"
      }
    }
    handler = "kata-cc"
    overhead = {
      podFixed = {
        cpu    = "250m"
        memory = "160Mi"
      }
    }
    scheduling = {
      nodeClassification = {
        tolerated = [
          {
            key      = "nvidia.com/gpu"
            operator = "Exists"
            effect   = "NoSchedule"
          },
          {
            key      = "kata-cc"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]
      }
      nodeSelector = {
        "nvidia.com/cc.enabled" = "true"
      }
    }
  }
}

# CiliumNetworkPolicy — restrict CC workload egress/ingress to attestation and GPU peers
resource "kubernetes_manifest" "kata_cc_network_policy" {
  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "kata-cc-gpu-policy"
      namespace = var.cc_namespace
      labels = {
        "app.kubernetes.io/name"      = "kata-cc-gpu"
        "app.kubernetes.io/component" = "network-policy"
      }
    }
    spec = {
      endpointSelector = {
        matchLabels = {
          "app"                        = var.cc_app_label
          "runtime.kata-containers.io" = "kata-cc"
        }
      }
      # Ingress: allow only from within the same namespace and from kube-system monitoring
      ingress = [
        {
          fromEndpoints = [
            {
              matchLabels = {
                "k8s:io.kubernetes.pod.namespace" = var.cc_namespace
              }
            },
            {
              matchLabels = {
                "k8s:io.kubernetes.pod.namespace" = "kube-system"
                "app.kubernetes.io/name"          = "hubble-relay"
              }
            }
          ]
        }
      ]
      # Egress: allow to attestation service (HTTPS), Kubernetes API, and DNS
      egress = [
        {
          # DNS resolution
          toEndpoints = [
            {
              matchLabels = {
                "k8s:io.kubernetes.pod.namespace" = "kube-system"
                "k8s-app"                         = "kube-dns"
              }
            }
          ]
          toPorts = [
            {
              ports = [
                {
                  port     = "53"
                  protocol = "UDP"
                },
                {
                  port     = "53"
                  protocol = "TCP"
                }
              ]
            }
          ]
        },
        {
          # Attestation service — HTTPS
          toCIDR = ["0.0.0.0/0"]
          toPorts = [
            {
              ports = [
                {
                  port     = "8443"
                  protocol = "TCP"
                }
              ]
            }
          ]
        },
        {
          # Kubernetes API for pod metadata
          toEntities = ["kube-apiserver"]
          toPorts = [
            {
              ports = [
                {
                  port     = "443"
                  protocol = "TCP"
                }
              ]
            }
          ]
        },
        {
          # Intra-namespace traffic (NCCL, vLLM tensor parallelism)
          toEndpoints = [
            {
              matchLabels = {
                "k8s:io.kubernetes.pod.namespace" = var.cc_namespace
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.kata_cc_runtimeclass]
}

# ConfigMap — attestation service configuration for Kata CC workloads
resource "kubernetes_config_map_v1" "kata_cc_attestation_config" {
  metadata {
    name      = "kata-cc-attestation-config"
    namespace = var.cc_namespace
    labels = {
      "app.kubernetes.io/name"      = "kata-cc-gpu"
      "app.kubernetes.io/component" = "attestation-config"
    }
    annotations = {
      "kata-containers.io/version" = var.kata_version
      "confidential-computing/tee" = var.attestation_tee_type
    }
  }

  data = {
    "attestation.toml" = <<-EOT
      # Kata Containers v${var.kata_version} — Confidential Computing Attestation
      [agent.policy]
      policy_namespace = "${var.attestation_policy_namespace}"

      [attestation]
      # Remote attestation service endpoint
      service_url = "${var.attestation_service_url}"
      tee_type    = "${var.attestation_tee_type}"

      # Attestation retry settings
      retry_max     = 5
      retry_backoff = "2s"

      # Evidence collection
      collect_measurements = true
      collect_eventlog     = true

      [attestation.tls]
      # Verify attestation service TLS certificate
      verify_cert        = true
      system_certs       = true
      # Optional: pin expected server cert hash for pinning
      # server_cert_hash = ""

      [gpu]
      # NVIDIA CC mode — require GPU attestation report in TEE evidence
      require_gpu_attestation = true
      driver_version_min      = "525.105"

      [policy]
      # OPA policy endpoint for attestation result enforcement
      opa_endpoint       = "${var.attestation_service_url}/opa/v1"
      opa_policy_path    = "/gpu/cc/allow"

      [logging]
      level  = "info"
      format = "json"
    EOT

    "kata-configuration-cc.toml" = <<-EOT
      # Kata Containers v${var.kata_version} — GPU CC Runtime Configuration
      [hypervisor.qemu]
      # Use QEMU with TDX/SEV-SNP support
      path   = "/usr/bin/qemu-system-x86_64"
      kernel = "/usr/share/kata-containers/vmlinuz-cc"
      image  = "/usr/share/kata-containers/kata-cc.img"

      # Memory encryption — TDX or SEV-SNP
      confidential_guest = true

      # GPU passthrough via VFIO
      hotplug_vfio_on_root_bus = true
      default_max_vcpus        = 192

      # Memory for GPU workloads — model weights + KV cache
      default_memory = 131072

      [agent]
      # Use vsock for host-guest communication
      use_vsock  = true
      log_level  = "info"

      [runtime]
      # Enable CC-specific runtime features
      enable_cpu_memory_hotplug = false
      sandbox_cgroup_only       = true
    EOT
  }
}
