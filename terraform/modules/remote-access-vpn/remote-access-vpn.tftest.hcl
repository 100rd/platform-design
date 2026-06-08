mock_provider "aws" {}

variables {
  name               = "network-eu-west-1"
  vpc_id             = "vpc-12345"
  private_subnet_ids = ["subnet-aaa", "subnet-bbb"]
  public_subnet_ids  = ["subnet-ccc", "subnet-ddd"]
  kms_key_arn        = "arn:aws:kms:eu-west-1:000000000000:key/00000000-0000-0000-0000-000000000000"
  secrets_arn_prefix = "arn:aws:secretsmanager:eu-west-1:000000000000:secret:org/network/remote-access-vpn"
  backup_s3_bucket   = "org-network-ravpn-backups"

  alert_sns_topic_arn        = "arn:aws:sns:eu-west-1:000000000000:network-alerts"
  enable_deletion_protection = false

  reachable_cidrs = ["10.10.0.0/16"]

  tags = {
    Environment = "network"
    ManagedBy   = "terraform"
  }
}

run "creates_vpn_host_and_nlb" {
  command = plan

  assert {
    condition     = aws_instance.vpn.source_dest_check == false
    error_message = "VPN host must disable source/dest check to forward client traffic"
  }

  assert {
    condition     = aws_lb.vpn.load_balancer_type == "network"
    error_message = "VPN edge must be a Network Load Balancer"
  }

  assert {
    condition     = aws_lb.vpn.internal == false
    error_message = "VPN NLB must be public to accept internet VPN connections"
  }
}

run "nlb_uses_tcp_udp_target_group" {
  command = plan

  assert {
    condition     = aws_lb_target_group.vpn_data.protocol == "TCP_UDP"
    error_message = "A single TCP_UDP target group must serve both UDP and TCP-fallback on the data port"
  }

  assert {
    condition     = aws_lb_target_group.vpn_data.target_type == "ip"
    error_message = "Target group must use target_type=ip so the NLB SG-reference data-plane rule applies"
  }

  assert {
    condition     = aws_lb_listener.vpn_data.protocol == "TCP_UDP"
    error_message = "The data listener must be TCP_UDP on a single port"
  }
}

run "instance_data_plane_ingress_is_sg_reference_not_world" {
  command = plan

  # ADR-0013 Layer 2: the host admits the data plane from the NLB SG, never 0.0.0.0/0.
  assert {
    condition     = aws_vpc_security_group_ingress_rule.instance_vpn_udp.referenced_security_group_id != null
    error_message = "Instance UDP ingress must reference the NLB SG, not a world CIDR"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.instance_vpn_tcp.referenced_security_group_id != null
    error_message = "Instance TCP ingress must reference the NLB SG, not a world CIDR"
  }
}

run "imdsv2_required" {
  command = plan

  assert {
    condition     = aws_instance.vpn.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 (http_tokens=required) must be enforced on the VPN host"
  }
}

run "trust_subpools_are_distinct" {
  command = plan

  assert {
    condition     = var.vpn_ops_subpool_cidr != var.vpn_standard_subpool_cidr
    error_message = "Ops and standard VPN sub-pools must be distinct CIDRs for the trust model"
  }
}
