# ---------------------------------------------------------------------------------------------------------------------
# ClusterMesh Connect Module
# ---------------------------------------------------------------------------------------------------------------------
# Creates Kubernetes secrets for cross-cluster ClusterMesh connections.
# Each remote cluster requires a secret in the kube-system namespace containing
# the ClusterMesh API server endpoint and TLS credentials.
#
# Prerequisites:
#   - Cilium with ClusterMesh enabled on both clusters
#   - ClusterMesh API server running and accessible via NLB
#   - TLS certificates exchanged between clusters
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_secret" "clustermesh_remote" {
  for_each = var.remote_clusters

  metadata {
    name      = "cilium-clustermesh-${each.key}"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "clustermesh.cilium.io/remote" = each.key
    }
  }

  data = {
    "${each.key}"       = each.value.endpoint
    "${each.key}.etcd-client-ca.crt" = each.value.ca_cert
    "tls.crt"           = each.value.tls_cert
    "tls.key"           = each.value.tls_key
  }

  type = "Opaque"
}
