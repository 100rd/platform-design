output "primary_endpoint" {
  description = "Primary endpoint address"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint address"
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Redis port"
  value       = 6379
}

output "connection_url" {
  description = "Redis connection URL"
  value       = "rediss://${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.this.id
}
