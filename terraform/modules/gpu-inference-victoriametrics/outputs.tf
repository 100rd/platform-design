output "vmcluster_name" {
  description = "Name of the VMCluster custom resource"
  value       = kubernetes_manifest.vmcluster.manifest.metadata.name
}

output "operator_chart_version" {
  description = "Deployed VictoriaMetrics Operator Helm chart version"
  value       = helm_release.vm_operator.version
}

output "vmselect_endpoint" {
  description = "VMSelect service endpoint for Grafana datasource configuration"
  value       = "http://vmselect-gpu-inference-metrics.monitoring.svc.cluster.local:8481/select/0/prometheus"
}
