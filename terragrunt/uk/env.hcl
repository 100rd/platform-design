# env.hcl — UK bare-metal environment hierarchy file (WS-A/C, ADR-0049)
# Read by all units under terragrunt/uk/ via find_in_parent_folders("env.hcl").
locals {
  environment = "production"
}
