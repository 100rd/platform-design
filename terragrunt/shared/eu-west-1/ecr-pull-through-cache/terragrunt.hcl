# ---------------------------------------------------------------------------------------------------------------------
# ECR Pull-Through Cache — Shared-services Account, eu-west-1 (ADR-0029)
# ---------------------------------------------------------------------------------------------------------------------
# Mirrors public upstream registries (Docker Hub, Quay, GHCR, registry.k8s.io,
# public.ecr.aws) into the shared account's private ECR registry to defeat
# Docker Hub rate-limits and external-registry outages. The shared account
# already hosts the central ECR registry (see shared/account.hcl), so the cache
# lives here and is reachable by workload accounts via the registry's
# cross-account access model.
#
# Implements ADR-0029. Cached repos are auto-created on first pull with KMS
# encryption, immutable tags, lifecycle, and scan-on-push.
#
# NOTE: the real Docker Hub credential (username + read-only access token) is
# injected out-of-band into the `ecr-pullthroughcache/docker-hub` secret via
# External Secrets Operator (ADR-0008) — never committed here.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/ecr-pull-through-cache"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
  owner        = local.account_vars.locals.owner
  cost_center  = local.account_vars.locals.cost_center
}

# CMK for cached-repository encryption. Mirrors the cloudtrail/aws-config wiring
# convention: consume `key_arns["<purpose>"]` from the per-region kms unit.
# Add an `ecr` key to the kms _envcommon inventory before applying for real.
dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      ecr = "arn:aws:kms:eu-west-1:000000000000:key/mock-ecr-key"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  # Public upstreams to mirror. Docker Hub requires an upstream credential.
  upstreams = {
    ecr-public = { upstream_registry_url = "public.ecr.aws" }
    docker-hub = { upstream_registry_url = "registry-1.docker.io", requires_credential = true }
    quay       = { upstream_registry_url = "quay.io" }
    ghcr       = { upstream_registry_url = "ghcr.io" }
    k8s        = { upstream_registry_url = "registry.k8s.io" }
  }

  kms_key_arn = dependency.kms.outputs.key_arns["ecr"]

  # Cached repos: immutable tags, retain last 50 tagged, expire untagged after 7d.
  image_tag_mutability = "IMMUTABLE"
  max_image_count      = 50
  untagged_expiry_days = 7

  # Enhanced (Inspector) continuous scanning over the cache prefixes.
  scan_type                              = "ENHANCED"
  create_registry_scanning_configuration = true

  tags = {
    Environment = local.environment
    Account     = local.account_name
    Owner       = local.owner
    CostCenter  = local.cost_center
    ManagedBy   = "terragrunt"
    ADR         = "0029"
  }
}
