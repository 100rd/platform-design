variable "repository" {
  description = "Repository name (without owner). The provider's `owner` is configured at the provider level."
  type        = string
}

variable "branch_pattern" {
  description = "Branch name or pattern (regex) to protect. Default 'main' protects the canonical default branch."
  type        = string
  default     = "main"
}

variable "required_status_checks" {
  description = "Required status check names (workflow job names). Empty list disables the required-checks gate. Strict (require branch up-to-date) is configurable separately."
  type        = list(string)
  default     = []
}

variable "strict_status_checks" {
  description = "Require branch to be up-to-date with base before merging. Recommended for monorepos to keep plans deterministic."
  type        = bool
  default     = true
}

variable "required_approving_review_count" {
  description = "Number of approving reviews required to merge. 0 disables required reviews; 1 is the typical baseline; 2 for prod-affecting branches."
  type        = number
  default     = 1
  validation {
    condition     = var.required_approving_review_count >= 0 && var.required_approving_review_count <= 6
    error_message = "GitHub allows 0-6 required approving reviews."
  }
}

variable "dismiss_stale_reviews" {
  description = "Dismiss stale approvals when new commits are pushed. Strongly recommended."
  type        = bool
  default     = true
}

variable "require_code_owner_reviews" {
  description = "Require review from CODEOWNERS for paths that match. Requires a CODEOWNERS file in the repo."
  type        = bool
  default     = false
}

variable "require_last_push_approval" {
  description = "Require an explicit approval AFTER the most recent push (the 'last-push approval' control)."
  type        = bool
  default     = false
}

variable "enforce_admins" {
  description = "Apply branch protection to admins (admins cannot bypass). Recommended on for prod repos."
  type        = bool
  default     = true
}

variable "allows_deletions" {
  description = "Allow the protected branch to be deleted. Should be false for main."
  type        = bool
  default     = false
}

variable "allows_force_pushes" {
  description = "Allow force-pushes. Should be false for main."
  type        = bool
  default     = false
}

variable "require_conversation_resolution" {
  description = "Require all conversations on the PR to be resolved before merge."
  type        = bool
  default     = true
}

variable "require_signed_commits" {
  description = "Require signed commits. Recommended on for compliance-sensitive repos but disabled by default to ease developer onboarding."
  type        = bool
  default     = false
}

variable "lock_branch" {
  description = "Lock the branch (read-only). Use only for archived branches."
  type        = bool
  default     = false
}

variable "bypass_pull_request_actor_ids" {
  description = "Node IDs of users / teams / apps allowed to bypass the pull-request requirement (e.g., Dependabot). Use sparingly and document each entry."
  type        = list(string)
  default     = []
}

variable "push_restrictions_actor_ids" {
  description = "Node IDs of users / teams allowed to push directly to the branch. Empty list disables direct pushes for everyone."
  type        = list(string)
  default     = []
}

variable "restrict_pushes_blocks_creations" {
  description = "If push_restrictions are set, also block branch CREATIONS by non-listed actors."
  type        = bool
  default     = true
}
