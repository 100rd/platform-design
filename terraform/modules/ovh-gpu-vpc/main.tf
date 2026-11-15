# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud GPU Private Network (vRack) & Gateway Module
# ---------------------------------------------------------------------------------------------------------------------
# Provisions an isolated vRack Private Network, regional private subnet, and OVHcloud
# Public Cloud Gateway (SNAT) in `GRA11` so private MKS GPU nodes can pull model weights
# and container images without public node IPs.
# ---------------------------------------------------------------------------------------------------------------------

resource "ovh_cloud_project_network_private" "this" {
  service_name = var.service_name
  name         = var.network_name
  regions      = [var.region]
  vlan_id      = var.vlan_id
}

resource "ovh_cloud_project_network_private_subnet" "this" {
  service_name = var.service_name
  network_id   = ovh_cloud_project_network_private.this.id
  region       = var.region
  network      = var.subnet_cidr
  start        = cidrhost(var.subnet_cidr, 10)
  end          = cidrhost(var.subnet_cidr, 65500)
  no_gateway   = false
  dhcp         = true
}

resource "ovh_cloud_project_gateway" "this" {
  count        = var.enable_gateway ? 1 : 0
  service_name = var.service_name
  name         = "${var.network_name}-gw"
  model        = var.gateway_model
  region       = var.region
  network_id   = tolist(ovh_cloud_project_network_private.this.regions_attributes)[0].openstackid
  subnet_id    = ovh_cloud_project_network_private_subnet.this.id
}
