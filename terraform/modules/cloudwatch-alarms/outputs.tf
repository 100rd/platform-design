output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic. Use this as the target for additional alarm actions."
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS alerts topic"
  value       = aws_sns_topic.alerts.name
}

output "alarm_arns" {
  description = "Map of alarm name to ARN for all created alarms"
  value = merge(
    {
      eks_api_server_errors = aws_cloudwatch_metric_alarm.eks_api_server_errors.arn
      eks_node_not_ready    = aws_cloudwatch_metric_alarm.eks_node_not_ready.arn
      high_cpu              = aws_cloudwatch_metric_alarm.high_cpu.arn
      high_memory           = aws_cloudwatch_metric_alarm.high_memory.arn
      s3_state_bucket_size  = aws_cloudwatch_metric_alarm.s3_state_bucket_size.arn
    },
    var.enable_billing_alarm ? { billing = aws_cloudwatch_metric_alarm.billing[0].arn } : {},
    var.alb_arn_suffix != "" ? {
      alb_5xx_errors      = aws_cloudwatch_metric_alarm.alb_5xx_errors[0].arn
      alb_unhealthy_hosts = aws_cloudwatch_metric_alarm.alb_unhealthy_hosts[0].arn
    } : {}
  )
}
