# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference DCGM Exporter — Outputs
# ---------------------------------------------------------------------------------------------------------------------

output "dcgm_namespace" {
  description = "Kubernetes namespace where DCGM Exporter is deployed"
  value       = kubernetes_namespace.dcgm.metadata[0].name
}

output "metrics_endpoint" {
  description = "In-cluster metrics endpoint for DCGM Exporter (ClusterIP service)"
  value       = "http://dcgm-exporter.${kubernetes_namespace.dcgm.metadata[0].name}.svc.cluster.local:9400/metrics"
}

output "dcgm_exporter_version" {
  description = "Deployed DCGM Exporter Helm chart version"
  value       = helm_release.dcgm_exporter.version
}

output "auto_taint_enabled" {
  description = "Whether GPU health auto-tainting is enabled"
  value       = var.enable_auto_taint
}

output "xid_error_threshold" {
  description = "XID error threshold used to trigger node tainting"
  value       = var.xid_error_threshold
}

output "temperature_threshold" {
  description = "GPU temperature threshold (Celsius) used for alerting"
  value       = var.temperature_threshold
}
