# ---------------------------------------------------------------------------------------------------------------------
# Scaleway GPU VPC & Private Network Module
# ---------------------------------------------------------------------------------------------------------------------
# Provisions an isolated Scaleway VPC, Private Network (with IPAM subnet), and Public Gateway
# (NAT / Masquerade + optional SSH bastion) so private Kapsule GPU nodes have no public IPs
# while retaining high-bandwidth outbound internet access for pulling model weights & OCI images.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  tag_list = [for k, v in var.tags : "${k}=${v}"]
}

resource "scaleway_vpc" "this" {
  project_id     = var.project_id
  name           = var.network_name
  region         = var.region
  enable_routing = true
  tags           = local.tag_list
}

resource "scaleway_vpc_private_network" "this" {
  project_id = var.project_id
  name       = "${var.network_name}-pn"
  region     = var.region
  vpc_id     = scaleway_vpc.this.id
  tags       = local.tag_list

  ipv4_subnet {
    subnet = var.subnet_cidr
  }
}

resource "scaleway_vpc_public_gateway_ip" "this" {
  count      = var.enable_public_gateway ? 1 : 0
  project_id = var.project_id
  zone       = var.zone
  tags       = local.tag_list
}

resource "scaleway_vpc_public_gateway" "this" {
  count           = var.enable_public_gateway ? 1 : 0
  project_id      = var.project_id
  name            = "${var.network_name}-pgw"
  type            = var.public_gateway_type
  zone            = var.zone
  ip_id           = scaleway_vpc_public_gateway_ip.this[0].id
  bastion_enabled = var.bastion_enabled
  tags            = local.tag_list
}

resource "scaleway_vpc_gateway_network" "this" {
  count              = var.enable_public_gateway ? 1 : 0
  gateway_id         = scaleway_vpc_public_gateway.this[0].id
  private_network_id = scaleway_vpc_private_network.this.id
  zone               = var.zone
  enable_masquerade  = true

  ipam_config {
    push_default_route = true
  }
}
