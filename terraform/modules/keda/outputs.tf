output "release_name" {
  description = "Name of the KEDA Helm release"
  value       = helm_release.keda.name
}

output "release_version" {
  description = "Version of installed KEDA chart"
  value       = helm_release.keda.version
}

output "namespace" {
  description = "Namespace where KEDA is installed"
  value       = helm_release.keda.namespace
}
