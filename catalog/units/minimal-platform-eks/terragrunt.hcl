# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform EKS Cluster — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a dedicated EKS cluster for the minimal-platform stack.
#
# Key difference from the standard eks catalog unit:
#   - cluster_name = staging-eu-central-1-minimal-platform (avoids collision with
#     the standard platform cluster staging-eu-central-1-platform in the same account)
#   - Depends on minimal-platform-vpc and minimal-platform-kms
# ---------------------------------------------------------------------------------------------------------------------

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
  # ---------------------------------------------------------------------------
  sso_role_prefix = "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com"
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
  cluster_name    = local.cluster_name
  cluster_version = "1.32"

  # Networking
  vpc_id                   = dependency.vpc.outputs.vpc_id
  subnet_ids               = dependency.vpc.outputs.private_subnets
  control_plane_subnet_ids = dependency.vpc.outputs.private_subnets

  # Endpoint access — follows account.hcl setting (private-only for staging)
  cluster_endpoint_public_access  = local.account_vars.locals.eks_public_access
  cluster_endpoint_private_access = true

  # IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # ---------------------------------------------------------------------------
  # Secrets Encryption — PCI-DSS Req 3.4
  # ---------------------------------------------------------------------------
  cluster_encryption_config = {
    provider_key_arn = dependency.kms.outputs.key_arns["eks-secrets"]
    resources        = ["secrets"]
  }

  # ---------------------------------------------------------------------------
  # Control Plane Logging — PCI-DSS Req 10.2
  # ---------------------------------------------------------------------------
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # ---------------------------------------------------------------------------
  # Cluster Addons — vpc-cni intentionally omitted (Cilium CNI used instead)
  # ---------------------------------------------------------------------------
  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        tolerations = [
          {
            key      = "node.cilium.io/agent-not-ready"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]
      })
    }
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
  # Managed node groups — sizes from account.hcl (shared with platform)
  # ---------------------------------------------------------------------------
  eks_managed_node_groups = {
    system = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = local.account_vars.locals.eks_instance_types
      min_size       = local.account_vars.locals.eks_min_size
      max_size       = local.account_vars.locals.eks_max_size
      desired_size   = local.account_vars.locals.eks_desired_size

      platform = "bottlerocket"

      # -----------------------------------------------------------------------
      # EBS root volume encryption — HIGH-2 fix (security review round 2)
      # Explicit per-volume CMK encryption regardless of account-level default.
      # Bottlerocket uses /dev/xvda for the OS root volume.
      # -----------------------------------------------------------------------
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

      taints = {
        cilium = {
          key    = "node.cilium.io/agent-not-ready"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  enable_cluster_creator_admin_permissions = true

  # ---------------------------------------------------------------------------
  # EKS Access Entries — PCI-DSS Req 7.1, 7.2, 8.5
  # ---------------------------------------------------------------------------
  access_entries = {
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

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
