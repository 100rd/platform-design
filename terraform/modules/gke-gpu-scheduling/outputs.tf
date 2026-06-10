output "enabled" {
  description = "Whether a batch scheduler was deployed by this module."
  value       = var.enabled
}

output "scheduler" {
  description = "Which batch scheduler was deployed (kueue or volcano); null when disabled."
  value       = var.enabled ? var.scheduler : null
}

output "namespace" {
  description = "Namespace the scheduler is installed into (null when disabled)."
  value       = var.enabled ? kubernetes_namespace.scheduling[0].metadata[0].name : null
}

output "release_name" {
  description = "Helm release name of the deployed scheduler (null when disabled)."
  value = var.enabled ? (
    local.deploy_kueue ? helm_release.kueue[0].name : helm_release.volcano[0].name
  ) : null
}

output "platform_labels" {
  description = "Effective ADR-0028 Kubernetes-plane labels applied to scheduler resources."
  value       = local.platform_labels
}
