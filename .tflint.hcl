plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.35.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  call_module_type    = "none"
  force               = false
  disabled_by_default = false
}

# Enforce naming conventions
rule "terraform_naming_convention" {
  enabled = true
}

# Enforce consistent type usage
rule "terraform_typed_variables" {
  enabled = true
}

# Require descriptions for variables and outputs
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# Disallow deprecated syntax
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# ---------------------------------------------------------------------------
# ADR-0028: Unified Platform Tagging Taxonomy — required-tag enforcement
# ---------------------------------------------------------------------------
# Fail CI when a taggable AWS resource is missing any of the five canonical
# platform:* tag keys. This is the "strict linter rule" mitigation called out
# in ADR-0028 Risks -> Tag Key Mismatch.
#
# How it interacts with the Terragrunt root config:
#   - The root provider `default_tags` (terragrunt/root.hcl) applies these keys
#     to every resource at apply time. TFLint, however, lints the *module
#     source* in isolation (call_module_type = "none") and does NOT see
#     provider default_tags or Terragrunt-injected inputs.
#   - Therefore a resource is "compliant" here only if its own `tags`/`var.tags`
#     plumbs these keys through. Modules wire `tags = var.tags` (and the root
#     feeds var.tags the platform:* set), so resources tagged from `var.tags`
#     pass; a resource hard-coding a partial tag map fails.
#
# The exact key casing/format below is load-bearing: it must match the K8s
# platform.* labels' AWS counterparts byte-for-byte or the Grafana/FinOps joins
# in ADR-0028 break.
rule "aws_resource_missing_tags" {
  enabled = true

  tags = [
    "platform:system",
    "platform:component",
    "platform:env",
    "platform:owner",
    "platform:managed-by",
  ]

  # Resources that cannot carry these tags or are tagged exclusively via the
  # provider default_tags (and never via module `var.tags`) would otherwise
  # raise unactionable findings during the migration. Exclusions are tracked
  # against ADR-0028 Consequences -> Migration Effort and trimmed as modules
  # are refactored to thread var.tags through every taggable resource.
  exclude = []
}

# Terragrunt generates versions.tf, provider.tf, and backend.tf at runtime
# via generate blocks, so these rules produce false positives in module source code
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}
