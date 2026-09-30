# ---------------------------------------------------------------------------------------------------------------------
# VPC Endpoints (PrivateLink)
# ---------------------------------------------------------------------------------------------------------------------
# Creates VPC endpoints for core AWS services to keep traffic off the public internet
# and avoid NAT Gateway costs. Uses terraform-aws-modules/vpc//modules/vpc-endpoints.
#
# Services included:
#   Gateway:   S3, DynamoDB (free — no hourly charge)
#   Interface: SSM, SSMMessages, EC2Messages, EC2, ECR API, ECR DKR, STS, SNS, SQS,
#              CloudWatch Logs, CloudWatch Monitoring, Secrets Manager, KMS
#
# Benefits:
#   - Eliminates NAT Gateway traffic charges for AWS API calls
#   - Keeps traffic on AWS backbone (security + latency)
#   - Required for SSM Session Manager on private instances
#   - Required for ECR pulls from private subnets
# ---------------------------------------------------------------------------------------------------------------------

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.6.0"

  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  endpoints = {
    # ─── Gateway Endpoints (free, no hourly charge) ──────────────────────────
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = var.route_table_ids
      tags            = { Name = "${var.name_prefix}s3" }
    }

    dynamodb = {
      service         = "dynamodb"
      service_type    = "Gateway"
      route_table_ids = var.route_table_ids
      tags            = { Name = "${var.name_prefix}dynamodb" }
    }

    # ─── Interface Endpoints ─────────────────────────────────────────────────

    ssm = {
      service             = "ssm"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}ssm" }
    }

    ssmmessages = {
      service             = "ssmmessages"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}ssmmessages" }
    }

    ec2messages = {
      service             = "ec2messages"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}ec2messages" }
    }

    ec2 = {
      service             = "ec2"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}ec2" }
    }

    ecr_api = {
      service             = "ecr.api"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}ecr-api" }
    }

    ecr_dkr = {
      service             = "ecr.dkr"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}ecr-dkr" }
    }

    sts = {
      service             = "sts"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}sts" }
    }

    sns = {
      service             = "sns"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}sns" }
    }

    sqs = {
      service             = "sqs"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}sqs" }
    }

    logs = {
      service             = "logs"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}logs" }
    }

    monitoring = {
      service             = "monitoring"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}monitoring" }
    }

    secretsmanager = {
      service             = "secretsmanager"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}secretsmanager" }
    }

    kms = {
      service             = "kms"
      service_type        = "Interface"
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}kms" }
    }
  }

  tags = var.tags
}
