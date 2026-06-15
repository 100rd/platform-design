# dc.hcl — UK primary datacenter (WS-A/C, ADR-0049)
# Overrides terragrunt/uk/dc.hcl for the primary DC.
# ADR-0049 D5: primary-active cluster; standby is hot-standby.
locals {
  dc_name     = "uk-primary"
  dc_location = "uk-primary"
  environment = "production"
}
