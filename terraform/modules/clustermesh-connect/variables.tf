variable "remote_clusters" {
  description = "Map of remote cluster names to their ClusterMesh connection details"
  type = map(object({
    endpoint = string
    ca_cert  = string
    tls_cert = string
    tls_key  = string
  }))
  default = {}
}
