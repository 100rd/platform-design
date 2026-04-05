# ---------------------------------------------------------------------------------------------------------------------
# CloudWatch Alarms + SNS Topic
# ---------------------------------------------------------------------------------------------------------------------
# Creates a KMS-encrypted SNS topic and CloudWatch alarms covering:
#   - Billing threshold (management account, us-east-1 only — requires enable_billing_alarm = true)
#   - EKS API server errors
#   - EKS node not-ready count
#   - EC2 high CPU utilization
#   - EC2 high memory utilization (requires CloudWatch agent)
#   - ALB 5xx errors (optional — requires alb_arn_suffix)
#   - ALB unhealthy host count (optional — requires alb_arn_suffix)
#   - Terraform state S3 bucket size
# ---------------------------------------------------------------------------------------------------------------------

# ─── SNS Topic ────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name              = "${var.project}-${var.environment}-alerts"
  kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null

  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ─── Billing Alarm (management / us-east-1 only) ──────────────────────────────
# AWS billing metrics are only published in us-east-1. Set enable_billing_alarm = true
# in the management account only.

resource "aws_cloudwatch_metric_alarm" "billing" {
  count = var.enable_billing_alarm ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-billing-threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 86400 # 24 h — billing metrics are daily
  statistic           = "Maximum"
  threshold           = var.billing_threshold_usd
  alarm_description   = "Estimated AWS charges exceeded $${var.billing_threshold_usd}. Investigate in Cost Explorer."
  treat_missing_data  = "notBreaching"

  dimensions = {
    Currency = "USD"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ─── EKS: API Server Errors ───────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "eks_api_server_errors" {
  alarm_name          = "${var.project}-${var.environment}-eks-api-server-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "APIServerRequestErrors"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "EKS API server errors exceeded 10 in 5 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = "${var.project}-${var.environment}"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ─── EKS: Node Not Ready ──────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "eks_node_not_ready" {
  alarm_name          = "${var.project}-${var.environment}-eks-node-not-ready"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "cluster_failed_node_count"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "One or more EKS nodes are in a not-ready state"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = "${var.project}-${var.environment}"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ─── EC2: High CPU ────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project}-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300 # 5 min x 2 periods = 10 min sustained
  statistic           = "Average"
  threshold           = var.cpu_threshold_percent
  alarm_description   = "EC2 average CPU utilization exceeded ${var.cpu_threshold_percent}% for 10 minutes"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ─── EC2: High Memory (requires CloudWatch agent) ─────────────────────────────

resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "${var.project}-${var.environment}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_threshold_percent
  alarm_description   = "EC2 memory utilization exceeded ${var.memory_threshold_percent}% for 10 minutes (requires CloudWatch agent)"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ─── ALB: 5xx Errors ──────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  count = var.alb_arn_suffix != "" ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  alarm_description   = "ALB target 5xx error count exceeded ${var.alb_5xx_threshold} in 5 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ─── ALB: Unhealthy Host Count ────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = var.alb_arn_suffix != "" ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "ALB has one or more unhealthy targets"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ─── S3: State Bucket Size ────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "s3_state_bucket_size" {
  alarm_name          = "${var.project}-${var.environment}-s3-state-bucket-size"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = 86400 # daily metric
  statistic           = "Average"
  threshold           = 10737418240 # 10 GB in bytes
  alarm_description   = "Terraform state S3 bucket exceeds 10 GB — possible state bloat"
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName  = "tfstate-${var.environment}-${var.state_bucket_region}"
    StorageType = "StandardStorage"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}
