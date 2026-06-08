# ---------------------------------------------------------------------------------------------------------------------
# Remote-Access VPN — Network Account
# ---------------------------------------------------------------------------------------------------------------------
# A management / remote-access VPN host that runs in the Network account and
# joins the TGW estate (ADR-0013). Ported and genericised from the infra
# source-of-truth `modules/pritunl-vpn` (infra ADR-012). The default VPN
# software is Pritunl, but the module is product-neutral — the only public
# surface is internet -> NLB on the VPN data port.
#
# Resources:
#   - IAM instance profile (SSM + CloudWatch agent + scoped Secrets Manager/KMS/S3)
#   - Security groups (NLB edge attached to the NLB; instance SG references the
#     NLB SG for the data-plane ingress — no 0.0.0.0/0 on the host)
#   - EIP + public NLB (target_type=ip) + TCP_UDP target group/listener on the
#     data port (one listener serves both UDP and TCP fallback)
#   - EC2 instance (AL2023 x86_64 via SSM param; IMDSv2; source_dest_check=false)
#   - Root EBS (KMS) + dedicated data EBS (KMS) for the VPN datastore
#   - EC2 auto-recovery alarm + NetworkOut anomaly-detection egress alarm
#   - DLM EBS snapshot lifecycle policy
#   - VPC flow logs + app logs -> CloudWatch log groups (KMS)
#   - Secrets Manager secret shells (values injected out-of-band)
#
# Security model (ADR-0013 Layer 2 — security groups):
#   - The data-plane source is the NLB SG (target_type=ip). The instance SG
#     references the NLB SG; there is no 0.0.0.0/0 ingress on the host.
#   - No public UI, no SSH (SSM Session Manager only).
#   - VPN routed egress is an explicit per-CIDR allow-list (var.reachable_cidrs)
#     that must agree with the TGW route tables in the inter-vpc-security module.
#
# ADR-0013 | trust model: ops / standard VPN sub-pools (see variables.tf).
# ---------------------------------------------------------------------------------------------------------------------

data "aws_region" "current" {}

# Latest Amazon Linux 2023 x86_64 AMI via the SSM public parameter. Avoids a
# hardcoded AMI ID and always resolves to the latest AL2023 kernel default.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ─── IAM — instance role ──────────────────────────────────────────────────────

resource "aws_iam_role" "vpn" {
  name        = "${var.name}-vpn-role"
  description = "Instance role for the remote-access VPN host. Grants SSM, CloudWatch agent, and scoped Secrets Manager / KMS / S3 access."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name}-vpn-role" })
}

# SSM managed instance core — enables Session Manager (replaces SSH).
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.vpn.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent — app-log + metrics publishing.
resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.vpn.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Scoped inline policy: Secrets Manager (prefix-only) + KMS decrypt + S3 backup.
resource "aws_iam_role_policy" "vpn_secrets" {
  name = "${var.name}-vpn-secrets-policy"
  role = aws_iam_role.vpn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Scoped to this deployment's secret prefix only (least privilege).
        Resource = "${var.secrets_arn_prefix}/*"
      },
      {
        Sid    = "KmsDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      },
      {
        Sid    = "S3BackupWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.backup_s3_bucket}",
          "arn:aws:s3:::${var.backup_s3_bucket}/${var.name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "vpn" {
  name = "${var.name}-vpn-profile"
  role = aws_iam_role.vpn.name

  tags = merge(var.tags, { Name = "${var.name}-vpn-profile" })
}

# ─── Security groups ──────────────────────────────────────────────────────────

# NLB security group — world-facing UDP/TCP edge (the only public surface).
resource "aws_security_group" "nlb" {
  name        = "${var.name}-vpn-nlb-sg"
  description = "VPN NLB edge SG. Allows internet UDP/TCP ${var.vpn_data_port} for the VPN data plane."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-vpn-nlb-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "nlb_vpn_udp" {
  security_group_id = aws_security_group.nlb.id
  description       = "VPN data plane UDP ${var.vpn_data_port} from internet to NLB"
  ip_protocol       = "udp"
  from_port         = var.vpn_data_port
  to_port           = var.vpn_data_port
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.tags, { Name = "${var.name}-vpn-nlb-udp" })
}

resource "aws_vpc_security_group_ingress_rule" "nlb_vpn_tcp" {
  security_group_id = aws_security_group.nlb.id
  description       = "VPN data plane fallback TCP ${var.vpn_data_port} from internet to NLB"
  ip_protocol       = "tcp"
  from_port         = var.vpn_data_port
  to_port           = var.vpn_data_port
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.tags, { Name = "${var.name}-vpn-nlb-tcp" })
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_instance" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "NLB forwarding traffic to the VPN instance SG"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.instance.id

  tags = merge(var.tags, { Name = "${var.name}-vpn-nlb-egress" })
}

# ─── Instance security group (ADR-0013 Layer 2) ───────────────────────────────
# The NLB target group uses target_type=ip. Referencing the NLB SG here is more
# precise than CIDRs and keeps the host with no 0.0.0.0/0 ingress.
resource "aws_security_group" "instance" {
  name        = "${var.name}-vpn-sg"
  description = "VPN instance SG. Data-plane ingress from the NLB SG only. No SSH (SSM only)."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-vpn-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "instance_vpn_udp" {
  security_group_id            = aws_security_group.instance.id
  description                  = "VPN data plane UDP ${var.vpn_data_port} from NLB SG"
  ip_protocol                  = "udp"
  from_port                    = var.vpn_data_port
  to_port                      = var.vpn_data_port
  referenced_security_group_id = aws_security_group.nlb.id

  tags = merge(var.tags, { Name = "${var.name}-vpn-instance-udp" })
}

resource "aws_vpc_security_group_ingress_rule" "instance_vpn_tcp" {
  security_group_id            = aws_security_group.instance.id
  description                  = "VPN data plane TCP ${var.vpn_data_port} from NLB SG"
  ip_protocol                  = "tcp"
  from_port                    = var.vpn_data_port
  to_port                      = var.vpn_data_port
  referenced_security_group_id = aws_security_group.nlb.id

  tags = merge(var.tags, { Name = "${var.name}-vpn-instance-tcp" })
}

# NLB health check on the UI port (distinct from the data port so the TCP probe
# does not conflict with active VPN sessions).
resource "aws_vpc_security_group_ingress_rule" "instance_health_check" {
  security_group_id            = aws_security_group.instance.id
  description                  = "NLB health check TCP ${var.vpn_ui_port} from NLB SG"
  ip_protocol                  = "tcp"
  from_port                    = var.vpn_ui_port
  to_port                      = var.vpn_ui_port
  referenced_security_group_id = aws_security_group.nlb.id

  tags = merge(var.tags, { Name = "${var.name}-vpn-instance-health" })
}

# Web UI from the VPN client pool only (TGW-internal; no public UI).
resource "aws_vpc_security_group_ingress_rule" "instance_ui_vpn_clients" {
  security_group_id = aws_security_group.instance.id
  description       = "VPN web UI TCP ${var.vpn_ui_port} from the VPN client pool (TGW-internal; no public access)"
  ip_protocol       = "tcp"
  from_port         = var.vpn_ui_port
  to_port           = var.vpn_ui_port
  cidr_ipv4         = var.vpn_client_cidr

  tags = merge(var.tags, { Name = "${var.name}-vpn-instance-ui" })
}

# ─── Egress — split control-plane vs. routed spoke ────────────────────────────
# Control-plane HTTPS (SSM, KMS, SecretsManager, S3, CloudWatch) is served by
# VPC endpoints. Follow-up (ADR-0013 design-target): scope this rule to the VPC
# CIDR / endpoint prefix-lists once all endpoints are confirmed, removing the
# broad internet fallback.
resource "aws_vpc_security_group_egress_rule" "instance_ctrl_plane_https" {
  security_group_id = aws_security_group.instance.id
  description       = "Control-plane HTTPS egress for SSM, KMS, SecretsManager, S3, CloudWatch via VPC endpoints. Restrict to VPC CIDR once endpoints confirmed."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.tags, { Name = "${var.name}-vpn-instance-ctrl-https" })
}

# Local single-node datastore (loopback only).
resource "aws_vpc_security_group_egress_rule" "instance_datastore_egress" {
  security_group_id = aws_security_group.instance.id
  description       = "VPN datastore TCP ${var.datastore_port} local single-node on the same instance (loopback)"
  ip_protocol       = "tcp"
  from_port         = var.datastore_port
  to_port           = var.datastore_port
  cidr_ipv4         = "127.0.0.1/32"

  tags = merge(var.tags, { Name = "${var.name}-vpn-instance-datastore" })
}

# Routed VPN egress — one rule per permitted spoke/legacy CIDR (ADR-0013
# allow-list). source_dest_check=false lets the instance forward on behalf of
# VPN clients. These CIDRs must agree with the TGW route tables.
resource "aws_vpc_security_group_egress_rule" "instance_spoke_egress" {
  for_each = toset(var.reachable_cidrs)

  security_group_id = aws_security_group.instance.id
  description       = "VPN routed egress to permitted spoke or legacy CIDR ${each.value} (ADR-0013 allow-list)"
  ip_protocol       = "-1"
  cidr_ipv4         = each.value

  tags = merge(var.tags, { Name = "${var.name}-vpn-egress-${replace(each.value, "/", "-")}" })
}

# ─── EIP + NLB ────────────────────────────────────────────────────────────────

resource "aws_eip" "nlb" {
  domain = "vpc"

  # Prevent accidental EIP deletion — this is the stable VPN endpoint IP.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-vpn-nlb-eip" })
}

# Public NLB with the static EIP via subnet_mapping and the NLB SG attached.
# The NLB must be public to accept VPN connections from the internet.
resource "aws_lb" "vpn" {
  name               = "${var.name}-vpn-nlb"
  load_balancer_type = "network"
  internal           = false
  security_groups    = [aws_security_group.nlb.id]

  subnet_mapping {
    subnet_id     = var.public_subnet_ids[0]
    allocation_id = aws_eip.nlb.id
  }

  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, { Name = "${var.name}-vpn-nlb" })
}

# ─── Target group + listener (target_type=ip, TCP_UDP) ────────────────────────
# A single TCP_UDP target group + listener serves both the UDP data plane and
# the TCP fallback on one port (an NLB cannot have separate TCP and UDP
# listeners on the same port). name_prefix keeps names unique across deploys
# (AWS limits the TG name_prefix to 6 chars; the env is carried in the Name tag).
resource "aws_lb_target_group" "vpn_data" {
  name_prefix     = "ravpn"
  port            = var.vpn_data_port
  protocol        = "TCP_UDP"
  vpc_id          = var.vpc_id
  target_type     = "ip"
  ip_address_type = "ipv4"

  preserve_client_ip = true

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = var.vpn_ui_port
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(var.tags, { Name = "${var.name}-vpn-tg-data" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "vpn_data" {
  load_balancer_arn = aws_lb.vpn.arn
  port              = var.vpn_data_port
  protocol          = "TCP_UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vpn_data.arn
  }

  tags = merge(var.tags, { Name = "${var.name}-vpn-listener-data" })
}

# Register the instance private IP (target_type=ip requires an IP, not an ID).
resource "aws_lb_target_group_attachment" "vpn_data" {
  target_group_arn  = aws_lb_target_group.vpn_data.arn
  target_id         = aws_instance.vpn.private_ip
  port              = var.vpn_data_port
  availability_zone = aws_instance.vpn.availability_zone
}

# ─── EC2 instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "vpn" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.vpn.name

  # VPN router mode: the instance forwards packets on behalf of VPN clients.
  source_dest_check = false

  # IMDSv2 required; hop_limit=1 prevents SSRF lateral movement.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true

    tags = merge(var.tags, { Name = "${var.name}-vpn-root" })
  }

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    name             = var.name
    aws_region       = data.aws_region.current.id
    secrets_prefix   = var.secrets_path_prefix
    backup_s3_bucket = var.backup_s3_bucket
    datastore_device = "/dev/xvdf"
    datastore_mount  = "/var/lib/mongodb"
    datastore_port   = var.datastore_port
    vpn_ui_port      = var.vpn_ui_port
  })

  tags = merge(var.tags, { Name = "${var.name}-vpn" })

  lifecycle {
    # Prevent replacement from AMI / user_data drift; update via a new launch.
    ignore_changes = [ami, user_data]
  }
}

# Dedicated EBS volume for the VPN datastore — separate from root for isolated snapshots.
resource "aws_ebs_volume" "datastore" {
  availability_zone = aws_instance.vpn.availability_zone
  size              = var.datastore_volume_size_gb
  type              = "gp3"
  encrypted         = true
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = "${var.name}-vpn-datastore" })
}

resource "aws_volume_attachment" "datastore" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.datastore.id
  instance_id  = aws_instance.vpn.id
  force_detach = false
}

# ─── EC2 auto-recovery alarm (ADR-0013 detective controls) ────────────────────

resource "aws_cloudwatch_metric_alarm" "ec2_auto_recovery" {
  alarm_name          = "${var.name}-vpn-auto-recovery"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed_System"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "VPN host EC2 system status check failed triggers auto-recovery"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.vpn.id
  }

  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.id}:ec2:recover",
    var.alert_sns_topic_arn
  ]

  ok_actions = [var.alert_sns_topic_arn]

  tags = merge(var.tags, { Name = "${var.name}-vpn-auto-recovery" })
}

# Anomaly-detection egress alarm — adapts to the actual traffic baseline rather
# than a fixed threshold. Catches sudden NetworkOut spikes (possible exfil)
# without false positives from normal VPN load growth.
resource "aws_cloudwatch_metric_alarm" "high_egress_anomaly" {
  alarm_name          = "${var.name}-vpn-egress-anomaly"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 3
  threshold_metric_id = "e1"
  alarm_description   = "VPN host NetworkOut exceeds the anomaly-detection upper band, possible exfil or misconfiguration"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "NetworkOut"
      namespace   = "AWS/EC2"
      period      = 300
      stat        = "Average"

      dimensions = {
        InstanceId = aws_instance.vpn.id
      }
    }
  }

  metric_query {
    id          = "e1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 3)"
    label       = "NetworkOut expected"
    return_data = true
  }

  alarm_actions = [var.alert_sns_topic_arn]
  ok_actions    = [var.alert_sns_topic_arn]

  tags = merge(var.tags, { Name = "${var.name}-vpn-egress-anomaly" })
}

# ─── DLM EBS snapshot lifecycle ───────────────────────────────────────────────

resource "aws_iam_role" "dlm" {
  name        = "${var.name}-vpn-dlm-role"
  description = "IAM role for the DLM EBS snapshot lifecycle policy for the VPN volumes."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dlm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name}-vpn-dlm-role" })
}

resource "aws_iam_role_policy_attachment" "dlm_lifecycle" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "vpn" {
  description        = "Daily EBS snapshots for the VPN root and datastore volumes ${var.dlm_snapshot_retain_days} day retention"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "daily-${var.dlm_snapshot_retain_days}d"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["02:00"]
      }

      retain_rule {
        count = var.dlm_snapshot_retain_days
      }

      copy_tags = true
    }

    target_tags = {
      Name   = "${var.name}-vpn"
      Backup = "remote-access-vpn"
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-vpn-dlm" })
}

# Tag volumes for DLM targeting.
resource "aws_ec2_tag" "root_backup_tag" {
  resource_id = aws_instance.vpn.root_block_device[0].volume_id
  key         = "Backup"
  value       = "remote-access-vpn"
}

resource "aws_ec2_tag" "datastore_backup_tag" {
  resource_id = aws_ebs_volume.datastore.id
  key         = "Backup"
  value       = "remote-access-vpn"
}

# ─── CloudWatch log groups ────────────────────────────────────────────────────

# VPC-level flow logs (all traffic on the network VPC — ADR-0013 detective controls).
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.name}-vpn-flowlogs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = "${var.name}-vpn-flowlogs" })
}

# Application log group — the CloudWatch agent writes VPN/datastore/backup logs here.
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/remote-access-vpn/${var.name}"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = "${var.name}-vpn-applogs" })
}

# ─── VPC flow logs IAM + flow log ─────────────────────────────────────────────

resource "aws_iam_role" "flow_logs" {
  name        = "${var.name}-vpn-flowlogs-role"
  description = "IAM role for VPC flow logs to CloudWatch for the VPN network VPC."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name}-vpn-flowlogs-role" })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.name}-vpn-flowlogs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "vpn_vpc" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-vpn-flowlog" })
}

# ─── Secrets Manager secret shells (values injected out-of-band) ──────────────
# Secret names are constructed from var.secrets_path_prefix so the module is
# reusable. Values are NEVER stored in this repo; operators set them out-of-band.

resource "aws_secretsmanager_secret" "datastore_uri" {
  name        = "${var.secrets_path_prefix}/datastore-uri"
  description = "VPN datastore connection URI (local single-node on the same instance). Set out-of-band."
  kms_key_id  = var.kms_key_arn

  recovery_window_in_days = 7

  tags = merge(var.tags, { Name = "${var.secrets_path_prefix}/datastore-uri" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret" "setup_key" {
  name        = "${var.secrets_path_prefix}/setup-key"
  description = "VPN one-time setup key generated on first boot. Set out-of-band."
  kms_key_id  = var.kms_key_arn

  recovery_window_in_days = 7

  tags = merge(var.tags, { Name = "${var.secrets_path_prefix}/setup-key" })

  lifecycle {
    prevent_destroy = true
  }
}
