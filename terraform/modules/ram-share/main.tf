# ---------------------------------------------------------------------------------------------------------------------
# AWS Resource Access Manager — Network Account
# ---------------------------------------------------------------------------------------------------------------------
# Shares Transit Gateway with workload accounts in the organization.
# Enables cross-account VPC attachments without manual acceptance.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ram_resource_share" "tgw" {
  name                      = "${var.name}-tgw-share"
  allow_external_principals = false

  tags = merge(var.tags, {
    Name = "${var.name}-tgw-share"
  })
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = var.transit_gateway_arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# Share with the entire organization (all accounts auto-accept)
resource "aws_ram_principal_association" "org" {
  count = var.share_with_organization ? 1 : 0

  principal          = var.organization_arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# Or share with specific accounts
resource "aws_ram_principal_association" "accounts" {
  for_each = var.share_with_organization ? {} : var.share_with_accounts

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# Share subnets if needed (for shared VPC pattern)
resource "aws_ram_resource_share" "subnets" {
  count = length(var.shared_subnet_arns) > 0 ? 1 : 0

  name                      = "${var.name}-subnet-share"
  allow_external_principals = false

  tags = merge(var.tags, {
    Name = "${var.name}-subnet-share"
  })
}

resource "aws_ram_resource_association" "subnets" {
  for_each = { for idx, arn in var.shared_subnet_arns : idx => arn }

  resource_arn       = each.value
  resource_share_arn = aws_ram_resource_share.subnets[0].arn
}
