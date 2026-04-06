output "hpa_name" {
  description = "Name of the vLLM HorizontalPodAutoscaler"
  value       = kubernetes_horizontal_pod_autoscaler_v2.vllm.metadata[0].name
}

output "prometheus_adapter_namespace" {
  description = "Namespace where Prometheus Adapter is installed"
  value       = helm_release.prometheus_adapter.namespace
}

output "prometheus_adapter_release_name" {
  description = "Helm release name of Prometheus Adapter"
  value       = helm_release.prometheus_adapter.name
}

output "prometheus_adapter_version" {
  description = "Installed version of the prometheus-adapter Helm chart"
  value       = helm_release.prometheus_adapter.version
}
