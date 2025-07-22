terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.39.0"
    }
  }
}

resource "hcloud_server" "node" {
  count       = var.node_count
  name        = "${var.name_prefix}-${count.index}"
  server_type = var.server_type
  image       = var.image
  location    = var.location
  ssh_keys    = var.ssh_keys
  user_data   = var.user_data
  labels      = var.labels
}

output "node_ips" {
  description = "Public IPv4 addresses of Hetzner nodes"
  value       = [for s in hcloud_server.node : s.ipv4_address]
}
