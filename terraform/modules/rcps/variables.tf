variable "organization_id" {
  description = "AWS Organization ID (e.g. 'o-abc123'). Used as the aws:PrincipalOrgID match in the org-perimeter RCP."
  type        = string
}

variable "target_ou_ids" {
  description = "List of OU (or root) IDs to attach the org-perimeter RCP to. ADR-0017 staged rollout → root promotion: STAGE by wiring ONLY the Policy-Staging OU id first; PROMOTE by appending the organization root id once staging is verified clean. The attachment is a for_each set, so adding the root id is additive (Policy-Staging stays attached) and removing it cleanly reverts to staged-only."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to RCP resources"
  type        = map(string)
  default     = {}
}
