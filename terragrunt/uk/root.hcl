# root.hcl — UK Bare-Metal Terragrunt Root Configuration (WS-A stub, ADR-0049)
#
# STUB root.hcl for the UK bare-metal live tree, created by WS-C to allow
# the baremetal-ml-monitoring live-tree shim to validate. The full
# implementation (remote state backend, provider generation, etc.) is owned
# by WS-A and will replace or extend this stub when WS-A lands.
#
# The UK tree uses dc.hcl + env.hcl hierarchy (not account.hcl / region.hcl)
# because bare-metal has no cloud account or region concept.
# This mirrors the pattern of terragrunt/gcp-staging/root.hcl (GCP tree root).
#
# APPLY GATE: plan/validate-only. No apply without explicit human approval.

locals {
  dc_vars  = read_terragrunt_config(find_in_parent_folders("dc.hcl"))
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  dc_name     = local.dc_vars.locals.dc_name
  environment = local.env_vars.locals.environment
}

# ---------------------------------------------------------------------------
# Remote state backend — STUB (WS-A will implement the real backend).
# In-DC bare-metal: likely Vault-backed or S3-compatible (MinIO/Ceph-RGW).
# ---------------------------------------------------------------------------
# remote_state {
#   backend = "s3"
#   config = {
#     bucket  = "tfstate-uk-${local.dc_name}"
#     key     = "${path_relative_to_include()}/terraform.tfstate"
#     region  = "us-east-1"  # placeholder; real backend is in-DC (ADR-0049)
#     use_lockfile = true
#   }
# }

# ---------------------------------------------------------------------------
# Provider generation — STUB (WS-A will inject the kubernetes / talos provider
# configs, pointing at the Talos cluster endpoint from talos-cluster outputs).
# ---------------------------------------------------------------------------
