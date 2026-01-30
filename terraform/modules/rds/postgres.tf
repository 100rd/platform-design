module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = var.identifier

  engine               = "postgres"
  engine_version       = "15"
  family               = "postgres15" # DB parameter group
  major_engine_version = "15"         # DB option group
  instance_class       = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100

  db_name  = var.db_name
  username = var.username
  password = var.password
  port     = 5432

  multi_az               = var.multi_az
  db_subnet_group_name   = "dns-failover-subnet-group" # Will be created by module if subnets provided
  subnet_ids             = var.subnet_ids
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_window           = "03:00-06:00"
  backup_retention_period = 7
  skip_final_snapshot       = var.environment == "prod" ? false : true
  final_snapshot_identifier = var.environment == "prod" ? "${var.identifier}-final-snapshot" : null

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_interval                   = 60

  tags = var.tags
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.identifier}-sg"
  description = "PostgreSQL security group"
  vpc_id      = var.vpc_id

  # Ingress from allowed SGs (e.g. EKS nodes)
  ingress_with_source_security_group_id = [
    for sg_id in var.allowed_security_group_ids : {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      description              = "PostgreSQL access from EKS"
      source_security_group_id = sg_id
    }
  ]

  tags = var.tags
}
