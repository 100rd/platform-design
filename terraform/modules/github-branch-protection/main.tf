# ---------------------------------------------------------------------------------------------------------------------
# GitHub Branch Protection
# ---------------------------------------------------------------------------------------------------------------------
# Manages a single branch-protection rule for a single repository / branch
# pattern. Designed to be invoked per-repo from a Terragrunt unit so each
# repo gets its own state and bypass list. Issue #177.
#
# Permissions required on the GitHub PAT / app token used by the provider:
#   - Repo Admin (or org-level Admin)
#   - For org-level apps: 'Branch protection rules' read+write.
# ---------------------------------------------------------------------------------------------------------------------

resource "github_branch_protection" "this" {
  repository_id = var.repository
  pattern       = var.branch_pattern

  enforce_admins   = var.enforce_admins
  allows_deletions = var.allows_deletions
  # Force-pushes are blocked when allows_force_pushes = false; the field
  # name is somewhat counter-intuitive, but matches the API.
  allows_force_pushes             = var.allows_force_pushes
  require_conversation_resolution = var.require_conversation_resolution
  require_signed_commits          = var.require_signed_commits
  lock_branch                     = var.lock_branch

  # Required status checks block — only included when at least one check
  # is listed (empty list disables the gate cleanly).
  dynamic "required_status_checks" {
    for_each = length(var.required_status_checks) > 0 ? [1] : []
    content {
      strict   = var.strict_status_checks
      contexts = var.required_status_checks
    }
  }

  # Required PR review block — only included when at least one approval
  # is required (count = 0 disables reviews).
  dynamic "required_pull_request_reviews" {
    for_each = var.required_approving_review_count > 0 ? [1] : []
    content {
      required_approving_review_count = var.required_approving_review_count
      dismiss_stale_reviews           = var.dismiss_stale_reviews
      require_code_owner_reviews      = var.require_code_owner_reviews
      require_last_push_approval      = var.require_last_push_approval

      # Bypass list — empty by default. Add Dependabot or platform-team
      # actor IDs as needed; each entry is a node ID (not a login).
      pull_request_bypassers = var.bypass_pull_request_actor_ids
    }
  }

  # Push restrictions — empty list disables direct pushes for everyone
  # (only the merge UI / merge_pull_request mutation can land changes).
  dynamic "restrict_pushes" {
    for_each = length(var.push_restrictions_actor_ids) > 0 ? [1] : []
    content {
      blocks_creations = var.restrict_pushes_blocks_creations
      push_allowances  = var.push_restrictions_actor_ids
    }
  }
}
