output "cilium_version" {
  description = "Installed Cilium version"
  value       = helm_release.cilium.version
}

output "cilium_namespace" {
  description = "Namespace where Cilium is installed"
  value       = helm_release.cilium.namespace
}

output "pod_cidr" {
  description = "Pod CIDR configured for Cilium cluster-pool IPAM"
  value       = var.pod_cidr
}

output "bgp_local_asn" {
  description = "Local ASN used for BGP peering"
  value       = var.bgp_local_asn
}
