mock_provider "aws" {}

variables {
  name               = "network-eu-west-1"
  transit_gateway_id = "tgw-12345"

  tags = {
    Environment = "network"
    ManagedBy   = "terraform"
  }
}

# Default posture: VPN routing is off and the NACL backstop is off (the
# sequencing gate). No TGW route table, no routes, no NACL rules.
run "deny_by_default_creates_nothing" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table.network_vpn) == 0
    error_message = "No VPN route table should exist until enable_vpn_routing = true"
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route.vpn_forward) == 0
    error_message = "No forward routes should exist until enable_vpn_routing = true"
  }

  assert {
    condition     = length(aws_network_acl_rule.prod_deny_standard_subpool) == 0
    error_message = "No NACL backstop rules should exist until enable_prod_nacl_backstop = true"
  }
}

# Prod NACL backstop can be applied independently and BEFORE routing is enabled.
run "prod_nacl_backstop_applies_allow_and_deny" {
  command = plan

  variables {
    enable_prod_nacl_backstop = true
    prod_subnet_nacl_ids      = ["acl-prod-a", "acl-prod-b"]
  }

  assert {
    condition     = length(aws_network_acl_rule.prod_allow_ops_subpool) == 2
    error_message = "Ops ALLOW rule should be applied to each prod subnet NACL"
  }

  assert {
    condition     = length(aws_network_acl_rule.prod_deny_standard_subpool) == 2
    error_message = "Standard DENY rule should be applied to each prod subnet NACL"
  }

  assert {
    condition     = alltrue([for r in aws_network_acl_rule.prod_deny_standard_subpool : r.rule_action == "deny"])
    error_message = "The standard sub-pool rule must be a deny rule"
  }
}

# When routing is enabled, the VPN RT and the allow-list forward routes appear.
run "vpn_routing_creates_segmented_route_table" {
  command = plan

  variables {
    enable_vpn_routing = true
    network_vpc_id     = "vpc-network"

    vpn_forward_routes = {
      shared = { destination_cidr = "10.10.0.0/16", tgw_attachment_id = "tgw-attach-shared" }
      prod   = { destination_cidr = "10.30.0.0/16", tgw_attachment_id = "tgw-attach-prod" }
      legacy = { destination_cidr = "172.21.0.0/16", tgw_attachment_id = "tgw-attach-legacy-admin" }
    }

    vpn_return_routes = {
      # Prod-tier RT returns ONLY to the ops sub-pool (asymmetric return).
      prod = { route_table_id = "tgw-rtb-prod", vpn_pool_cidr = "10.100.0.0/24" }
      # Shared-tier RT returns the full pool.
      shared = { route_table_id = "tgw-rtb-shared", vpn_pool_cidr = "10.100.0.0/20" }
    }
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table.network_vpn) == 1
    error_message = "The isolated VPN route table should be created when routing is enabled"
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route.vpn_forward) == 3
    error_message = "One forward route per allow-list entry should be created"
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route.vpn_return) == 2
    error_message = "One return route per spoke RT should be created"
  }
}

run "vpn_routing_off_by_default" {
  command = plan

  assert {
    condition     = var.enable_vpn_routing == false
    error_message = "enable_vpn_routing must default to false (sequencing gate)"
  }
}
