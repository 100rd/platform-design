# ---------------------------------------------------------------------------------------------------------------------
# Talos MachineConfig — Catalog Unit (WS-A — ml-infra) — ADR-0049 / ADR-0050 / ADR-0052
# ---------------------------------------------------------------------------------------------------------------------
# Renders the immutable Talos MachineConfig (control-plane + GPU-worker) — the single place
# the rbd+ceph kernel modules (ADR-0052) and the NVIDIA system extension (ADR-0050) are
# declared. Gates the whole WS-A stack: nothing else can come up before this.
#
# Requires project.hcl with: environment, baremetal_config (optional)
# Requires region.hcl with: uk_dc (optional)
# Apply-gated: enabled defaults OFF.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/talos-machineconfig"
}

locals {
  project_vars = try(read_terragrunt_config(find_in_parent_folders("project.hcl")), { locals = {} })
  region_vars  = try(read_terragrunt_config(find_in_parent_folders("region.hcl")), { locals = {} })

  environment = try(local.project_vars.locals.environment, "staging")
  baremetal   = try(local.project_vars.locals.baremetal_config, {})
  dc          = try(local.region_vars.locals.uk_dc, "primary")
}

inputs = {
  # Apply-gated default-OFF; flip via baremetal_config.talos_machineconfig_enabled per DC.
  enabled = try(local.baremetal.talos_machineconfig_enabled, false)

  cluster_name     = "uk-${local.dc}"
  cluster_endpoint = try(local.baremetal.cluster_endpoint, "https://10.10.0.10:6443")

  control_plane_endpoints = try(local.baremetal.control_plane_endpoints, ["10.10.0.10"])
  talos_version           = try(local.baremetal.talos_version, "v1.9.2")
  kubernetes_version      = try(local.baremetal.kubernetes_version, "v1.32.0")

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
