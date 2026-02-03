output "cilium_version" {
  description = "Deployed Cilium version"
  value       = var.cilium_version
}

output "hubble_enabled" {
  description = "Whether Hubble observability is enabled"
  value       = var.enable_hubble
}

output "hubble_ui_enabled" {
  description = "Whether Hubble UI is enabled"
  value       = var.enable_hubble_ui
}

output "kube_proxy_replacement" {
  description = "Whether kube-proxy is replaced by Cilium eBPF"
  value       = var.replace_kube_proxy
}
