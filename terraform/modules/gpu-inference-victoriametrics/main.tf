# ---------------------------------------------------------------------------------------------------------------------
# VictoriaMetrics Cluster Mode — GPU Inference Metrics
# ---------------------------------------------------------------------------------------------------------------------
# Deploys VictoriaMetrics Operator and VMCluster CR for high-scale metrics
# collection from 5000 GPU nodes. Cluster mode separates insert, select,
# and storage into independently scalable components.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "vm_operator" {
  name             = "victoria-metrics-operator"
  repository       = "https://victoriametrics.github.io/helm-charts"
  chart            = "victoria-metrics-operator"
  version          = var.operator_chart_version
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 300
}

# VMCluster CR for cluster-mode VictoriaMetrics
resource "kubernetes_manifest" "vmcluster" {
  depends_on = [helm_release.vm_operator]

  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMCluster"
    metadata = {
      name      = "gpu-inference-metrics"
      namespace = "monitoring"
    }
    spec = {
      retentionPeriod = var.retention_period
      vminsert = {
        replicaCount = var.vminsert_replicas
        resources = {
          requests = { cpu = "2", memory = "4Gi" }
          limits   = { cpu = "4", memory = "8Gi" }
        }
      }
      vmselect = {
        replicaCount = var.vmselect_replicas
        resources = {
          requests = { cpu = "2", memory = "8Gi" }
          limits   = { cpu = "4", memory = "16Gi" }
        }
        cacheMountPath = "/select-cache"
      }
      vmstorage = {
        replicaCount    = var.vmstorage_replicas
        storageDataPath = "/vmstorage-data"
        storage = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class
              resources = {
                requests = { storage = var.storage_size }
              }
            }
          }
        }
        resources = {
          requests = { cpu = "2", memory = "4Gi" }
          limits   = { cpu = "4", memory = "8Gi" }
        }
      }
    }
  }
}

# VMServiceScrape for DCGM Exporter
resource "kubernetes_manifest" "vmscrape_dcgm" {
  depends_on = [helm_release.vm_operator]

  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "dcgm-exporter"
      namespace = "monitoring"
    }
    spec = {
      selector = {
        matchLabels = { "app.kubernetes.io/name" = "dcgm-exporter" }
      }
      endpoints = [{ port = "metrics", interval = "15s" }]
    }
  }
}

# VMServiceScrape for Cilium
resource "kubernetes_manifest" "vmscrape_cilium" {
  depends_on = [helm_release.vm_operator]

  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "cilium-agent"
      namespace = "monitoring"
    }
    spec = {
      namespaceSelector = { matchNames = ["kube-system"] }
      selector = {
        matchLabels = { "k8s-app" = "cilium" }
      }
      endpoints = [{ port = "peer-service", interval = "30s" }]
    }
  }
}

# VMNodeScrape for node-exporter / kubelet-cadvisor
resource "kubernetes_manifest" "vmscrape_node" {
  depends_on = [helm_release.vm_operator]

  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMNodeScrape"
    metadata = {
      name      = "kubelet-cadvisor"
      namespace = "monitoring"
    }
    spec = {
      scheme          = "https"
      bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token"
      tlsConfig = {
        insecureSkipVerify = true
      }
      relabelConfigs = [
        {
          action = "labelmap"
          regex  = "__meta_kubernetes_node_label_(.+)"
        }
      ]
    }
  }
}
