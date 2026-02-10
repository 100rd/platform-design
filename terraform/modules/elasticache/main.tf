resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = var.tags
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-redis-"
  vpc_id      = var.vpc_id
  description = "Security group for ElastiCache Redis cluster ${var.name}"

  ingress {
    description     = "Redis from EKS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow outbound within VPC"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# CloudWatch log groups for Redis logging - PCI-DSS Req 10.1, 10.7
resource "aws_cloudwatch_log_group" "slow_log" {
  count = var.slow_log_enabled ? 1 : 0

  name              = "/elasticache/${var.name}/slow-log"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "engine_log" {
  count = var.engine_log_enabled ? 1 : 0

  name              = "/elasticache/${var.name}/engine-log"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = var.description

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  parameter_group_name = var.parameter_group_name
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token                 = var.auth_token

  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window
  maintenance_window       = var.maintenance_window

  apply_immediately = var.apply_immediately

  # Redis slow log - PCI-DSS Req 10.1 (audit trails)
  dynamic "log_delivery_configuration" {
    for_each = var.slow_log_enabled ? [1] : []
    content {
      destination      = aws_cloudwatch_log_group.slow_log[0].name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "slow-log"
    }
  }

  # Redis engine log - PCI-DSS Req 10.1 (audit trails)
  dynamic "log_delivery_configuration" {
    for_each = var.engine_log_enabled ? [1] : []
    content {
      destination      = aws_cloudwatch_log_group.engine_log[0].name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "engine-log"
    }
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}
