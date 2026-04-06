output "volcano_namespace" {
  description = "Namespace where Volcano is deployed"
  value       = helm_release.volcano.namespace
}

output "volcano_version" {
  description = "Volcano Helm chart version deployed"
  value       = helm_release.volcano.version
}

output "queue_names" {
  description = "List of Volcano queue names created"
  value = [
    kubernetes_manifest.queue_training.manifest.metadata.name,
    kubernetes_manifest.queue_inference.manifest.metadata.name,
    kubernetes_manifest.queue_batch.manifest.metadata.name,
  ]
}
