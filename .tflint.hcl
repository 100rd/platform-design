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

# Terragrunt generates versions.tf, provider.tf, and backend.tf at runtime
# via generate blocks, so these rules produce false positives in module source code
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}
