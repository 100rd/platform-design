mock_provider "aws" {}

variables {
  name               = "test-vpn"
  transit_gateway_id = "tgw-12345"
  vpn_connections = {
    office = {
      customer_gateway_ip = "203.0.113.1"
      bgp_asn             = 65000
      static_routes       = ["192.168.0.0/16"]
    }
  }
  tags = {
    Environment = "test"
    Team        = "network"
    ManagedBy   = "terraform"
  }
}

run "creates_customer_gateway" {
  command = plan

  assert {
    condition     = length(aws_customer_gateway.this) == 1
    error_message = "Should create 1 customer gateway"
  }
}

run "creates_vpn_connection" {
  command = plan

  assert {
    condition     = length(aws_vpn_connection.this) == 1
    error_message = "Should create 1 VPN connection"
  }
}
