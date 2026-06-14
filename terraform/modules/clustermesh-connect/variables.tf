variable "remote_clusters" {
  description = "Map of remote cluster names to their ClusterMesh connection details (literal certs). Prefer remote_clusters_from_secrets for the cross-region cert exchange."
  type = map(object({
    endpoint = string
    ca_cert  = string
    tls_cert = string
    tls_key  = string
  }))
  default = {}
}

variable "remote_clusters_from_secrets" {
  description = "Map of remote cluster names to their ClusterMesh endpoint + the AWS Secrets Manager secret IDs holding the peer CA / client cert / client key. The module resolves the secret values at apply time. Empty by default so plan/validate stay offline (no Secrets Manager reads) until the cross-region cert exchange has populated the secrets."
  type = map(object({
    endpoint       = string # peer clustermesh-apiserver endpoint, e.g. <nlb-dns>:2379
    ca_secret_id   = string # Secrets Manager secret holding the peer etcd CA cert (PEM)
    cert_secret_id = string # Secrets Manager secret holding the client cert (PEM)
    key_secret_id  = string # Secrets Manager secret holding the client key (PEM)
  }))
  default = {}
}
