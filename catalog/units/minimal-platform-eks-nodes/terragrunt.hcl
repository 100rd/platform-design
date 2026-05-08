# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform EKS Managed Node Group — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions the managed node group for the minimal-platform EKS cluster.
# Must be deployed AFTER minimal-platform-eks-cluster AND minimal-platform-cilium.
#
# Deploy order:
#   vpc -> kms -> eks-cluster -> cilium -> eks-nodes (this unit)
#
# Why this unit exists separately:
#   Cilium must be running on the cluster (Helm chart applied, operator and
#   DaemonSet manifests present) BEFORE nodes join. When nodes start up they
#   carry the taint node.cilium.io/agent-not-ready=true:NoExecute so that no
#   workloads are scheduled until the Cilium agent on that node removes the taint.
#   This eliminates the CNI chicken-and-egg problem that required manual SG rule
#   intervention in Round 7.
#
# Uses the eks-managed-node-group submodule from terraform-aws-modules/eks/aws
# directly — avoids creating a full EKS cluster just to attach a node group.
#
# Soft dependency on cilium (skip_outputs = true) ensures the Cilium Helm release
# is present in state before the auto-scaling group launches instances. Terragrunt
# enforces apply ordering even when outputs are not consumed.
# ---------------------------------------------------------------------------------------------------------------------

# Include root.hcl to activate remote_state (S3 backend generation) and provider
# generation. Without this block, terragrunt ignores root.hcl entirely — no
# backend.tf is generated and state falls back to local storage, which is lost
# on any cache clean (rm -rf .terragrunt-cache / .terragrunt-stack).
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/eks/aws//modules/eks-managed-node-group?version=21.15.1"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Minimal Platform EKS Cluster (control plane)
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    cluster_name                       = "sandbox-eu-west-1-minimal-platform"
    cluster_version                    = "1.32"
    cluster_endpoint                   = "https://XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX.gr7.eu-west-1.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jYS1kYXRh"
    cluster_service_cidr               = "172.20.0.0/16"
    cluster_ip_family                  = "ipv4"
    cluster_primary_security_group_id  = "sg-MOCKMOCKMOCKMOCK01"
    node_security_group_id             = "sg-MOCKMOCKMOCKMOCK02"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# SOFT DEPENDENCY: Minimal Platform Cilium
# Ensures the Cilium operator and DaemonSet manifests exist in state before
# the node group auto-scaling group launches EC2 instances.
# skip_outputs = true because we do not consume any cilium outputs here.
# ---------------------------------------------------------------------------------------------------------------------

dependency "cilium" {
  config_path  = "../cilium"
  skip_outputs = true
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Minimal Platform VPC (subnet IDs for node placement)
# ---------------------------------------------------------------------------------------------------------------------

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    private_subnets = ["subnet-00000000000000000", "subnet-11111111111111111", "subnet-22222222222222222"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Minimal Platform KMS (EBS encryption key)
# ---------------------------------------------------------------------------------------------------------------------

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      ebs = "arn:aws:kms:eu-west-1:000000000000:key/mock-ebs-key"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name = "system"

  # Cluster identity — wires this node group to the control plane
  cluster_name    = dependency.eks_cluster.outputs.cluster_name
  cluster_version = dependency.eks_cluster.outputs.cluster_version

  # The submodule variable is cluster_auth_base64 — this is the same value as
  # cluster_certificate_authority_data (already base64 encoded by EKS).
  cluster_endpoint    = dependency.eks_cluster.outputs.cluster_endpoint
  cluster_auth_base64 = dependency.eks_cluster.outputs.cluster_certificate_authority_data

  cluster_service_cidr              = dependency.eks_cluster.outputs.cluster_service_cidr
  cluster_primary_security_group_id = dependency.eks_cluster.outputs.cluster_primary_security_group_id

  # Node placement
  subnet_ids             = dependency.vpc.outputs.private_subnets
  vpc_security_group_ids = [dependency.eks_cluster.outputs.node_security_group_id]

  # AMI and sizing
  ami_type       = "BOTTLEROCKET_x86_64"
  instance_types = local.account_vars.locals.eks_instance_types
  min_size       = local.account_vars.locals.eks_min_size
  max_size       = local.account_vars.locals.eks_max_size
  desired_size   = local.account_vars.locals.eks_desired_size

  # -------------------------------------------------------------------------
  # EBS root volume encryption — HIGH-2 fix (security review round 2)
  # Bottlerocket uses /dev/xvda for the OS root volume.
  # -------------------------------------------------------------------------
  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 20
        volume_type           = "gp3"
        encrypted             = true
        kms_key_id            = dependency.kms.outputs.key_arns["ebs"]
        delete_on_termination = true
      }
    }
  }

  # -------------------------------------------------------------------------
  # Startup taint — prevents workload scheduling until Cilium agent is ready.
  #
  # Effect: NO_EXECUTE (not NO_SCHEDULE) so kubelet evicts pods that were
  # speculatively scheduled before the Cilium agent removed the taint.
  # The Cilium agent DaemonSet tolerates node.cilium.io/agent-not-ready via
  # its default {operator: Exists} toleration and removes this taint once
  # its ENI IPAM is healthy.
  # -------------------------------------------------------------------------
  taints = {
    cilium = {
      key    = "node.cilium.io/agent-not-ready"
      value  = "true"
      effect = "NO_EXECUTE"
    }
  }

  # Disable name_prefix to keep IAM role name deterministic and avoid
  # exceeding the 38-char AWS IAM name_prefix limit.
  iam_role_use_name_prefix = false

  tags = local.account_vars.locals.default_tags
}
