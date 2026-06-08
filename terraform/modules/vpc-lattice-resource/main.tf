# ---------------------------------------------------------------------------------------------------------------------
# VPC Lattice Resource Connectivity (ADR-0023)
# ---------------------------------------------------------------------------------------------------------------------
# Identity-scoped, cross-account/cross-VPC TCP access to an individual resource
# (e.g. an RDS DB ARN) WITHOUT an NLB and WITHOUT threading the flow through the
# intra-region Transit Gateway.
#
# Flow:
#   Resource Gateway (multi-AZ ingress in the resource-owning VPC)
#     -> Resource Configuration (type = ARN -> RDS DB ARN, TCP-only)
#       -> Service Network (carrier)  -> Service Network <-> Resource association
#         -> RAM share (cross-account) -> consumer reaches via SN VPC association
#       Authorization: IAM auth policy on the Service Network (aws:PrincipalOrgID).
#
# Complements ADR-0013 (TGW segmentation stays the general inter-VPC substrate).
# TCP-only, single-region only.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# Resource Gateway — multi-AZ NAT-style ingress fronting the shared resource.
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_vpclattice_resource_gateway" "this" {
  name               = "${var.name}-rgw"
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
  ip_address_type    = var.ip_address_type

  tags = merge(var.tags, {
    Name = "${var.name}-rgw"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Resource Configuration — type = ARN pointing at the target resource ARN (e.g. RDS DB).
# For an arn_resource, port/protocol are derived from the target resource ARN itself,
# so port_ranges/protocol are NOT set here (they are mutually exclusive with arn_resource).
# var.resource_port / var.resource_protocol document the TCP-only invariant (ADR-0023)
# and inform the security-group scoping on the Resource Gateway.
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_vpclattice_resource_configuration" "this" {
  name                        = "${var.name}-rcfg"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.this.id

  type = "ARN"

  resource_configuration_definition {
    arn_resource {
      arn = var.resource_arn
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-rcfg"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Service Network — the carrier the Resource Configuration is associated to and the
# unit shared cross-account via RAM.
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_vpclattice_service_network" "this" {
  name      = "${var.name}-sn"
  auth_type = "AWS_IAM"

  tags = merge(var.tags, {
    Name = "${var.name}-sn"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Associate the Resource Configuration to the Service Network.
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_vpclattice_service_network_resource_association" "this" {
  resource_configuration_identifier = aws_vpclattice_resource_configuration.this.id
  service_network_identifier        = aws_vpclattice_service_network.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-sn-rcfg-assoc"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM auth policy — identity-scoped authorization on the Service Network.
# Scoped via aws:PrincipalOrgID so only principals in our Organization can invoke,
# and (optionally) narrowed to specific principal ARNs. Replaces CIDR/SG-only control.
# ---------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "auth" {
  count = var.enable_auth_policy ? 1 : 0

  statement {
    sid    = "AllowOrgScopedLatticeAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = length(var.allowed_principal_arns) > 0 ? var.allowed_principal_arns : ["*"]
    }

    actions   = ["vpc-lattice-svcs:Invoke"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.principal_org_id]
    }
  }
}

resource "aws_vpclattice_auth_policy" "this" {
  count = var.enable_auth_policy ? 1 : 0

  resource_identifier = aws_vpclattice_service_network.this.arn
  policy              = data.aws_iam_policy_document.auth[0].json
}

# ---------------------------------------------------------------------------------------------------------------------
# RAM cross-account sharing of the Service Network (optional).
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_ram_resource_share" "this" {
  count = var.enable_ram_share ? 1 : 0

  name                      = "${var.name}-sn-share"
  allow_external_principals = false

  tags = merge(var.tags, {
    Name = "${var.name}-sn-share"
  })
}

resource "aws_ram_resource_association" "this" {
  count = var.enable_ram_share ? 1 : 0

  resource_arn       = aws_vpclattice_service_network.this.arn
  resource_share_arn = aws_ram_resource_share.this[0].arn
}

# Share with the entire organization (all member accounts auto-accept).
resource "aws_ram_principal_association" "org" {
  count = var.enable_ram_share && var.share_with_organization ? 1 : 0

  principal          = var.organization_arn
  resource_share_arn = aws_ram_resource_share.this[0].arn
}

# Or share with specific accounts.
resource "aws_ram_principal_association" "accounts" {
  for_each = var.enable_ram_share && !var.share_with_organization ? var.share_with_accounts : {}

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.this[0].arn
}
