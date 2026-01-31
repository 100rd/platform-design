output "release_name" {
  description = "Name of the WPA Helm release"
  value       = var.enabled ? helm_release.wpa[0].name : ""
}

output "enabled" {
  description = "Whether WPA is enabled"
  value       = var.enabled
}
