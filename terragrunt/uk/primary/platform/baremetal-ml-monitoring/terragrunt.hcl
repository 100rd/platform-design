# Live tree unit: UK Primary — baremetal-ml-monitoring (WS-C)
# ADR-0038 (drift monitoring), ADR-0049 (bare-metal foundation)
#
# Thin live-tree shim instantiating the catalog unit for the UK primary DC.
# The catalog unit (catalog/units/baremetal-ml-monitoring/terragrunt.hcl)
# provides all inputs and dependencies.
#
# APPLY GATE: plan/validate-only (never_apply = true in CI profile).

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/catalog/units/baremetal-ml-monitoring"
}
