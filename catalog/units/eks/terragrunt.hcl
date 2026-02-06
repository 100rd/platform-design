# ---------------------------------------------------------------------------------------------------------------------
# EKS Cluster Configuration — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Reusable unit that provisions a managed Kubernetes cluster with IRSA support and a
# "system" managed node group using the terraform-aws-modules/eks/aws registry module.
#
# CNI: Cilium (deployed separately) — vpc-cni addon is DISABLED by default.
# The cluster is placed in the private subnets of the VPC and tagged for Karpenter discovery.
#
# PCI-DSS Controls:
#   Req 3.4  — Secrets encrypted at rest via KMS CMK (envelope encryption)
#   Req 7.1  — Access limited to authorized personnel via RBAC + access entries
#   Req 7.2  — Access control system enforced via EKS access entries + K8s RBAC
#   Req 8.5  — No shared accounts (SSO roles map individual users to K8s groups)
#   Req 10.2 — All control plane log types enabled (api, audit, authenticator, controllerManager, scheduler)
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

  cluster_name = "${local.environment}-${local.aws_region}-platform"

  # ---------------------------------------------------------------------------
  # SSO Role ARNs — constructed from account ID and SSO permission set names.
  # These are the IAM roles created by AWS IAM Identity Center (SSO).
  # Pattern: arn:aws:iam::<account_id>:role/aws-reserved/sso.amazonaws.com/<region>/AWSReservedSSO_<PermissionSetName>_*
  # We use the role path prefix so access entries match any SSO role instance.
  # ---------------------------------------------------------------------------
  sso_role_prefix = "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: VPC
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
# DEPENDENCY: KMS — PCI-DSS Req 3.4 (secrets encryption)
# ---------------------------------------------------------------------------------------------------------------------

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      eks-secrets = "arn:aws:kms:eu-west-1:000000000000:key/mock-eks-secrets-key"
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

  # Endpoint access
  # Dev environments allow public access for developer convenience; staging/prod are private only.
  cluster_endpoint_public_access  = local.account_vars.locals.eks_public_access
  cluster_endpoint_private_access = true

  # IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # ---------------------------------------------------------------------------
  # Secrets Encryption — PCI-DSS Req 3.4
  # Uses the eks-secrets KMS CMK from the kms catalog unit.
  # ---------------------------------------------------------------------------
  cluster_encryption_config = {
    provider_key_arn = dependency.kms.outputs.key_arns["eks-secrets"]
    resources        = ["secrets"]
  }

  # ---------------------------------------------------------------------------
  # Control Plane Logging — PCI-DSS Req 10.2
  # All five log types enabled for comprehensive audit trail.
  # ---------------------------------------------------------------------------
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # ---------------------------------------------------------------------------
  # Cluster Addons
  # IMPORTANT: vpc-cni is DISABLED because we use Cilium CNI instead.
  # Cilium is deployed as a separate unit after EKS cluster creation.
  # ---------------------------------------------------------------------------
  cluster_addons = {
    coredns = {
      most_recent = true
      # CoreDNS needs Cilium to be ready before pods can communicate
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
    # vpc-cni is intentionally NOT included — Cilium is used instead
  }

  # ---------------------------------------------------------------------------
  # Node security group tags for Karpenter auto-discovery
  # ---------------------------------------------------------------------------
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  # ---------------------------------------------------------------------------
  # Managed node groups
  # The "system" group runs cluster-critical workloads (CoreDNS, Cilium, Karpenter)
  # Uses Bottlerocket AMI for native Cilium support.
  # Instance types and scaling parameters are defined per environment in account.hcl.
  # ---------------------------------------------------------------------------
  eks_managed_node_groups = {
    system = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = local.account_vars.locals.eks_instance_types
      min_size       = local.account_vars.locals.eks_min_size
      max_size       = local.account_vars.locals.eks_max_size
      desired_size   = local.account_vars.locals.eks_desired_size

      # Bottlerocket-specific settings
      platform = "bottlerocket"

      # Taints to prevent workloads until Cilium is ready
      taints = {
        cilium = {
          key    = "node.cilium.io/agent-not-ready"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Cluster Creator Admin — bootstrap access
  # NOTE: Disable this after initial cluster setup and rely solely on
  # access_entries below for ongoing access. Keeping it enabled during
  # bootstrap allows the deploying principal to apply RBAC manifests.
  # ---------------------------------------------------------------------------
  enable_cluster_creator_admin_permissions = true

  # ---------------------------------------------------------------------------
  # EKS Access Entries — PCI-DSS Req 7.1, 7.2, 8.5
  #
  # Maps AWS IAM Identity Center (SSO) roles to Kubernetes groups.
  # K8s RBAC ClusterRoles/RoleBindings (kubernetes/rbac/) define what each
  # group can do. SSO ensures individual user authentication (Req 8.5).
  #
  # Role mapping:
  #   PlatformEngineer SSO -> platform-operators (full workload management)
  #   ReadOnlyAccess SSO   -> platform-viewers   (read-only cluster access)
  #   DeveloperAccess SSO  -> platform-viewers   (read-only — devs observe, not operate)
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
