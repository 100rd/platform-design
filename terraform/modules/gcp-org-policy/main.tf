# ---------------------------------------------------------------------------------------------------------------------
# GCP Organization Policy Module (WS-E — security / compliance)
# ---------------------------------------------------------------------------------------------------------------------
# Binds a set of GCP org-policy constraints to a resource-manager node (org / folder
# / project) to give the GCP estate guardrail parity with the AWS SCP + iam-baseline
# controls already in this repo:
#
#   AWS control (in-repo)                         GCP parity (this module)
#   ------------------------------------------    -------------------------------------------------
#   scps deny_s3_public + iam-baseline S3 PAB     storage.publicAccessPrevention
#   iam-baseline EBS-encryption-by-default        gcp.restrictNonCmekServices (CMEK)
#   scps restrict_regions                         gcp.resourceLocations
#   iam-baseline MFA / no static creds            iam.disableServiceAccountKeyCreation/Upload
#   (no AWS analog — GCP-specific hardening)      compute.vmExternalIpAccess, compute.requireOsLogin,
#                                                 sql.restrictPublicIp, storage.uniformBucketLevelAccess
#
# Uses the modern `google_org_policy_policy` resource (provider google ~> 6, the
# v2 Org Policy API), NOT the deprecated `google_organization_policy` (v1). Boolean
# constraints set `spec.rules[].enforce = "TRUE"`; list constraints set
# `deny_all` / `values { allowed_values | denied_values }`.
#
# ADR-0028 note: org-policy bindings are not labelable GCP resources, so the
# platform taxonomy is carried on var.labels for provenance (see variables.tf) and
# echoed into the local below; it is not applied to a billable resource here. This
# mirrors how gcp-billing-budget handles google_billing_budget's lack of labels.
#
# plan/validate-only — apply is gated behind explicit human approval + blast-radius
# review (an org-policy change is org-wide and must never auto-apply).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # ADR-0028 baseline taxonomy for this system, merged with caller overrides.
  # Recorded for provenance; see variables.tf for why it is not applied to a resource.
  platform_labels = merge(
    {
      platform_system     = "security"
      platform_component  = "org-policy"
      platform_managed_by = "terragrunt"
    },
    var.labels,
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# compute.vmExternalIpAccess — LIST constraint (allow-list of instances permitted an
# external IP). Empty allow-list => deny_all (no external IPs); non-empty => permit
# only those values.
# ---------------------------------------------------------------------------------------------------------------------

resource "google_org_policy_policy" "vm_external_ip" {
  count = var.restrict_vm_external_ip ? 1 : 0

  name   = "${var.parent}/policies/compute.vmExternalIpAccess"
  parent = var.parent

  spec {
    rules {
      deny_all = length(var.vm_external_ip_allowed_projects) == 0 ? "TRUE" : null

      dynamic "values" {
        for_each = length(var.vm_external_ip_allowed_projects) > 0 ? [1] : []
        content {
          allowed_values = var.vm_external_ip_allowed_projects
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Boolean constraints — enforce = TRUE.
# ---------------------------------------------------------------------------------------------------------------------

resource "google_org_policy_policy" "disable_sa_key_creation" {
  count = var.disable_sa_key_creation ? 1 : 0

  name   = "${var.parent}/policies/iam.disableServiceAccountKeyCreation"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "disable_sa_key_upload" {
  count = var.disable_sa_key_upload ? 1 : 0

  name   = "${var.parent}/policies/iam.disableServiceAccountKeyUpload"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "require_os_login" {
  count = var.require_os_login ? 1 : 0

  name   = "${var.parent}/policies/compute.requireOsLogin"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "restrict_public_ip_cloudsql" {
  count = var.restrict_public_ip_cloudsql ? 1 : 0

  name   = "${var.parent}/policies/sql.restrictPublicIp"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "uniform_bucket_level_access" {
  count = var.uniform_bucket_level_access ? 1 : 0

  name   = "${var.parent}/policies/storage.uniformBucketLevelAccess"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "public_access_prevention" {
  count = var.enforce_public_access_prevention ? 1 : 0

  name   = "${var.parent}/policies/storage.publicAccessPrevention"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# List constraints — CMEK and resource-location guardrails.
# ---------------------------------------------------------------------------------------------------------------------

resource "google_org_policy_policy" "restrict_non_cmek_services" {
  count = length(var.enforce_cmek) > 0 ? 1 : 0

  name   = "${var.parent}/policies/gcp.restrictNonCmekServices"
  parent = var.parent

  spec {
    rules {
      values {
        # Services listed here are DENIED the ability to create non-CMEK resources,
        # i.e. CMEK becomes mandatory for them.
        denied_values = var.enforce_cmek
      }
    }
  }
}

resource "google_org_policy_policy" "resource_locations" {
  count = length(var.allowed_resource_locations) > 0 ? 1 : 0

  name   = "${var.parent}/policies/gcp.resourceLocations"
  parent = var.parent

  spec {
    rules {
      values {
        allowed_values = var.allowed_resource_locations
      }
    }
  }
}
