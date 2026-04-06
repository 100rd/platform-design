output "vector_namespace" {
  description = "Kubernetes namespace where Vector DaemonSet is deployed"
  value       = kubernetes_namespace.logging.metadata[0].name
}

output "clickhouse_endpoint" {
  description = "ClickHouse HTTP endpoint reachable from within the cluster"
  value       = "http://clickhouse.${var.clickhouse_namespace}.svc.cluster.local:8123"
}

output "clickhouse_version" {
  description = "Installed ClickHouse Helm chart version"
  value       = helm_release.clickhouse.version
}

output "vector_version" {
  description = "Installed Vector Helm chart version"
  value       = helm_release.vector.version
}
