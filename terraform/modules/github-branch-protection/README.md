# Module: `github-branch-protection`

GitHub branch-protection rule managed as Terraform. One rule per repo /
branch-pattern. Closes #177.

## Why IaC for this

Branch protection rules are a critical control plane: they decide who can
push to `main`, what checks must pass, whether admins can bypass, etc. A
console-clicked rule is invisible to the audit trail and easy to drift
silently (someone disables a check during a hotfix and forgets). IaC
makes the rule reviewable, diff-able, and atomic-rollback-able.

## Inputs

The full list lives in `variables.tf`. Defaults are tuned for a
canonical "protect main on a CI-first repo":

- `enforce_admins = true` — admins can't bypass.
- `allows_deletions = false`, `allows_force_pushes = false`.
- `require_conversation_resolution = true`.
- `dismiss_stale_reviews = true`, `required_approving_review_count = 1`.
- `strict_status_checks = true` (branch must be up-to-date).
- `bypass_pull_request_actor_ids = []` (no bypassers).
- `push_restrictions_actor_ids = []` (no direct pushes for anyone).

The most-tweaked input is `required_status_checks` — list the workflow
job names that must pass.

## Bypass list management

Each entry in `bypass_pull_request_actor_ids` and
`push_restrictions_actor_ids` is a GitHub **node ID** (base64-ish string
like `MDQ6VXNlcjEyMzQ1`), not a login. Lookup tools:

```bash
# User node ID
gh api graphql -f query='query{user(login:"<login>"){id}}'
# Team node ID
gh api graphql -f query='query{organization(login:"<org>"){team(slug:"<team>"){id}}}'
```

Document EVERY entry inline in the consuming Terragrunt unit's input map
— bypass is a security-sensitive privilege.

## Provider

The module declares `integrations/github ~> 6.0`. The provider's `owner`
is configured at the provider level (in the consuming root or via
`GITHUB_TOKEN` / `GITHUB_OWNER` env vars).

## Required status checks for this repo

Standard set for `100rd/platform-design::main`:

```hcl
required_status_checks = [
  "HCL Format Check",
  "Validate Catalog Units",
  "Detect Terragrunt roots",
  "Detect changed modules",
  "gitleaks",
  "kubeconform",
  "OPA Policy Status",
  "Plan Status",
]
```

Per-PR matrix checks (`OPA <module>`, `Plan <module>`) are excluded
because their names vary by changed-module set; the umbrella `OPA Policy
Status` and `Plan Status` jobs aggregate the matrix into a stable name.

## Cost

Zero — GitHub branch protection is free.

## Rollback

`terraform destroy` against the consuming unit removes the rule, returning
the branch to "no protection".
