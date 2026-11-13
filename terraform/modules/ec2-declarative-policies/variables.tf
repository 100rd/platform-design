variable "target_ou_ids" {
  description = "List of OU (or root) IDs to attach the EC2 declarative policy to. ADR-0017 staged rollout: wire ONLY the Policy-Staging OU id first; append the org root id once verified clean. for_each set → additive/reversible."
  type        = list(string)
  default     = []
}

variable "require_imdsv2" {
  description = "Require IMDSv2 (instance_metadata_defaults.http_tokens = required). Retires the require_imdsv2 SCP per ADR-0017."
  type        = bool
  default     = true
}

variable "imds_hop_limit" {
  description = "Default IMDS PUT response hop limit (1 = no containers reach IMDS; 2 = allow one container hop)."
  type        = number
  default     = 2
}

variable "block_public_ebs_snapshots" {
  description = "Block public sharing of new EBS snapshots (snapshot_block_public_access = block_new_sharing)."
  type        = bool
  default     = true
}

variable "block_public_amis" {
  description = "Block public sharing of new AMIs (image_block_public_access = block_new_sharing)."
  type        = bool
  default     = true
}

variable "enable_allowed_images" {
  description = "Enforce the allowed-AMI providers criteria."
  type        = bool
  default     = true
}

variable "allowed_images_state" {
  description = "Allowed-images enforcement mode: audit_mode (log only, staged-rollout default), enabled (enforce), or disabled."
  type        = string
  default     = "audit_mode"

  validation {
    condition     = contains(["audit_mode", "enabled", "disabled"], var.allowed_images_state)
    error_message = "allowed_images_state must be one of: audit_mode, enabled, disabled."
  }
}

variable "allowed_image_providers" {
  description = "Allowed AMI providers (e.g. [\"amazon\"] and/or specific account IDs) when allowed-images is enforced."
  type        = list(string)
  default     = ["amazon"]
}

variable "exception_message" {
  description = "Message surfaced to users whose EC2 API call is blocked by this declarative policy."
  type        = string
  default     = "Blocked by the organization EC2 declarative baseline (ADR-0017). Contact the platform team."
}

variable "tags" {
  description = "Tags to apply to the policy resource."
  type        = map(string)
  default     = {}
}
