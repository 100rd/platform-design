# ---------------------------------------------------------------------------------------------------------------------
# baremetal-org-policy — Talos OS security-posture assertions + Kyverno/Gatekeeper
# policy bundle as code (WS-E — security / compliance).
# ---------------------------------------------------------------------------------------------------------------------
# This module is the bare-metal analogue of terraform/modules/gcp-org-policy. The
# Talos estate has no cloud org-policy API, so guardrail parity is delivered as:
#
#   AWS/GCP control (in-repo)                     Bare-metal/Talos parity (this module)
#   ------------------------------------------    -------------------------------------------------
#   iam-baseline MFA / no static creds            Talos mTLS machine API, no SSH/shell (posture assertion)
#   gcp.requireOsLogin / no project SSH keys      Talos no-SSH posture assertion (no shell path at all)
#   scps deny_public + S3 PAB                     Kyverno default-deny + tenant-isolation policy bundle
#   iam-baseline immutable/atomic change          Talos A/B-partition immutable install assertion
#   gcp.restrictNonCmekServices                   (handled by ESO/Vault + Rook-Ceph at-rest, out of scope here)
#
# Two planes, both PLAN-SAFE:
#   1. Posture assertions (locals) — compares the EXPECTED Talos posture (assert_*)
#      against the OBSERVED posture (observed_*, wired from WS-A talos-machineconfig)
#      and emits posture_violations. Pure computation; never touches a cluster. This
#      is the artifact the SOC2 matrix cites for the immutable-OS controls.
#   2. Policy bundle (kubectl_manifest) — Kyverno/Gatekeeper CRs delivered as code,
#      DEFAULT-OFF (deploy_policy_bundle = false => for_each is empty => zero
#      resources). Plan-only renders the bundle into outputs for review.
#
# ADR-0028: rendered CR labels carry the dotted taxonomy (platform.system); the
# Terraform plane records the underscore form for provenance (see local below).
# ADR-0040 (SOC posture, reused) + ADR-0049 (foundation) + ADR-0050 (immutable-OS).
#
# plan/validate-only — apply is gated behind explicit human approval + blast-radius
# review. A policy-bundle change is cluster-wide admission control and must never
# auto-apply.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # ADR-0028 baseline taxonomy for this system, merged with caller overrides.
  # Underscore form on the Terraform plane (recorded for provenance).
  platform_labels = merge(
    {
      platform_system     = "security"
      platform_component  = "org-policy"
      platform_managed_by = "terragrunt"
    },
    var.labels,
  )

  # Dotted form for the K8s/CR plane (ADR-0028). Re-key the leading "platform_"
  # prefix to "platform." and any remaining underscore to a hyphen, so
  # platform_managed_by -> platform.managed-by (NOT platform.managed.by), matching
  # the established dotted taxonomy keys (platform.system / .component / .owner /
  # .env / .managed-by) used across apps/infra/kyverno.
  cr_labels = {
    for k, v in local.platform_labels :
    replace(replace(k, "platform_", "platform."), "_", "-") => v
  }

  # -------------------------------------------------------------------------------------------------------------------
  # Posture assertions. Each entry: { asserted, observed_ok, soc2 }. observed_ok is
  # the boolean "the observed posture satisfies the assertion". A violation is an
  # assertion that is asserted = true but observed_ok = false.
  # -------------------------------------------------------------------------------------------------------------------
  posture = {
    no_ssh = {
      asserted    = var.assert_no_ssh
      observed_ok = var.observed_ssh_enabled == false
      soc2        = "CC6.1/CC6.6"
      desc        = "Talos exposes no SSH/shell path (no sshd, no extra kernel args opening a shell)"
    }
    mtls_machine_api = {
      asserted    = var.assert_mtls_machine_api
      observed_ok = var.observed_machine_api_mtls == true
      soc2        = "CC6.1/CC6.7"
      desc        = "Talos machine API is mTLS-only with strict client-cert auth (no plaintext)"
    }
    kubeprism = {
      asserted    = var.assert_kubeprism_enabled
      observed_ok = var.observed_kubeprism_enabled == true
      soc2        = "A1.2/CC7.5"
      desc        = "machine.features.kubePrism enabled (in-cluster API HA, no API VIP SPOF)"
    }
    immutable_install = {
      asserted    = var.assert_immutable_install
      observed_ok = var.observed_install_immutable == true
      soc2        = "CC8.1"
      desc        = "Immutable install disk; A/B-partition atomic upgrade with auto-rollback"
    }
    no_package_manager = {
      asserted    = var.assert_no_package_manager
      observed_ok = var.observed_package_manager_present == false
      soc2        = "CC6.8"
      desc        = "No package manager / writable /usr (GPU driver via Talos system extension, ADR-0050)"
    }
  }

  # The set of assertions that are turned ON.
  active_assertions = {
    for k, v in local.posture : k => v if v.asserted
  }

  # Violations: asserted but observed posture does not satisfy it.
  posture_violations = [
    for k, v in local.active_assertions : {
      assertion = k
      soc2      = v.soc2
      detail    = v.desc
    } if v.observed_ok == false
  ]

  posture_compliant = length(local.posture_violations) == 0

  # -------------------------------------------------------------------------------------------------------------------
  # Built-in Kyverno tenant-isolation policy bundle (the UK doc's Gatekeeper tenant
  # constraints, ported to Kyverno ClusterPolicy). Rendered as YAML strings; only
  # materialised as kubectl_manifest when deploy_policy_bundle = true.
  # -------------------------------------------------------------------------------------------------------------------
  builtin_policies = merge(
    var.enforce_tenant_label ? {
      "require-tenant-label" = yamlencode({
        apiVersion = "kyverno.io/v1"
        kind       = "ClusterPolicy"
        metadata = {
          name   = "bm-${var.cluster_name}-require-tenant-label"
          labels = local.cr_labels
          annotations = {
            adr                                   = "ADR-0028,ADR-0040,ADR-0049"
            "policies.kyverno.io/title"           = "Require tenant label (bare-metal)"
            "policies.kyverno.io/category"        = "Multi-Tenancy"
            "platform-design.io/dc"               = var.dc_name
            "platform-design.io/enforcement-mode" = var.policy_enforcement_mode
          }
        }
        spec = {
          validationFailureAction = var.policy_enforcement_mode
          background              = true
          rules = [{
            name  = "require-tenant-on-pods"
            match = { any = [{ resources = { kinds = ["Pod"] } }] }
            exclude = { any = [{ resources = { namespaces = [
              "kube-system", "kube-public", "kube-node-lease", "kyverno",
              "gatekeeper-system", "external-secrets", "argocd", "monitoring",
            ] } }] }
            validate = {
              message = "Pod is missing the required tenant={id} label (bare-metal tenant isolation, ADR-0049 / UK-DC Gatekeeper constraint)."
              pattern = { metadata = { labels = { tenant = "?*" } } }
            }
          }]
        }
      })
    } : {},
    var.enforce_no_cross_ns_sa ? {
      "deny-cross-ns-sa" = yamlencode({
        apiVersion = "kyverno.io/v1"
        kind       = "ClusterPolicy"
        metadata = {
          name   = "bm-${var.cluster_name}-deny-cross-ns-sa"
          labels = local.cr_labels
          annotations = {
            adr                                   = "ADR-0028,ADR-0040,ADR-0049"
            "policies.kyverno.io/title"           = "Deny cross-namespace ServiceAccount refs (bare-metal)"
            "policies.kyverno.io/category"        = "Multi-Tenancy"
            "platform-design.io/dc"               = var.dc_name
            "platform-design.io/enforcement-mode" = var.policy_enforcement_mode
          }
        }
        spec = {
          validationFailureAction = var.policy_enforcement_mode
          background              = false
          rules = [{
            name  = "deny-foreign-sa"
            match = { any = [{ resources = { kinds = ["Pod"] } }] }
            validate = {
              message = "Pod may not reference a ServiceAccount in another namespace (cross-namespace SA refs are denied; SOC2 CC6.3 least privilege)."
              deny = {
                conditions = {
                  any = [{
                    key      = "{{ request.object.spec.serviceAccountName || '' }}"
                    operator = "AnyIn"
                    value    = ["system:serviceaccount:*"]
                  }]
                }
              }
            }
          }]
        }
      })
    } : {},
  )

  # Full bundle = built-ins + caller-supplied extras.
  policy_bundle = merge(local.builtin_policies, var.policy_bundle_manifests)
}

# ---------------------------------------------------------------------------------------------------------------------
# Policy bundle delivery — APPLY-GATED / DEFAULT-OFF.
# When deploy_policy_bundle = false (default) the for_each collapses to an empty map
# and NO kubectl_manifest resource is created: a plan against this module creates
# zero infra. When explicitly enabled (CI on main, after human go), each bundle entry
# becomes one CR. The kubectl provider is configured at the catalog-unit layer from
# the talos-cluster kubeconfig (mock at plan time) — no static credentials here.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubectl_manifest" "policy" {
  for_each = var.deploy_policy_bundle ? local.policy_bundle : {}

  yaml_body = each.value

  # Server-side apply so CRDs (Kyverno/Gatekeeper) are validated by the API server.
  server_side_apply = true
  wait              = false
}
