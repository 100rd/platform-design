# ---------------------------------------------------------------------------------------------------------------------
# Route53 Resolver — Cross-Account DNS Resolution
# ---------------------------------------------------------------------------------------------------------------------
# Creates Route53 Resolver endpoints for DNS resolution between VPCs,
# on-premises, and 3rd-party networks via the network account.
# ---------------------------------------------------------------------------------------------------------------------

# Inbound Resolver Endpoint — allows on-prem/VPN to resolve AWS private zones
resource "aws_route53_resolver_endpoint" "inbound" {
  count = var.enable_inbound ? 1 : 0

  name      = "${var.name}-inbound"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.resolver[0].id]

  dynamic "ip_address" {
    for_each = var.subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-inbound-resolver"
  })
}

# Outbound Resolver Endpoint — allows AWS to resolve on-prem/partner DNS
resource "aws_route53_resolver_endpoint" "outbound" {
  count = var.enable_outbound ? 1 : 0

  name      = "${var.name}-outbound"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.resolver[0].id]

  dynamic "ip_address" {
    for_each = var.subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-outbound-resolver"
  })
}

# Security group for resolver endpoints
resource "aws_security_group" "resolver" {
  count = (var.enable_inbound || var.enable_outbound) ? 1 : 0

  name_prefix = "${var.name}-resolver-"
  description = "Security group for Route53 Resolver endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description = "DNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-resolver-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Forwarding rules — resolve partner/on-prem domains via their DNS
resource "aws_route53_resolver_rule" "forward" {
  for_each = var.enable_outbound ? var.forwarding_rules : {}

  domain_name          = each.value.domain
  name                 = "${var.name}-fwd-${each.key}"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound[0].id

  dynamic "target_ip" {
    for_each = each.value.target_ips
    content {
      ip   = target_ip.value.ip
      port = try(target_ip.value.port, 53)
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-fwd-${each.key}"
  })
}

# Share forwarding rules with the organization via RAM
resource "aws_route53_resolver_rule_association" "shared" {
  for_each = var.enable_outbound ? var.forwarding_rules : {}

  resolver_rule_id = aws_route53_resolver_rule.forward[each.key].id
  vpc_id           = var.vpc_id
}
