# -----------------------------------------------------------------------------
# _envcommon: EKS module — shared inputs, dependencies, and source pin
# -----------------------------------------------------------------------------
# Included from a per-environment unit via:
#
#   include "root" {
#     path = find_in_parent_folders("root.hcl")
#   }
#   include "envcommon" {
#     path           = find_in_parent_folders("_envcommon/eks.hcl")
#     expose         = true
#     merge_strategy = "deep"
#   }
#
#   inputs = {
#     # Per-env overrides (cluster_version, instance types, sizing) go here.
#   }
#
# This file pins the module source and surfaces every input that's the same
# across environments. Per-env tweaks happen in the unit's own `inputs` block.
# -----------------------------------------------------------------------------

locals {
  # Module source (path-based; bumped repo-wide when EKS module changes).
  module_source = "${get_repo_root()}/project/platform-design/terraform/modules/eks"

  # Cross-cutting defaults — only overwrite when an env truly diverges.
  defaults = {
    # Latest supported version (see PROJECT_STATUS.md for the cluster matrix).
    cluster_version = "1.34"

    # Endpoint posture — flip to false in non-prod with caution.
    endpoint_private_access = true
    endpoint_public_access  = false

    # Control-plane logs: audit + authenticator are required for
    # centralized aggregation (see issue #178).
    enabled_cluster_log_types = [
      "api",
      "audit",
      "authenticator",
      "controllerManager",
      "scheduler",
    ]

    # Encryption-at-rest for secrets via the env's KMS key.
    secrets_encryption_enabled = true
  }
}

terraform {
  source = local.module_source
}

# Common dependency: VPC must exist before EKS. Per-env units extend
# this with additional dependencies (KMS for secrets, IAM roles, etc.)
# via `dependency` blocks in their own files (deep merge applies).
dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id             = "vpc-mock0123456789abcdef"
    private_subnet_ids = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
    public_subnet_ids  = ["subnet-mockA", "subnet-mockB", "subnet-mockC"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  cluster_version            = local.defaults.cluster_version
  endpoint_private_access    = local.defaults.endpoint_private_access
  endpoint_public_access     = local.defaults.endpoint_public_access
  enabled_cluster_log_types  = local.defaults.enabled_cluster_log_types
  secrets_encryption_enabled = local.defaults.secrets_encryption_enabled

  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids
}
