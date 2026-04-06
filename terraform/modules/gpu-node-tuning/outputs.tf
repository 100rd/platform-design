output "kubelet_config_name" {
  description = "Name of the kubelet configuration ConfigMap"
  value       = kubernetes_config_map_v1.gpu_kubelet_config.metadata[0].name
}

output "sysctl_config_name" {
  description = "Name of the sysctl configuration ConfigMap"
  value       = kubernetes_config_map_v1.gpu_sysctl_config.metadata[0].name
}

output "bottlerocket_config_name" {
  description = "Name of the Bottlerocket configuration ConfigMap"
  value       = kubernetes_config_map_v1.gpu_bottlerocket_config.metadata[0].name
}

output "validator_daemonset_name" {
  description = "Name of the tuning validator DaemonSet"
  value       = kubernetes_daemon_set_v1.gpu_tuning_validator.metadata[0].name
}
