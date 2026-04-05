variable "project" {
  description = "Project name used in IAM role naming (e.g. 'platform-design')"
  type        = string
}

variable "account_name" {
  description = "Short account name used in IAM role naming (e.g. 'dev', 'prod', 'management')"
  type        = string
}

variable "repository" {
  description = "GitHub repository in 'org/repo' format (e.g. '100rd/platform-design')"
  type        = string
}

variable "branch" {
  description = "Default branch name. The terraform role is scoped to pushes on this branch."
  type        = string
  default     = "main"
}

variable "extra_subjects" {
  description = "Additional OIDC subjects to add to the terraform role beyond the defaults (main branch, PR, environment). Useful for environment-specific deployments."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}
