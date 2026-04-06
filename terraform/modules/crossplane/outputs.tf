output "crossplane_namespace" {
  description = "Namespace where Crossplane is installed"
  value       = helm_release.crossplane.namespace
}

output "crossplane_version" {
  description = "Installed Crossplane version"
  value       = helm_release.crossplane.version
}
