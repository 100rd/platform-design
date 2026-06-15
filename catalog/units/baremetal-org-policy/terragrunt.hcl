# ---------------------------------------------------------------------------------------------------------------------
# baremetal-org-policy — Catalog Unit (WS-E — security / compliance, bare metal)
# ---------------------------------------------------------------------------------------------------------------------
# Binds the Talos OS security-posture assertions (immutable OS, no SSH, mTLS machine
# API, KubePrism, no package manager) + the Kyverno/Gatekeeper tenant-isolation policy
# bundle to a per-DC Talos cluster. Bare-metal analogue of catalog/units/gcp-org-policy.
#
# Two planes, both plan-safe:
#   - Posture assertions read the OBSERVED posture from the WS-A talos-machineconfig
#     unit (dependency, mock at plan time) and emit posture_violations.
#   - The policy bundle is APPLY-GATED (deploy_policy_bundle = false by default): a
#     plan creates ZERO kubectl_manifest resources. Flip to true only in CI on main
#     after human go + blast-radius review (cluster-wide admission control).
#
# Dependencies (in the WS-A baremetal-gpu-analysis stack):
#   - talos-cluster        (kubeconfig / endpoint / CA — for the kubectl provider)
#   - talos-machineconfig  (the observed OS posture this module asserts against)
#
# Requires site.hcl with: dc_name, environment (mirrors the WS-B sibling unit).
#
# ADR-0028: Terraform-plane labels use underscore keys (platform_system); rendered
# policy CRs carry the dotted form. ADR-0040 (SOC posture, reused) + ADR-0049
# (foundation/posture) + ADR-0050 (immutable-OS rationale).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/baremetal-org-policy"
}

locals {
  site_vars = read_terragrunt_config(find_in_parent_folders("site.hcl"))

  dc_name     = local.site_vars.locals.dc_name     # "uk-primary" | "uk-standby"
  environment = local.site_vars.locals.environment # e.g. "prod"

  security_config = try(local.site_vars.locals.security_config, {})

  cluster_name = try(local.security_config.cluster_name, "talos-${local.dc_name}")
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Talos cluster (kubeconfig + endpoint from WS-A talos-cluster unit).
# Used to configure the kubectl provider for the (apply-gated) policy bundle.
# ---------------------------------------------------------------------------------------------------------------------

dependency "talos_cluster" {
  config_path = "../talos-cluster"

  mock_outputs = {
    kubeconfig_raw = "apiVersion: v1\nclusters: []\ncontexts: []\nkind: Config\nusers: []"
    endpoint       = "https://10.0.0.1:6443"
    ca_certificate = "bW9jay1jYS1jZXJ0"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Talos machine config (the OBSERVED OS posture WS-A renders). Each
# observed_* input below is read from this unit's outputs so the posture assertion
# compares the asserted posture against what talos-machineconfig actually produced.
# Compliant mock defaults keep the unit green at plan time; a drifted real cluster
# surfaces posture_violations.
# ---------------------------------------------------------------------------------------------------------------------

dependency "talos_machineconfig" {
  config_path = "../talos-machineconfig"

  mock_outputs = {
    ssh_enabled             = false
    machine_api_mtls        = true
    kubeprism_enabled       = true
    install_immutable       = true
    package_manager_present = false
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS: kubectl authenticated via the Talos cluster endpoint + CA. No static
# credentials — the in-cluster kubeconfig is materialised by talos-cluster. In
# plan-only/mock mode the provider is exercised against mock outputs and (because the
# bundle is apply-gated) creates nothing.
# ---------------------------------------------------------------------------------------------------------------------

generate "baremetal_providers" {
  path      = "baremetal_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "kubectl" {
      host                   = "${dependency.talos_cluster.outputs.endpoint}"
      cluster_ca_certificate = base64decode("${dependency.talos_cluster.outputs.ca_certificate}")
      load_config_file       = false
    }
  PROVIDERS
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  cluster_name = local.cluster_name
  dc_name      = local.dc_name

  # APPLY-GATED: the Kyverno/Gatekeeper bundle is NOT delivered by default. A plan
  # against this unit creates zero kubectl_manifest resources. Flip via site.hcl
  # (security_config.deploy_policy_bundle = true) only in CI on main after human go.
  deploy_policy_bundle    = try(local.security_config.deploy_policy_bundle, false)
  policy_enforcement_mode = try(local.security_config.policy_enforcement_mode, "Audit")
  enforce_tenant_label    = try(local.security_config.enforce_tenant_label, true)
  enforce_no_cross_ns_sa  = try(local.security_config.enforce_no_cross_ns_sa, true)

  # OBSERVED posture wired from the WS-A talos-machineconfig unit.
  observed_ssh_enabled             = dependency.talos_machineconfig.outputs.ssh_enabled
  observed_machine_api_mtls        = dependency.talos_machineconfig.outputs.machine_api_mtls
  observed_kubeprism_enabled       = dependency.talos_machineconfig.outputs.kubeprism_enabled
  observed_install_immutable       = dependency.talos_machineconfig.outputs.install_immutable
  observed_package_manager_present = dependency.talos_machineconfig.outputs.package_manager_present

  # ADR-0028 taxonomy (underscore keys on the Terraform plane).
  labels = {
    platform_env   = local.environment
    platform_owner = try(local.security_config.owner, "team-sec")
  }
}
