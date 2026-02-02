output "argocd_crds_installed" {
  description = "Whether ArgoCD CRDs have been installed"
  value       = true

  depends_on = [
    kubectl_manifest.argocd_application_crd,
    kubectl_manifest.argocd_appproject_crd,
    kubectl_manifest.argocd_applicationset_crd,
  ]
}

output "cert_manager_crds_installed" {
  description = "Whether cert-manager CRDs have been installed"
  value       = true

  depends_on = [kubectl_manifest.cert_manager_crds]
}

output "external_secrets_crds_installed" {
  description = "Whether External Secrets CRDs have been installed"
  value       = true

  depends_on = [kubectl_manifest.external_secrets_crds]
}

output "prometheus_operator_crds_installed" {
  description = "Whether Prometheus Operator CRDs have been installed"
  value       = true

  depends_on = [helm_release.prometheus_operator_crds]
}

output "gatekeeper_crds_installed" {
  description = "Whether Gatekeeper CRDs have been installed"
  value       = true

  depends_on = [kubectl_manifest.gatekeeper_crds]
}

output "velero_crds_installed" {
  description = "Whether Velero CRDs have been installed"
  value       = true

  depends_on = [kubectl_manifest.velero_crds]
}

output "kargo_crds_installed" {
  description = "Whether Kargo CRDs have been installed"
  value       = true

  depends_on = [kubectl_manifest.kargo_crds]
}

output "all_crds_installed" {
  description = "Whether all platform CRDs have been installed"
  value       = true

  depends_on = [
    kubectl_manifest.argocd_application_crd,
    kubectl_manifest.argocd_appproject_crd,
    kubectl_manifest.argocd_applicationset_crd,
    kubectl_manifest.cert_manager_crds,
    kubectl_manifest.external_secrets_crds,
    helm_release.prometheus_operator_crds,
    kubectl_manifest.gatekeeper_crds,
    kubectl_manifest.velero_crds,
    kubectl_manifest.kargo_crds,
  ]
}
