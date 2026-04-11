mock_provider "aws" {}

variables {
  name     = "test-redis"
  vpc_id   = "vpc-12345678"
  vpc_cidr = "10.0.0.0/16"
  subnet_ids                 = ["subnet-aaa", "subnet-bbb"]
  allowed_security_group_ids = ["sg-12345"]
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_replication_group" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.description == "Redis cluster for application caching"
    error_message = "Default description should be set"
  }
}

run "security_group_created" {
  command = plan

  assert {
    condition     = aws_security_group.this.name == "test-redis-sg"
    error_message = "Security group name should include module name"
  }
}

run "default_port_6379" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.port == 6379
    error_message = "Default Redis port should be 6379"
  }
}
