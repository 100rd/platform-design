output "private_network_id" {
  description = "OpenStack UUID of the regional vRack Private Network (consumed by ovh_cloud_project_kube)"
  value       = tolist(ovh_cloud_project_network_private.this.regions_attributes)[0].openstackid
}

output "subnet_id" {
  description = "Subnet ID of the vRack Private Network (consumed by ovh_cloud_project_kube)"
  value       = ovh_cloud_project_network_private_subnet.this.id
}

output "gateway_ip" {
  description = "Gateway IP address inside the private subnet"
  value       = ovh_cloud_project_network_private_subnet.this.gateway_ip
}

output "gateway_id" {
  description = "OVHcloud Public Cloud Gateway ID (if enabled)"
  value       = var.enable_gateway ? ovh_cloud_project_gateway.this[0].id : null
}
