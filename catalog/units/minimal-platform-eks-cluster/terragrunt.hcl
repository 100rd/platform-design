# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform EKS Cluster (control plane only) — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions the EKS control plane, IAM roles, OIDC provider, KMS encryption,
# cluster addons, and shared security groups for the minimal-platform stack.
#
# IMPORTANT: This unit deliberately creates NO managed node groups (eks_managed_node_groups = {}).
# The node group lives in a separate catalog unit (minimal-platform-eks-nodes) which
# depends on this unit AND on minimal-platform-cilium.
#
# Deploy order:
#   vpc -> kms -> eks-cluster -> cilium -> eks-nodes
#
# This split breaks the Cilium chicken-and-egg cycle:
#   - Cilium operator/DaemonSet manifests are installed BEFORE nodes come up
#   - Nodes start with taint node.cilium.io/agent-not-ready=true:NoExecute
#   - Cilium agent removes the taint once it initialises on each node
#   - Nodes become Ready without any manual CNI intervention
#
# All cluster-level outputs (cluster_endpoint, cluster_name, oidc_provider_arn,
# cluster_certificate_authority_data, cluster_service_cidr, cluster_ip_family,
# cluster_security_group_id, node_security_group_id) are available immediately
# after this unit applies — no nodes required.
#
# Derived from minimal-platform-eks with the managed node group block removed.
# Input renames for terraform-aws-modules/eks/aws v21.x applied.
# ---------------------------------------------------------------------------------------------------------------------

# Include root.hcl to activate remote_state (S3 backend generation) and provider
# generation. Without this block, terragrunt ignores root.hcl entirely — no
# backend.tf is generated and state falls back to local storage, which is lost
# on any cache clean (rm -rf .terragrunt-cache / .terragrunt-stack).
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/eks/aws?version=21.15.1"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  cluster_name = "${local.environment}-${local.aws_region}-minimal-platform"

  # ---------------------------------------------------------------------------
  # SSO Role ARNs — constructed from account ID and SSO permission set names.
  # Used as the default access_entries for org accounts with AWS SSO.
  # ---------------------------------------------------------------------------
  sso_role_prefix = "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com"

  default_access_entries = {
    platform_engineer = {
      principal_arn     = "${local.sso_role_prefix}/AWSReservedSSO_PlatformEngineer_*"
      kubernetes_groups = ["platform-operators"]
      type              = "STANDARD"
    }

    readonly_access = {
      principal_arn     = "${local.sso_role_prefix}/AWSReservedSSO_ReadOnlyAccess_*"
      kubernetes_groups = ["platform-viewers"]
      type              = "STANDARD"
    }

    developer_access = {
      principal_arn     = "${local.sso_role_prefix}/AWSReservedSSO_DeveloperAccess_*"
      kubernetes_groups = ["platform-viewers"]
      type              = "STANDARD"
    }
  }

  # ---------------------------------------------------------------------------
  # Access entries — configurable per account.
  #
  # Org accounts (staging, prod, dev): default SSO role entries from local.
  # Sandbox: empty map from account.hcl; cluster access via creator permissions.
  #
  # Backward-compatible: if account.hcl does not define eks_access_entries,
  # try() falls back to the SSO role defaults.
  # ---------------------------------------------------------------------------
  access_entries = try(local.account_vars.locals.eks_access_entries, local.default_access_entries)

  # ---------------------------------------------------------------------------
  # Public access CIDRs — configurable per account.
  #
  # Default: open to the world (0.0.0.0/0) for accounts where public access is
  # already gated by eks_public_access = false in account.hcl (staging/prod).
  # Sandbox: locked to user's IP via eks_public_access_cidrs in account.hcl.
  # ---------------------------------------------------------------------------
  public_access_cidrs = try(local.account_vars.locals.eks_public_access_cidrs, ["0.0.0.0/0"])
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Minimal Platform VPC
# ---------------------------------------------------------------------------------------------------------------------

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id          = "vpc-00000000000000000"
    private_subnets = ["subnet-00000000000000000", "subnet-11111111111111111", "subnet-22222222222222222"]
    intra_subnets   = ["subnet-33333333333333333", "subnet-44444444444444444", "subnet-55555555555555555"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Minimal Platform KMS — PCI-DSS Req 3.4 (secrets encryption)
# ---------------------------------------------------------------------------------------------------------------------

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      eks-secrets = "arn:aws:kms:eu-central-1:000000000000:key/mock-eks-secrets-key"
      ebs         = "arn:aws:kms:eu-central-1:000000000000:key/mock-ebs-key"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  # v21: cluster_name -> name
  name = local.cluster_name
  # v21: cluster_version -> kubernetes_version
  kubernetes_version = "1.32"

  # Networking
  vpc_id                   = dependency.vpc.outputs.vpc_id
  subnet_ids               = dependency.vpc.outputs.private_subnets
  control_plane_subnet_ids = dependency.vpc.outputs.private_subnets

  # Endpoint access — follows account.hcl settings
  # v21: cluster_endpoint_public_access       -> endpoint_public_access
  # v21: cluster_endpoint_private_access      -> endpoint_private_access
  # v21: cluster_endpoint_public_access_cidrs -> endpoint_public_access_cidrs
  endpoint_public_access       = local.account_vars.locals.eks_public_access
  endpoint_private_access      = true
  endpoint_public_access_cidrs = local.public_access_cidrs

  # IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # Disable name_prefix for IAM role: cluster name (e.g. sandbox-eu-central-1-minimal-platform)
  # is 40 chars; appending "-cluster-" yields 50 which exceeds the 38-char name_prefix AWS limit.
  # Using exact name is safe for a single cluster per environment.
  iam_role_use_name_prefix = false

  # ---------------------------------------------------------------------------
  # Secrets Encryption — PCI-DSS Req 3.4
  # v21: cluster_encryption_config -> encryption_config
  # ---------------------------------------------------------------------------
  encryption_config = {
    provider_key_arn = dependency.kms.outputs.key_arns["eks-secrets"]
    resources        = ["secrets"]
  }

  # ---------------------------------------------------------------------------
  # Control Plane Logging — PCI-DSS Req 10.2
  # v21: cluster_enabled_log_types -> enabled_log_types
  # ---------------------------------------------------------------------------
  enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # ---------------------------------------------------------------------------
  # Cluster Addons — DaemonSet-based addons only (kube-proxy, eks-pod-identity-agent).
  # vpc-cni intentionally omitted (Cilium CNI used instead).
  # CoreDNS (Deployment) is deferred to a post-nodes step because EKS waits
  # for addon ACTIVE status which requires running pods → blocks apply forever
  # in a no-nodes cluster. CoreDNS will be installed via eks-nodes unit's
  # post_apply or as a separate addon unit after nodes exist.
  # v21: cluster_addons -> addons
  # ---------------------------------------------------------------------------
  addons = {
    kube-proxy = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  # ---------------------------------------------------------------------------
  # Node security group tags for Karpenter auto-discovery
  # ---------------------------------------------------------------------------
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  # ---------------------------------------------------------------------------
  # Additional node security group rules for Cilium ENI mode (Fix #8).
  #
  # EKS v21 module default node SG rules cover:
  #   - TCP 443 inbound from cluster SG (API -> nodes)
  #   - TCP 10250 inbound from cluster SG (kubelet)
  #   - TCP/UDP 53 self (CoreDNS)
  #   - TCP 1025-65535 self (ephemeral; recommended rules)
  #   - Egress all (0.0.0.0/0)
  #
  # Gap for Cilium ENI mode: pods get VPC IPs and inherit the node SG.
  # Cross-node pod traffic uses VPC routing — the node SG must permit all
  # inbound protocols from itself. The default covers TCP ephemeral ports
  # but NOT UDP (needed for WireGuard encryption on UDP 51871) or ICMP
  # (needed for path MTU discovery). A single self all-protocol rule fills
  # both gaps.
  #
  # This replaces the manual `aws ec2 authorize-security-group-ingress`
  # workaround that was required during the Round 7 first-apply.
  # ---------------------------------------------------------------------------
  node_security_group_additional_rules = {
    ingress_self_all_cilium_eni = {
      description = "Cilium ENI mode: all protocols self (pod-to-pod across nodes + WireGuard UDP 51871)"
      type        = "ingress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      self        = true
    }
  }

  # ---------------------------------------------------------------------------
  # No managed node groups — nodes live in the separate eks-nodes unit.
  # This allows Cilium to be deployed between cluster creation and node join,
  # breaking the CNI chicken-and-egg problem.
  # ---------------------------------------------------------------------------
  eks_managed_node_groups = {}

  enable_cluster_creator_admin_permissions = true

  # ---------------------------------------------------------------------------
  # EKS Access Entries — configurable per account (PCI-DSS Req 7.1, 7.2, 8.5)
  #
  # Org accounts (staging, prod, dev): default SSO role entries from local.
  # Sandbox: empty map from account.hcl; cluster access via creator permissions.
  # ---------------------------------------------------------------------------
  access_entries = local.access_entries

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
