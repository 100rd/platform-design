output "namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = helm_release.argocd.namespace
}

output "chart_version" {
  description = "Deployed ArgoCD Helm chart version"
  value       = helm_release.argocd.version
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.argocd.name
}
