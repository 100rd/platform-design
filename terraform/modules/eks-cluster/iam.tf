module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix      = "VPC-CNI-IRSA"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = var.tags
}

# DNS Sync Role - Needs Route53 Full Access for Syncing
module "dns_sync_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "dns-sync-irsa"

  role_policy_arns = {
    route53 = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["dns-failover:dns-sync"]
    }
  }

  tags = var.tags
}

# Failover Controller Role - Needs Secrets Manager Access and Route53 Read
resource "aws_iam_policy" "failover_controller_policy" {
  name        = "${var.cluster_name}-failover-controller-policy"
  description = "Policy for DNS Failover Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = ["arn:aws:secretsmanager:*:*:secret:/dns-failover/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })
}

module "failover_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "failover-controller-irsa"

  role_policy_arns = {
    policy = aws_iam_policy.failover_controller_policy.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["dns-failover:failover-controller"]
    }
  }

  tags = var.tags
}

# DNS Monitor Role - Needs Route53 Read Access
module "dns_monitor_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "dns-monitor-irsa"

  role_policy_arns = {
    route53 = "arn:aws:iam::aws:policy/AmazonRoute53ReadOnlyAccess"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["dns-failover:dns-monitor"]
    }
  }

  tags = var.tags
}
