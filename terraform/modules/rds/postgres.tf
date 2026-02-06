# ---------------------------------------------------------------------------------------------------------------------
# RDS PostgreSQL Instance with PCI-DSS Controls
# ---------------------------------------------------------------------------------------------------------------------
# PCI-DSS Req 4.1: Encrypt data in transit (rds.force_ssl = 1)
# PCI-DSS Req 3.4: Encrypt data at rest (KMS CMK)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_db_parameter_group" "this" {
  name        = "${var.identifier}-pg17-ssl"
  family      = "postgres17"
  description = "PostgreSQL 17 parameter group with forced SSL (PCI-DSS Req 4.1)"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = var.identifier

  engine               = "postgres"
  engine_version       = "17"
  family               = "postgres17"
  major_engine_version = "17"
  instance_class       = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100

  db_name  = var.db_name
  username = var.username
  password = var.password
  port     = 5432

  # SSL enforcement via custom parameter group (PCI-DSS Req 4.1)
  create_db_parameter_group = false
  parameter_group_name      = aws_db_parameter_group.this.name

  multi_az               = var.multi_az
  db_subnet_group_name   = "dns-failover-subnet-group"
  subnet_ids             = var.subnet_ids
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_window           = "03:00-06:00"
  backup_retention_period = 7
  skip_final_snapshot     = var.environment == "prod" ? false : true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_interval                   = 60

  # Encryption at rest with KMS CMK (PCI-DSS Req 3.4)
  storage_encrypted = true
  kms_key_id        = var.kms_key_id

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
