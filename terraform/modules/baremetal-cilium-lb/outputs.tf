output "enabled" {
  description = "Whether Cilium + LB/BGP was deployed."
  value       = var.enabled
}

output "release_name" {
  description = "Cilium Helm release name (null when disabled)."
  value       = var.enabled ? helm_release.cilium[0].name : null
}

output "bgp_enabled" {
  description = "Whether the BGP control-plane peering was configured (false = LB-IPAM-only / L2 fallback, ADR-0051)."
  value       = local.enable_bgp
}

output "lb_ipam_cidrs" {
  description = "Service-VIP CIDR blocks LB-IPAM advertises."
  value       = var.lb_ipam_cidrs
}

output "mtu" {
  description = "Datapath MTU (9000 jumbo frames for the GPU fabric)."
  value       = var.mtu
}

output "platform_labels" {
  description = "Effective ADR-0028 dotted labels."
  value       = local.platform_labels
}
