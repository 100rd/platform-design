# dc.hcl — UK bare-metal datacenter hierarchy file (WS-A/C, ADR-0049)
#
# Root-level DC config read by all units under terragrunt/uk/.
# Convention mirrors account.hcl / region.hcl for the AWS live tree.
# Units under terragrunt/uk/{primary,standby}/ override dc_name via a
# local dc.hcl in that subdirectory (shadows this file on parent-folder walk).
#
# ADR-0028: dc_name feeds platform_cluster label on all resources.
locals {
  dc_name     = "uk"
  dc_location = "uk"
  environment = "production"
}
