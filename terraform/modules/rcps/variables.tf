variable "organization_id" {
  description = "AWS Organization ID (e.g. 'o-abc123'). Used as the aws:PrincipalOrgID match in the org-perimeter RCP."
  type        = string
}

variable "target_ou_ids" {
  description = "List of OU (or root) IDs to attach the org-perimeter RCP to. Per ADR-0017 staged rollout, wire ONLY the Policy-Staging OU id first; switch to the root id to promote once staging is verified clean."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to RCP resources"
  type        = map(string)
  default     = {}
}
