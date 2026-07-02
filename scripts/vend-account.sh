#!/usr/bin/env bash
# =============================================================================
# vend-account.sh — Account Vending Automation
# =============================================================================
#
# PURPOSE:
#   Automates the end-to-end provisioning of a new AWS account from a YAML
#   request file. Replaces the 8-step manual process with a single command.
#
# USAGE:
#   ./scripts/vend-account.sh --request bootstrap/account-requests/<name>.yaml [--dry-run]
#
# WHAT THIS SCRIPT DOES:
#   1.  Validates the request YAML (all required fields present)
#   2.  Confirms the plan with the operator before making changes
#   3.  Adds the account resource to modules/organizations/main.tf
#   4.  Adds the account output to modules/organizations/outputs.tf
#   5.  Creates the Terragrunt account directory structure:
#         <account-name>/account.hcl
#         <account-name>/eu-west-1/budgets/terragrunt.hcl
#         <account-name>/eu-west-1/github-oidc/terragrunt.hcl  (if enabled)
#   6.  Prints next steps (organizations apply, state backend bootstrap, etc.)
#
# PREREQUISITES:
#   - AWS CLI configured with management account credentials (AdministratorAccess)
#   - yq v4 installed: https://github.com/mikefarah/yq
#   - git repository is clean (no uncommitted changes) on a feature branch
#
# EXAMPLES:
#   # Dry run — shows every change without touching files:
#   ./scripts/vend-account.sh --request bootstrap/account-requests/analytics.yaml --dry-run
#
#   # Full execution:
#   ./scripts/vend-account.sh --request bootstrap/account-requests/analytics.yaml
#
# ISSUE: #70
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REPO_ROOT="$(git rev-parse --show-toplevel)"
ORG_MAIN="${REPO_ROOT}/modules/organizations/main.tf"
ORG_OUTPUTS="${REPO_ROOT}/modules/organizations/outputs.tf"
REGION="eu-west-1"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }
warn() { echo "[WARN]  $*" >&2; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || error "Required command not found: $1"
}

# Read a field from YAML using yq (v4 syntax).
# Usage: yaml_get <file> <path>
yaml_get() {
  yq e "$2" "$1" 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

REQUEST_FILE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request)
      REQUEST_FILE="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    *)
      error "Unknown argument: $1. Usage: $0 --request <file> [--dry-run]" ;;
  esac
done

[[ -z "${REQUEST_FILE}" ]] && error "Missing --request <file>"
[[ -f "${REQUEST_FILE}" ]] || error "Request file not found: ${REQUEST_FILE}"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

require_command aws
require_command yq
require_command git

log "=== Account Vending Script ==="
log "Request file : ${REQUEST_FILE}"
log "Dry run      : ${DRY_RUN}"
log ""

# Ensure we're on a feature branch, not main/master
CURRENT_BRANCH=$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD)
if [[ "${CURRENT_BRANCH}" == "main" || "${CURRENT_BRANCH}" == "master" ]]; then
  error "You are on the '${CURRENT_BRANCH}' branch. Create a feature branch first:
  git checkout -b feature/vend-account-<name>"
fi

# ---------------------------------------------------------------------------
# Parse request YAML
# ---------------------------------------------------------------------------

ACCOUNT_NAME=$(yaml_get "${REQUEST_FILE}" '.account_name')
ACCOUNT_DISPLAY=$(yaml_get "${REQUEST_FILE}" '.account_display_name')
ACCOUNT_EMAIL=$(yaml_get "${REQUEST_FILE}" '.account_email')
OU=$(yaml_get "${REQUEST_FILE}" '.ou')
ENVIRONMENT=$(yaml_get "${REQUEST_FILE}" '.environment')
OWNER_TEAM=$(yaml_get "${REQUEST_FILE}" '.owner_team')
COST_CENTER=$(yaml_get "${REQUEST_FILE}" '.cost_center')
MONTHLY_BUDGET=$(yaml_get "${REQUEST_FILE}" '.monthly_budget_usd')
ENABLE_OIDC=$(yaml_get "${REQUEST_FILE}" '.enable_github_oidc')
ENABLE_STATE=$(yaml_get "${REQUEST_FILE}" '.enable_state_backend')
REQUESTED_BY=$(yaml_get "${REQUEST_FILE}" '.requested_by')
TICKET=$(yaml_get "${REQUEST_FILE}" '.ticket')

# Validate required fields
for field_name in ACCOUNT_NAME ACCOUNT_EMAIL OU ENVIRONMENT OWNER_TEAM COST_CENTER MONTHLY_BUDGET REQUESTED_BY TICKET; do
  field_val="${!field_name}"
  if [[ -z "${field_val}" || "${field_val}" == "REQUIRED" || "${field_val}" == "null" ]]; then
    error "Required field '${field_name,,}' is missing or still set to REQUIRED in ${REQUEST_FILE}"
  fi
done

# Validate OU
case "${OU}" in
  workloads|sandbox|infrastructure) ;;
  *) error "Invalid ou '${OU}'. Allowed values: workloads | sandbox | infrastructure" ;;
esac

# Validate environment
case "${ENVIRONMENT}" in
  development|staging|production|sandbox|shared) ;;
  *) error "Invalid environment '${ENVIRONMENT}'. Allowed: development|staging|production|sandbox|shared" ;;
esac

# Derive terraform resource name (hyphens → underscores)
TF_RESOURCE_NAME="${ACCOUNT_NAME//-/_}"

# Account directory path
ACCOUNT_DIR="${REPO_ROOT}/${ACCOUNT_NAME}"

# ---------------------------------------------------------------------------
# Plan output
# ---------------------------------------------------------------------------

log "=== PLAN ==="
log ""
log "Account name     : ${ACCOUNT_NAME}"
log "Display name     : ${ACCOUNT_DISPLAY}"
log "Email            : ${ACCOUNT_EMAIL}"
log "OU               : ${OU}"
log "Environment      : ${ENVIRONMENT}"
log "Owner team       : ${OWNER_TEAM}"
log "Cost center      : ${COST_CENTER}"
log "Monthly budget   : \$${MONTHLY_BUDGET}"
log "GitHub OIDC      : ${ENABLE_OIDC:-false}"
log "State backend    : ${ENABLE_STATE:-true}"
log "Requested by     : ${REQUESTED_BY}"
log "Ticket           : ${TICKET}"
log ""
log "Files to create/modify:"
log "  [M] ${ORG_MAIN}"
log "  [M] ${ORG_OUTPUTS}"
log "  [C] ${ACCOUNT_DIR}/account.hcl"
log "  [C] ${ACCOUNT_DIR}/${REGION}/budgets/terragrunt.hcl"
if [[ "${ENABLE_OIDC:-false}" == "true" ]]; then
  log "  [C] ${ACCOUNT_DIR}/${REGION}/github-oidc/terragrunt.hcl"
fi
log ""

if [[ "${DRY_RUN}" == "true" ]]; then
  log "[DRY RUN] No changes made. Remove --dry-run to execute."
  exit 0
fi

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------

echo -n "Type 'CONFIRM' to proceed with account vending: "
read -r CONFIRMATION
[[ "${CONFIRMATION}" == "CONFIRM" ]] || { log "Confirmation not received. Aborting."; exit 1; }
log ""

# ---------------------------------------------------------------------------
# Guard: check if account already exists in Terraform
# ---------------------------------------------------------------------------

if grep -q "aws_organizations_account\.${TF_RESOURCE_NAME}" "${ORG_MAIN}"; then
  error "Account resource 'aws_organizations_account.${TF_RESOURCE_NAME}' already exists in ${ORG_MAIN}. Aborting."
fi

if [[ -d "${ACCOUNT_DIR}" ]]; then
  error "Account directory already exists: ${ACCOUNT_DIR}. Aborting."
fi

# ---------------------------------------------------------------------------
# Step 1: Append account resource to modules/organizations/main.tf
# ---------------------------------------------------------------------------

log "Step 1: Appending account resource to organizations module..."

cat >> "${ORG_MAIN}" << TFBLOCK

# --- ${ACCOUNT_DISPLAY} account (${TICKET}) ---
# Provisioned by vend-account.sh — ${REQUESTED_BY} — $(date -u '+%Y-%m-%d')
resource "aws_organizations_account" "${TF_RESOURCE_NAME}" {
  name      = "\${var.project}-${ACCOUNT_NAME}"
  email     = "aws+${ACCOUNT_NAME}@\${var.account_email_domain}"
  parent_id = aws_organizations_organizational_unit.${OU}.id

  close_on_deletion          = false
  iam_user_access_to_billing = "ALLOW"

  tags = merge(var.tags, {
    Name        = "\${var.project}-${ACCOUNT_NAME}"
    Environment = "${ENVIRONMENT}"
    Owner       = "${OWNER_TEAM}"
    CostCenter  = "${COST_CENTER}"
    Ticket      = "${TICKET}"
  })

  lifecycle {
    ignore_changes = [email]
  }
}
TFBLOCK

log "  Done: account resource added."

# ---------------------------------------------------------------------------
# Step 2: Append output to modules/organizations/outputs.tf
# ---------------------------------------------------------------------------

log "Step 2: Appending account ID output to organizations outputs..."

# Read current outputs.tf so we can append before closing brace of member_account_ids
# Simpler: just append a new standalone output
cat >> "${ORG_OUTPUTS}" << TFOUT

output "account_id_${TF_RESOURCE_NAME}" {
  description = "Account ID of the ${ACCOUNT_DISPLAY} account"
  value       = aws_organizations_account.${TF_RESOURCE_NAME}.id
}
TFOUT

log "  Done: output added."

# ---------------------------------------------------------------------------
# Step 3: Create account directory structure
# ---------------------------------------------------------------------------

log "Step 3: Creating Terragrunt directory structure..."

mkdir -p "${ACCOUNT_DIR}/${REGION}/budgets"

# account.hcl
cat > "${ACCOUNT_DIR}/account.hcl" << HCL
# -----------------------------------------------------------------------------
# account.hcl — ${ACCOUNT_DISPLAY} (${OU^} OU)
# ${TICKET} — provisioned by vend-account.sh
#
# NOTE: aws_account_id is PLACEHOLDER until the account is created by applying
# management/eu-west-1/organizations. After apply:
#
#   cd management/eu-west-1/organizations
#   terragrunt output account_id_${TF_RESOURCE_NAME}
#   Then update aws_account_id below.
# -----------------------------------------------------------------------------

locals {
  account_name   = "${ACCOUNT_NAME}"
  aws_account_id = "PLACEHOLDER_${ACCOUNT_NAME^^//-/_}_ACCOUNT_ID"
  environment    = "${ENVIRONMENT}"

  # Tagging
  owner       = "${OWNER_TEAM}"
  cost_center = "${COST_CENTER}"

  # Account-specific settings
  enable_deletion_protection = $([ "${ENVIRONMENT}" == "production" ] && echo "true" || echo "false")
  log_retention_days         = $([ "${ENVIRONMENT}" == "production" ] && echo "90" || echo "30")

  # Budget cap
  monthly_budget_limit = "${MONTHLY_BUDGET}"
}
HCL

# budgets/terragrunt.hcl
cat > "${ACCOUNT_DIR}/${REGION}/budgets/terragrunt.hcl" << HCL
# -----------------------------------------------------------------------------
# ${ACCOUNT_NAME}/${REGION}/budgets/terragrunt.hcl
# AWS Budgets — \$${MONTHLY_BUDGET}/month cap
# ${TICKET}
# -----------------------------------------------------------------------------

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "\${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/budgets.hcl"
  expose = true
}

inputs = {
  monthly_budget_amount = "${MONTHLY_BUDGET}"

  alert_thresholds           = [50, 80, 100]
  forecasted_alert_threshold = 100

  notification_emails = [
    "platform-team@qbiq.ai",
  ]

  sns_topic_arns = []

  # Disabled: ce:* may be blocked by SCP in member accounts until SCPs are reviewed.
  enable_anomaly_detection = false
}
HCL

log "  Created: ${ACCOUNT_DIR}/account.hcl"
log "  Created: ${ACCOUNT_DIR}/${REGION}/budgets/terragrunt.hcl"

# Optional: GitHub OIDC
if [[ "${ENABLE_OIDC:-false}" == "true" ]]; then
  mkdir -p "${ACCOUNT_DIR}/${REGION}/github-oidc"

  cat > "${ACCOUNT_DIR}/${REGION}/github-oidc/terragrunt.hcl" << HCL
# -----------------------------------------------------------------------------
# ${ACCOUNT_NAME}/${REGION}/github-oidc/terragrunt.hcl
# GitHub Actions OIDC provider + Terraform CI/CD role
# ${TICKET}
# -----------------------------------------------------------------------------

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "\${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/github-oidc.hcl"
  expose = true
}

inputs = {}
HCL

  log "  Created: ${ACCOUNT_DIR}/${REGION}/github-oidc/terragrunt.hcl"
fi

# ---------------------------------------------------------------------------
# Step 4: Stage changes
# ---------------------------------------------------------------------------

log ""
log "Step 4: Staging changes..."

git -C "${REPO_ROOT}" add \
  "${ORG_MAIN}" \
  "${ORG_OUTPUTS}" \
  "${ACCOUNT_DIR}"

log "  Staged $(git -C "${REPO_ROOT}" diff --cached --name-only | wc -l | tr -d ' ') files."

# ---------------------------------------------------------------------------
# Summary + next steps
# ---------------------------------------------------------------------------

log ""
log "=== SUCCESS — Account Scaffolding Complete ==="
log ""
log "NEXT STEPS:"
log ""
log "  1. Review staged changes:"
log "       git diff --cached"
log ""
log "  2. Commit and push:"
log "       git commit -m 'feat: vend ${ACCOUNT_NAME} account (${TICKET})'"
log "       git push -u origin \$(git rev-parse --abbrev-ref HEAD)"
log ""
log "  3. Apply organizations to create the account (management account creds required):"
log "       cd management/eu-west-1/organizations"
log "       terragrunt plan"
log "       terragrunt apply"
log ""
log "  4. Get the real account ID and update ${ACCOUNT_DIR}/account.hcl:"
log "       terragrunt output account_id_${TF_RESOURCE_NAME}"
log "       # Replace PLACEHOLDER_${ACCOUNT_NAME^^//-/_}_ACCOUNT_ID"
log ""
log "  5. Bootstrap the Terraform state backend (assume OrganizationAccountAccessRole):"
log "       ACCOUNT_ID=<real-account-id>"
log "       aws cloudformation deploy \\"
log "         --stack-name terraform-state-backend \\"
log "         --template-file ${REPO_ROOT}/bootstrap/state-backend.yaml \\"
log "         --parameter-overrides ProjectName=qbiq AccountName=${ACCOUNT_NAME} AwsRegion=${REGION} \\"
log "         --profile <profile-assuming-into-\${ACCOUNT_ID}>"
log ""
log "  6. Apply budgets from the new account:"
log "       cd ${ACCOUNT_DIR}/${REGION}/budgets"
log "       terragrunt plan && terragrunt apply"
log ""

if [[ "${ENABLE_OIDC:-false}" == "true" ]]; then
  log "  7. Apply GitHub OIDC:"
  log "       cd ${ACCOUNT_DIR}/${REGION}/github-oidc"
  log "       terragrunt plan && terragrunt apply"
  log ""
fi

log "  8. Update SSO assignments in management/eu-west-1/sso/terragrunt.hcl"
log "     to add this account. Run: terragrunt plan && terragrunt apply"
log ""
log "  9. Open a PR, get review, merge, and close ${TICKET}."
log ""
