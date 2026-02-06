output "release_name" {
  description = "Name of the Falco Helm release"
  value       = helm_release.falco.name
}

output "release_version" {
  description = "Version of installed Falco chart"
  value       = helm_release.falco.version
}

output "namespace" {
  description = "Namespace where Falco is installed"
  value       = helm_release.falco.namespace
}
