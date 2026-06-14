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

# ---------------------------------------------------------------------------------------------------------------------
# Resolve peer TLS material from AWS Secrets Manager (cross-region cert exchange).
# for_each is empty by default → no Secrets Manager reads at plan/validate time.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_secretsmanager_secret_version" "ca" {
  for_each  = var.remote_clusters_from_secrets
  secret_id = each.value.ca_secret_id
}

data "aws_secretsmanager_secret_version" "cert" {
  for_each  = var.remote_clusters_from_secrets
  secret_id = each.value.cert_secret_id
}

data "aws_secretsmanager_secret_version" "key" {
  for_each  = var.remote_clusters_from_secrets
  secret_id = each.value.key_secret_id
}

locals {
  # Peers whose TLS material is resolved from Secrets Manager, normalised to the
  # same shape as var.remote_clusters.
  resolved_from_secrets = {
    for name, cfg in var.remote_clusters_from_secrets : name => {
      endpoint = cfg.endpoint
      ca_cert  = data.aws_secretsmanager_secret_version.ca[name].secret_string
      tls_cert = data.aws_secretsmanager_secret_version.cert[name].secret_string
      tls_key  = data.aws_secretsmanager_secret_version.key[name].secret_string
    }
  }

  # All remote clusters to wire (literal certs + Secrets-Manager-resolved).
  all_remotes = merge(var.remote_clusters, local.resolved_from_secrets)
}

resource "kubernetes_secret" "clustermesh_remote" {
  for_each = local.all_remotes

  metadata {
    name      = "cilium-clustermesh-${each.key}"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "clustermesh.cilium.io/remote" = each.key
    }
  }

  data = {
    "${each.key}"                    = each.value.endpoint
    "${each.key}.etcd-client-ca.crt" = each.value.ca_cert
    "tls.crt"                        = each.value.tls_cert
    "tls.key"                        = each.value.tls_key
  }

  type = "Opaque"
}
