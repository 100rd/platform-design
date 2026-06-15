# ---------------------------------------------------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------------------------------------------------
# Derived from inputs/locals (not from the count-gated resource) so they resolve cleanly even
# when enabled = false and no Application object is created. Consumers (dependency blocks in
# other units) get stable values during plan/validate.
# ---------------------------------------------------------------------------------------------------------------------

output "application_name" {
  description = "Name of the rendered ArgoCD Application (metadata.name)."
  value       = var.app_name
}

output "namespace" {
  description = "Namespace where the ArgoCD Application object is created (metadata.namespace, i.e. the ArgoCD namespace)."
  value       = var.argocd_namespace
}

output "destination_namespace" {
  description = "Destination namespace in the target cluster where the application is deployed."
  value       = var.destination_namespace
}

output "labels" {
  description = "Normalized ADR-0028 taxonomy labels applied to the Application metadata (dotted K8s label keys)."
  value       = local.normalized_labels
}

output "enabled" {
  description = "Whether the Application resource was actually rendered (apply gate). False on a default plan/validate."
  value       = var.enabled
}
