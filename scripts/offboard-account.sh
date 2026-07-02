#!/usr/bin/env bash
# =============================================================================
# offboard-account.sh — Move an AWS account to the Suspended OU
# =============================================================================
#
# PURPOSE:
#   Safely offboard (quarantine) an AWS account by moving it to the Suspended
#   OU. The deny-all SCP on the Suspended OU prevents all API calls except
#   from OrganizationAccountAccessRole. CloudTrail and Config continue to run
#   (they use service principals, not user/role ARNs).
#
# USAGE:
#   ./scripts/offboard-account.sh <account-id> <reason> [--dry-run]
#
# PREREQUISITES:
#   - AWS CLI configured with management account credentials (AdministratorAccess)
#   - Organization admin privileges (organizations:MoveAccount)
#   - Approval from 2 platform admins (4-eyes principle, see break-glass doc)
#
# EXAMPLES:
#   # Dry run (shows what would happen):
#   ./scripts/offboard-account.sh 123456789012 "project ended" --dry-run
#
#   # Actual offboarding:
#   ./scripts/offboard-account.sh 123456789012 "security incident - ticket SEC-456"
#
# WHAT THIS SCRIPT DOES:
#   1. Validates the account exists and is not already in Suspended OU
#   2. Shows current OU placement and account details
#   3. Requires confirmation (unless --dry-run)
#   4. Moves the account to the Suspended OU
#   5. Verifies the move completed
#   6. Logs the action to stdout for CloudTrail capture
#
# REVERTING:
#   To move an account OUT of Suspended OU, run:
#   aws organizations move-account --account-id <id> \
#     --source-parent-id <SUSPENDED_OU_ID> \
#     --destination-parent-id <TARGET_OU_ID>
#   Then re-run Terraform to restore normal SCP coverage.
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SUSPENDED_OU_NAME="Suspended"
REGION="eu-west-1"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <account-id> <reason> [--dry-run]"
  echo ""
  echo "  account-id   12-digit AWS account ID to offboard"
  echo "  reason       Reason for offboarding (quoted string, included in logs)"
  echo "  --dry-run    Show what would happen without making changes"
  exit 1
fi

ACCOUNT_ID="$1"
REASON="$2"
DRY_RUN=false

if [[ ${3:-} == "--dry-run" ]]; then
  DRY_RUN=true
fi

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
}

error() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || error "Required command not found: $1. Install AWS CLI."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

require_command aws
require_command jq

log "=== Account Offboarding Script ==="
log "Account ID : ${ACCOUNT_ID}"
log "Reason     : ${REASON}"
log "Dry run    : ${DRY_RUN}"
log ""

# Validate account ID format
if [[ ! "${ACCOUNT_ID}" =~ ^[0-9]{12}$ ]]; then
  error "Invalid account ID format: ${ACCOUNT_ID} (must be 12 digits)"
fi

# Get management account identity
CALLER=$(aws sts get-caller-identity --output json)
CALLER_ARN=$(echo "${CALLER}" | jq -r '.Arn')
MGMT_ACCOUNT=$(echo "${CALLER}" | jq -r '.Account')

log "Caller     : ${CALLER_ARN}"
log "Mgmt acct  : ${MGMT_ACCOUNT}"
log ""

# Fetch account details
log "Fetching account details..."
ACCOUNT_INFO=$(aws organizations describe-account --account-id "${ACCOUNT_ID}" --output json) \
  || error "Account ${ACCOUNT_ID} not found or not accessible from this account."

ACCOUNT_NAME=$(echo "${ACCOUNT_INFO}" | jq -r '.Account.Name')
ACCOUNT_EMAIL=$(echo "${ACCOUNT_INFO}" | jq -r '.Account.Email')
ACCOUNT_STATUS=$(echo "${ACCOUNT_INFO}" | jq -r '.Account.Status')

log "Account name   : ${ACCOUNT_NAME}"
log "Account email  : ${ACCOUNT_EMAIL}"
log "Account status : ${ACCOUNT_STATUS}"

if [[ "${ACCOUNT_STATUS}" != "ACTIVE" ]]; then
  error "Account ${ACCOUNT_ID} is not ACTIVE (status: ${ACCOUNT_STATUS}). Cannot offboard."
fi

# Fetch current OU placement
PARENTS=$(aws organizations list-parents --child-id "${ACCOUNT_ID}" --output json)
CURRENT_PARENT_ID=$(echo "${PARENTS}" | jq -r '.Parents[0].Id')
CURRENT_PARENT_TYPE=$(echo "${PARENTS}" | jq -r '.Parents[0].Type')

if [[ "${CURRENT_PARENT_TYPE}" == "ORGANIZATIONAL_UNIT" ]]; then
  CURRENT_OU_INFO=$(aws organizations describe-organizational-unit \
    --organizational-unit-id "${CURRENT_PARENT_ID}" --output json)
  CURRENT_OU_NAME=$(echo "${CURRENT_OU_INFO}" | jq -r '.OrganizationalUnit.Name')
else
  CURRENT_OU_NAME="Root"
fi

log ""
log "Current parent : ${CURRENT_OU_NAME} (${CURRENT_PARENT_ID})"

# Check if already in Suspended OU
if [[ "${CURRENT_OU_NAME}" == "${SUSPENDED_OU_NAME}" ]]; then
  log "Account is already in the ${SUSPENDED_OU_NAME} OU. No action needed."
  exit 0
fi

# Find the Suspended OU ID
log ""
log "Looking up Suspended OU..."
ORG_ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
CHILD_OUS=$(aws organizations list-organizational-units-for-parent \
  --parent-id "${ORG_ROOT_ID}" --output json)

SUSPENDED_OU_ID=$(echo "${CHILD_OUS}" | \
  jq -r ".OrganizationalUnits[] | select(.Name == \"${SUSPENDED_OU_NAME}\") | .Id")

if [[ -z "${SUSPENDED_OU_ID}" ]]; then
  error "Suspended OU not found under root ${ORG_ROOT_ID}. Has Issue #71 been applied?"
fi

log "Suspended OU ID: ${SUSPENDED_OU_ID}"

# Show summary and confirm
log ""
log "=== SUMMARY ==="
log "Will move account ${ACCOUNT_ID} (${ACCOUNT_NAME})"
log "  FROM: ${CURRENT_OU_NAME} (${CURRENT_PARENT_ID})"
log "  TO  : ${SUSPENDED_OU_NAME} (${SUSPENDED_OU_ID})"
log "  WHY : ${REASON}"
log ""
log "EFFECT: The deny-all SCP will immediately block all API calls in the account"
log "        except from OrganizationAccountAccessRole. CloudTrail and Config"
log "        continue to run (they use service principals)."
log ""

if [[ "${DRY_RUN}" == "true" ]]; then
  log "[DRY RUN] No changes made. Remove --dry-run to execute."
  exit 0
fi

# Require explicit confirmation
echo -n "Type 'CONFIRM' to proceed with account offboarding: "
read -r CONFIRMATION

if [[ "${CONFIRMATION}" != "CONFIRM" ]]; then
  log "Confirmation not received. Aborting."
  exit 1
fi

# Execute the move
log ""
log "Moving account to Suspended OU..."
aws organizations move-account \
  --account-id "${ACCOUNT_ID}" \
  --source-parent-id "${CURRENT_PARENT_ID}" \
  --destination-parent-id "${SUSPENDED_OU_ID}"

# Verify the move
log "Verifying placement..."
sleep 2

NEW_PARENTS=$(aws organizations list-parents --child-id "${ACCOUNT_ID}" --output json)
NEW_PARENT_ID=$(echo "${NEW_PARENTS}" | jq -r '.Parents[0].Id')

if [[ "${NEW_PARENT_ID}" == "${SUSPENDED_OU_ID}" ]]; then
  log ""
  log "SUCCESS: Account ${ACCOUNT_ID} (${ACCOUNT_NAME}) is now in the Suspended OU."
  log "         The deny-all SCP is now enforced for this account."
  log ""
  log "NEXT STEPS:"
  log "  1. Notify the account owner(s) of the suspension"
  log "  2. Create a ticket to track account closure timeline"
  log "  3. After 30 days, close the account via AWS console if not reinstated"
  log "  4. Update Terraform state: remove the account resource from organizations module"
else
  error "Move may not have completed. New parent is ${NEW_PARENT_ID}, expected ${SUSPENDED_OU_ID}."
fi
