mock_provider "aws" {}

variables {
  name     = "test-vpc"
  vpc_cidr = "10.0.0.0/16"
  azs      = ["us-east-1a", "us-east-1b", "us-east-1c"]
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_vpc_with_defaults" {
  command = plan

  assert {
    condition     = module.vpc.name == "test-vpc"
    error_message = "VPC name should be 'test-vpc'"
  }

  assert {
    condition     = module.vpc.cidr == "10.0.0.0/16"
    error_message = "VPC CIDR should be '10.0.0.0/16'"
  }

  assert {
    condition     = module.vpc.enable_nat_gateway == true
    error_message = "NAT Gateway should be enabled"
  }

  assert {
    condition     = module.vpc.enable_dns_hostnames == true
    error_message = "DNS hostnames should be enabled"
  }

  assert {
    condition     = module.vpc.enable_dns_support == true
    error_message = "DNS support should be enabled"
  }
}

run "single_nat_gateway_by_default" {
  command = plan

  variables {
    enable_ha_nat = false
  }

  assert {
    condition     = module.vpc.single_nat_gateway == true
    error_message = "Single NAT gateway should be enabled when enable_ha_nat is false"
  }
}

run "ha_nat_gateway_when_enabled" {
  command = plan

  variables {
    enable_ha_nat = true
  }

  assert {
    condition     = module.vpc.single_nat_gateway == false
    error_message = "Single NAT gateway should be disabled when enable_ha_nat is true"
  }

  assert {
    condition     = module.vpc.one_nat_gateway_per_az == true
    error_message = "One NAT gateway per AZ should be enabled for HA"
  }
}

run "flow_logs_enabled_by_default" {
  command = plan

  assert {
    condition     = module.vpc.enable_flow_log == true
    error_message = "VPC flow logs should be enabled by default for PCI-DSS compliance"
  }

  assert {
    condition     = module.vpc.flow_log_traffic_type == "ALL"
    error_message = "Flow log traffic type should be ALL"
  }
}

run "flow_log_retention_pci_dss_compliant" {
  command = plan

  assert {
    condition     = module.vpc.flow_log_cloudwatch_log_group_retention_in_days == 365
    error_message = "Flow log retention should be 365 days for PCI-DSS Req 10.7 compliance"
  }
}

run "karpenter_discovery_tags_applied" {
  command = plan

  variables {
    cluster_name = "test-cluster"
  }

  assert {
    condition     = module.vpc.private_subnet_tags["karpenter.sh/discovery"] == "test-cluster"
    error_message = "Private subnets should have karpenter.sh/discovery tag when cluster_name is set"
  }
}

run "public_subnets_tagged_for_elb" {
  command = plan

  assert {
    condition     = module.vpc.public_subnet_tags["kubernetes.io/role/elb"] == "1"
    error_message = "Public subnets should have kubernetes.io/role/elb tag"
  }
}
