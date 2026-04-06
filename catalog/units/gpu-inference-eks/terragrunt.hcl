# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference EKS Cluster — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions an EKS 1.35 cluster for GPU inference workloads with self-managed
# GPU node groups, DRA enabled, and custom AMI support.
#
# Key differences from platform/gpu-analysis EKS:
#   - EKS 1.35 (DRA GA support)
#   - Self-managed GPU node groups (p5.48xlarge / p4d.24xlarge)
#   - Private endpoint only
#   - No vpc-cni — Cilium deployed separately
#   - Secrets encryption via KMS
#   - All control plane logging enabled
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

  cluster_name = "${local.environment}-${local.aws_region}-gpu-inference"

  # SSO role ARN prefix for access entries
  sso_role_prefix = "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com"

  # GPU inference cluster configuration from account.hcl
  gpu_inference_config = try(local.account_vars.locals.gpu_inference_config, {})
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: GPU Inference VPC
# ---------------------------------------------------------------------------------------------------------------------

dependency "vpc" {
  config_path = "../gpu-inference-vpc"

  mock_outputs = {
    vpc_id                             = "vpc-00000000000000000"
    private_subnet_ids                 = ["subnet-00000000000000000", "subnet-11111111111111111", "subnet-22222222222222222"]
    intra_subnet_ids                   = ["subnet-33333333333333333", "subnet-44444444444444444", "subnet-55555555555555555"]
    gpu_interconnect_security_group_id = "sg-00000000000000000"
    bgp_gre_security_group_id          = "sg-11111111111111111"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: KMS — Secrets encryption
# ---------------------------------------------------------------------------------------------------------------------

dependency "kms" {
  config_path = "../../platform/kms"

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
  cluster_version = "1.35"

  # Networking
  vpc_id                   = dependency.vpc.outputs.vpc_id
  subnet_ids               = dependency.vpc.outputs.private_subnet_ids
  control_plane_subnet_ids = dependency.vpc.outputs.private_subnet_ids

  # Private endpoint only
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  # IRSA
  enable_irsa = true

  # ---------------------------------------------------------------------------
  # Secrets Encryption via KMS
  # ---------------------------------------------------------------------------
  cluster_encryption_config = {
    provider_key_arn = dependency.kms.outputs.key_arns["eks-secrets"]
    resources        = ["secrets"]
  }

  # ---------------------------------------------------------------------------
  # Control Plane Logging — all components enabled
  # ---------------------------------------------------------------------------
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # ---------------------------------------------------------------------------
  # Cluster Addons (Cilium deployed separately, vpc-cni NOT included)
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
  # Self-managed node groups
  # ---------------------------------------------------------------------------
  self_managed_node_groups = {
    # System node group for cluster-critical workloads (CoreDNS, Cilium, Karpenter)
    system = {
      instance_type = try(local.gpu_inference_config.system_instance_type, "m6i.xlarge")
      ami_type      = "BOTTLEROCKET_x86_64"
      platform      = "bottlerocket"
      min_size      = try(local.gpu_inference_config.system_min_size, 3)
      max_size      = try(local.gpu_inference_config.system_max_size, 6)
      desired_size  = try(local.gpu_inference_config.system_desired_size, 3)

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node-role=system'"

      taints = {
        cilium = {
          key    = "node.cilium.io/agent-not-ready"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }

    # GPU node group — H100 SXM5 instances for inference
    gpu-h100 = {
      instance_type = try(local.gpu_inference_config.gpu_instance_type, "p5.48xlarge")
      ami_type      = "BOTTLEROCKET_x86_64_NVIDIA"
      platform      = "bottlerocket"
      min_size      = try(local.gpu_inference_config.gpu_min_size, 0)
      max_size      = try(local.gpu_inference_config.gpu_max_size, 10)
      desired_size  = try(local.gpu_inference_config.gpu_desired_size, 0)

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node-role=gpu,nvidia.com/gpu.product=H100-SXM5,gpu-inference=true'"

      # Placement group for GPU node affinity
      placement = {
        group_name = try(local.gpu_inference_config.gpu_placement_group, "")
        strategy   = "cluster"
      }

      # Attach GPU interconnect and BGP/GRE security groups
      vpc_security_group_ids = [
        dependency.vpc.outputs.gpu_interconnect_security_group_id,
        dependency.vpc.outputs.bgp_gre_security_group_id,
      ]

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
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
  # ---------------------------------------------------------------------------
  enable_cluster_creator_admin_permissions = true

  # ---------------------------------------------------------------------------
  # EKS Access Entries
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
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
