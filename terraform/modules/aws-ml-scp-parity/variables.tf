# ---------------------------------------------------------------------------------------------------------------------
# Variables — aws-ml-scp-parity
# ---------------------------------------------------------------------------------------------------------------------
# WS-E SCP-parity plane for the greenfield AWS GPU/ML account (ADR-0044 §A1 greenfield,
# ADR-0048 backends). Mirrors the GCP org-policy deny-list plane from ADR-0040 D1 onto
# AWS Service Control Policies, scoped to the ML/GPU OU. apply-gated and default-OFF:
# every SCP attachment is behind `enabled` + a per-policy toggle so plan/validate never
# creates a real org policy.
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Master gate. When false (DEFAULT), the module creates and attaches NO Service Control Policies — apply-gated so plan/validate is inert. Set true only behind an explicit human apply + blast-radius review (SCPs are org-wide)."
  type        = bool
  default     = false
}

variable "project" {
  description = "Project name used in SCP policy naming (e.g. 'platform-design'). Net-new ML SCPs are prefixed with this and 'ml-'."
  type        = string
  default     = "platform-design"
}

variable "ml_target_ou_ids" {
  description = "List of AWS Organizations OU IDs that host the GPU/ML account(s). The ML deny-list SCPs are attached to these targets only — never to the org root, to bound blast radius to the ML estate (ADR-0040 staged-rollout posture)."
  type        = list(string)
  default     = []
}

variable "allowed_gpu_regions" {
  description = "Regions where GPU/ML resources may be created. Mirrors the GCP `gcp.resourceLocations` data-residency constraint (ADR-0040 D1 -> SOC2 C1.1). Used by the region-restriction SCP for the ML OU."
  type        = list(string)
  default = [
    "eu-west-1",
    "us-east-1",
    "us-west-2",
  ]
}

variable "terraform_role_name_pattern" {
  description = "IAM role-name pattern (wildcard) for the Terraform/Terragrunt execution role that is EXEMPT from the region-restriction SCP so it can call global services (IAM, STS, Route53) during ML stack provisioning. Mirrors the scps module exemption philosophy."
  type        = string
  default     = "platform-design-terraform-*"
}

variable "require_imdsv2" {
  description = "When true, attach an SCP denying EC2 RunInstances unless IMDSv2 is required (HttpTokens=required). Hardens GPU nodes against SSRF credential theft (CIS / SOC2 CC6.1). Gated by `enabled`."
  type        = bool
  default     = true
}

variable "require_ebs_encryption" {
  description = "When true, attach an SCP denying creation of unencrypted EBS volumes / RunInstances without encrypted block devices. AWS analog of the GCP `gcp.restrictNonCmekServices` constraint (ADR-0040 D1 -> SOC2 CC6.1). Gated by `enabled`."
  type        = bool
  default     = true
}

variable "deny_long_lived_access_keys" {
  description = "When true, attach an SCP denying `iam:CreateAccessKey` in the ML OU, forcing EKS Pod Identity / role assumption (ADR-0018) instead of static keys. AWS analog of GCP `iam.disableServiceAccountKeyCreation` (ADR-0040 D1/D2 -> SOC2 CC6.1/CC6.3). Gated by `enabled`."
  type        = bool
  default     = true
}

variable "restrict_gpu_regions" {
  description = "When true, attach a region-restriction SCP limiting the ML OU to `allowed_gpu_regions` (the Terraform role is exempt for global services). AWS analog of GCP `gcp.resourceLocations` (ADR-0040 D1 -> SOC2 C1.1). Gated by `enabled`."
  type        = bool
  default     = true
}

variable "tags" {
  description = "ADR-0028 platform taxonomy tags applied to every SCP resource. Defaults set platform:system=security, platform:component=scp-parity, platform:owner=team-sec. Caller may override platform:env / platform:managed-by."
  type        = map(string)
  default = {
    "platform:system"     = "security"
    "platform:component"  = "scp-parity"
    "platform:owner"      = "team-sec"
    "platform:managed-by" = "terragrunt"
  }
}
