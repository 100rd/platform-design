# ---------------------------------------------------------------------------------------------------------------------
# Inputs for the baremetal-org-policy module (WS-E — security / compliance).
#
# Bare-metal analogue of terraform/modules/gcp-org-policy. Where GCP binds
# org-policy constraints to a resource-manager node, the bare-metal/Talos estate
# has no cloud org-policy API — the equivalent guardrails are:
#   (a) Talos machine-config POSTURE ASSERTIONS (immutable OS, no SSH, mTLS API,
#       KubePrism) evaluated at plan time, and
#   (b) a Kyverno/Gatekeeper admission policy BUNDLE delivered as code.
#
# ADR-0028: Talos/K8s plane uses the DOTTED label form (platform.system = security);
# the Terraform plane records the UNDERSCORE form (platform_system) for provenance —
# exactly as gcp-org-policy documents for non-labelable bindings.
#
# ADR-0049 (foundation/posture) + ADR-0050 (immutable-OS security rationale) +
# ADR-0040 (SOC posture, reused).
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# Scope / identity.
# ---------------------------------------------------------------------------------------------------------------------

variable "cluster_name" {
  description = "Talos cluster name this posture/policy bundle binds to (e.g. talos-uk-primary). Used in policy/CR names and provenance only; no resource is created against a real cluster in plan/mock mode."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be a DNS-1123 label (lowercase alphanumerics and hyphens, 3-63 chars)."
  }
}

variable "dc_name" {
  description = "UK datacenter this binds to (uk-primary or uk-standby). Mirrors the WS-A stack's per-DC composition under terragrunt/uk/{primary,standby}/platform/."
  type        = string

  validation {
    condition     = contains(["uk-primary", "uk-standby"], var.dc_name)
    error_message = "dc_name must be one of: uk-primary, uk-standby."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Talos OS posture assertions (the immutable-OS controls mapped to SOC2 families).
# These describe the EXPECTED posture the WS-A talos-machineconfig must satisfy.
# The module computes per-assertion pass/fail at plan time (no cluster mutation) so
# the SOC2 matrix can cite a concrete Terraform assertion, per the plan acceptance:
# "a control-to-evidence matrix references concrete Talos-config assertions".
# Each toggle defaults ON (deny-by-default posture); set false only for a documented
# carve-out during staged rollout.
# ---------------------------------------------------------------------------------------------------------------------

variable "assert_no_ssh" {
  description = "Assert the Talos OS posture exposes NO SSH path (no shell, no sshd, no extra kernel args opening a shell). SOC2 CC6.1 / CC6.6 — minimal attack surface."
  type        = bool
  default     = true
}

variable "assert_mtls_machine_api" {
  description = "Assert the Talos machine API is mTLS-only with strict auth (no plaintext, client-cert-gated talosctl). SOC2 CC6.1 / CC6.7."
  type        = bool
  default     = true
}

variable "assert_kubeprism_enabled" {
  description = "Assert machine.features.kubePrism is enabled (in-cluster API HA, no single API VIP SPOF). SOC2 A1.2 / CC7.5."
  type        = bool
  default     = true
}

variable "assert_immutable_install" {
  description = "Assert the OS install disk is immutable / A-B-partition atomic-upgrade with auto-rollback (no in-place host mutation). SOC2 CC8.1 — change management."
  type        = bool
  default     = true
}

variable "assert_no_package_manager" {
  description = "Assert the OS has no package manager / writable /usr (GPU driver ships as a Talos system extension per ADR-0050, never apt-installed). SOC2 CC6.8 — unauthorized software."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# Observed posture — the actual values rendered by WS-A's talos-machineconfig,
# wired in through a dependency block at the catalog-unit layer (mock at plan time).
# The module compares observed vs asserted and emits posture_violations. Defaulting
# observed = expected keeps the module green when wired to a compliant cluster; a
# drifted cluster (e.g. observed_ssh_enabled = true) makes the assertion fail and
# surfaces in the posture_violations output and the *.tftest.hcl.
# ---------------------------------------------------------------------------------------------------------------------

variable "observed_ssh_enabled" {
  description = "Observed: is any SSH/shell path present on the Talos nodes? (from WS-A talos-machineconfig). Compliant posture = false."
  type        = bool
  default     = false
}

variable "observed_machine_api_mtls" {
  description = "Observed: is the Talos machine API mTLS-only with strict auth? (from WS-A talos-machineconfig). Compliant posture = true."
  type        = bool
  default     = true
}

variable "observed_kubeprism_enabled" {
  description = "Observed: is machine.features.kubePrism enabled? (from WS-A talos-machineconfig). Compliant posture = true."
  type        = bool
  default     = true
}

variable "observed_install_immutable" {
  description = "Observed: is the install disk immutable with A/B atomic upgrade + auto-rollback? (from WS-A talos-machineconfig). Compliant posture = true."
  type        = bool
  default     = true
}

variable "observed_package_manager_present" {
  description = "Observed: is a package manager / writable /usr present? (from WS-A talos-machineconfig). Compliant posture = false."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------------------------------------------------
# Admission policy bundle delivery (Kyverno/Gatekeeper CRs as code).
# DEFAULT-OFF (apply-gated): deploy_policy_bundle = false means NO kubectl_manifest
# resource is created — the module renders the bundle into outputs for plan review
# only. Set true (in CI on main, after merge + human go) to actually deliver the CRs.
# Mirrors the plan's "apply-gated / default-OFF where the plan says so".
# ---------------------------------------------------------------------------------------------------------------------

variable "deploy_policy_bundle" {
  description = "Deliver the Kyverno/Gatekeeper policy bundle CRs to the cluster (kubectl_manifest). DEFAULT FALSE — apply-gated; plan-only renders the bundle into outputs without creating any resource."
  type        = bool
  default     = false
}

variable "policy_bundle_manifests" {
  description = "Extra raw YAML policy CR documents (Kyverno ClusterPolicy / Gatekeeper Constraint) to deliver alongside the built-in bare-metal tenant guardrails, keyed by a stable id. Empty = built-ins only. Never put secrets here."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "enforce_tenant_label" {
  description = "Include the built-in Kyverno ClusterPolicy that rejects pods without a tenant={id} label (the UK doc's Gatekeeper tenant constraint, ported to Kyverno). SOC2 CC6.1 — tenant isolation."
  type        = bool
  default     = true
}

variable "enforce_no_cross_ns_sa" {
  description = "Include the built-in policy that rejects cross-namespace ServiceAccount references (the UK doc's second Gatekeeper tenant constraint). SOC2 CC6.3 — least privilege."
  type        = bool
  default     = true
}

variable "policy_enforcement_mode" {
  description = "Admission mode for the built-in Kyverno policies: Audit (observe, record violations) or Enforce (block). Defaults to Audit — matches apps/infra/kyverno's observe-first posture; promote to Enforce after a clean soak window."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Enforce"], var.policy_enforcement_mode)
    error_message = "policy_enforcement_mode must be Audit or Enforce."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ADR-0028 labels. NOTE: neither Talos posture assertions nor admission-policy CRs
# are labelable Terraform resources here (the CRs carry their OWN metadata.labels in
# the rendered YAML), so — exactly like gcp-org-policy / gcp-billing-budget document
# for non-labelable bindings — the platform taxonomy is asserted via this variable
# for catalog/test provenance and is echoed into the rendered policy CR labels. Keys
# use the Talos/K8s UNDERSCORE spelling on the Terraform plane (platform_system).
# ---------------------------------------------------------------------------------------------------------------------

variable "labels" {
  description = "ADR-0028 platform taxonomy (underscore keys on the Terraform plane, e.g. platform_system = security). Echoed into rendered policy CR labels (dotted form) and recorded for provenance."
  type        = map(string)
  default     = {}
  nullable    = false
}
