output "branch_protection_id" {
  description = "GitHub node ID of the branch protection rule."
  value       = github_branch_protection.this.id
}

output "repository" {
  description = "Repository the rule applies to."
  value       = var.repository
}

output "branch_pattern" {
  description = "Branch pattern the rule protects."
  value       = var.branch_pattern
}
