output "runtimeclass_name" {
  description = "Name of the Kata CC RuntimeClass"
  value       = kubernetes_manifest.kata_cc_runtimeclass.manifest.metadata.name
}

output "runtimeclass_handler" {
  description = "Kata CC handler name"
  value       = kubernetes_manifest.kata_cc_runtimeclass.manifest.handler
}

output "network_policy_name" {
  description = "Name of the CiliumNetworkPolicy for CC workloads"
  value       = kubernetes_manifest.kata_cc_network_policy.manifest.metadata.name
}

output "attestation_configmap_name" {
  description = "Name of the attestation configuration ConfigMap"
  value       = kubernetes_config_map_v1.kata_cc_attestation_config.metadata[0].name
}

output "attestation_configmap_namespace" {
  description = "Namespace of the attestation configuration ConfigMap"
  value       = kubernetes_config_map_v1.kata_cc_attestation_config.metadata[0].namespace
}

output "kata_version" {
  description = "Kata Containers version deployed"
  value       = var.kata_version
}
