#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# deploy-state-backends.sh — Bootstrap Terraform state backends across accounts
#
# Closes #159 — TF-only state-backend bootstrap.
#
# What it does:
#   For each member account, assume OrganizationAccountAccessRole, run the
#   bootstrap stack at bootstrap/state-backend/, and create the S3 bucket +
#   DynamoDB lock table that terragrunt/root.hcl expects.
#
# Prerequisites:
#   - AWS CLI configured with management-account credentials.
#   - OpenTofu (preferred) or Terraform installed (>=1.5).
#   - jq installed.
#   - account.hcl files under terragrunt/<account>/ populated with real
#     account IDs (placeholders 000000000000 / 111111111111 / ... are still
#     present in some files — set ACCOUNT_IDS env var to override; see below).
#
# Usage:
#   ./scripts/deploy-state-backends.sh [plan|apply] [account-name]
#
#   Account name omitted -> all accounts in the map.
#   To override account IDs at runtime (until account.hcl files are filled in):
#     ACCOUNT_IDS='management=111122223333,dev=444455556666' \
#       ./scripts/deploy-state-backends.sh plan
#
# Examples:
#   ./scripts/deploy-state-backends.sh plan                  # plan all accounts
#   ./scripts/deploy-state-backends.sh apply dev             # apply dev only
#   ./scripts/deploy-state-backends.sh plan management       # plan management
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_DIR="$REPO_ROOT/bootstrap/state-backend"
MODULES_DIR="$REPO_ROOT/terraform/modules"
REGION="${REGION:-eu-west-1}"

ACTION="${1:-plan}"
TARGET_ACCOUNT="${2:-all}"

# --- ANSI colors -------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { printf '%b\n' "${GREEN}[INFO]${NC} $*"; }
log_warn()  { printf '%b\n' "${YELLOW}[WARN]${NC} $*"; }
log_error() { printf '%b\n' "${RED}[ERROR]${NC} $*"; }
log_step()  { printf '%b\n' "${BLUE}[STEP]${NC} $*"; }

# --- Default account map (can be overridden via ACCOUNT_IDS env var) --------
# These IDs are read from terragrunt/<account>/account.hcl when populated.
# Until then, you can override via ACCOUNT_IDS='name=id,name=id,...'.
declare -A ACCOUNTS=(
  ["management"]="000000000000"
  ["network"]="555555555555"
  ["dev"]="111111111111"
  ["staging"]="222222222222"
  ["prod"]="333333333333"
  ["dr"]="666666666666"
)

# Optional override via env var: ACCOUNT_IDS='management=111122223333,dev=444455556666'
if [[ -n "${ACCOUNT_IDS:-}" ]]; then
  IFS=',' read -ra OVERRIDES <<< "$ACCOUNT_IDS"
  for kv in "${OVERRIDES[@]}"; do
    name="${kv%%=*}"
    id="${kv##*=}"
    if [[ -n "$name" && -n "$id" ]]; then
      ACCOUNTS["$name"]="$id"
    fi
  done
fi

# --- Detect terraform binary ------------------------------------------------
TF_BIN=""
if command -v tofu &>/dev/null; then
  TF_BIN="tofu"
elif command -v terraform &>/dev/null; then
  TF_BIN="terraform"
else
  log_error "Neither tofu nor terraform found in PATH"
  exit 1
fi
log_info "Using: $TF_BIN"

# --- Prereqs ----------------------------------------------------------------
for cmd in jq aws; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "$cmd is required."
    exit 1
  fi
done

if [[ "$ACTION" != "plan" && "$ACTION" != "apply" ]]; then
  log_error "Action must be 'plan' or 'apply'. Got: $ACTION"
  echo "Usage: $0 [plan|apply] [account-name]"
  exit 1
fi

# --- Verify management-account access ---------------------------------------
log_info "Verifying caller identity..."
CALLER_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text 2>&1)
log_info "Authenticated as account: $CALLER_ACCOUNT"

EXPECTED_MGMT="${ACCOUNTS[management]:-}"
if [[ -n "$EXPECTED_MGMT" && "$EXPECTED_MGMT" != "000000000000" && "$CALLER_ACCOUNT" != "$EXPECTED_MGMT" ]]; then
  log_warn "Caller is $CALLER_ACCOUNT but the configured management account is $EXPECTED_MGMT."
  log_warn "Continuing — but role assumption from a non-management account requires extra trust on OrganizationAccountAccessRole."
fi

# --- Helpers ----------------------------------------------------------------
assume_role() {
  local account_id="$1"
  local account_name="$2"
  local role_arn="arn:aws:iam::${account_id}:role/OrganizationAccountAccessRole"

  log_info "Assuming role in $account_name ($account_id)..."

  local creds
  if ! creds=$(aws sts assume-role \
      --role-arn "$role_arn" \
      --role-session-name "state-backend-deploy-${account_name}" \
      --duration-seconds 3600 \
      --output json 2>&1); then
    log_error "Failed to assume role in $account_name ($account_id):"
    log_error "$creds"
    log_error "Ensure OrganizationAccountAccessRole exists and trusts the management account."
    return 1
  fi

  AWS_ACCESS_KEY_ID=$(echo "$creds" | jq -r '.Credentials.AccessKeyId')
  AWS_SECRET_ACCESS_KEY=$(echo "$creds" | jq -r '.Credentials.SecretAccessKey')
  AWS_SESSION_TOKEN=$(echo "$creds" | jq -r '.Credentials.SessionToken')
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

  local verified
  verified=$(aws sts get-caller-identity --query "Account" --output text 2>&1)
  if [[ "$verified" != "$account_id" ]]; then
    log_error "Role assumption verification failed. Expected $account_id, got $verified"
    return 1
  fi
  log_info "Successfully assumed role in $account_name."
}

clear_role() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

deploy_account() {
  local account_name="$1"
  local account_id="$2"

  echo
  log_step "========================================"
  log_step "Account: $account_name ($account_id)"
  log_step "========================================"

  if [[ "$account_id" == "000000000000" || "$account_id" =~ ^.0+$ || "$account_id" == "111111111111" \
        || "$account_id" == "222222222222" || "$account_id" == "333333333333" \
        || "$account_id" == "555555555555" || "$account_id" == "666666666666" ]]; then
    log_warn "Placeholder account ID detected for $account_name ($account_id)."
    log_warn "Populate terragrunt/$account_name/account.hcl with the real ID, or pass via ACCOUNT_IDS=..."
    log_warn "Skipping."
    return 0
  fi

  if ! assume_role "$account_id" "$account_name"; then
    return 1
  fi

  local bucket_name="tfstate-${account_name}-${REGION}"
  if aws s3api head-bucket --bucket "$bucket_name" &>/dev/null; then
    log_warn "Bucket $bucket_name already exists — running plan/apply will be a no-op."
  fi

  local work_dir
  work_dir="$(mktemp -d "/tmp/state-backend-${account_name}.XXXXXX")"
  trap 'rm -rf "$work_dir"' RETURN

  cp -R "$BOOTSTRAP_DIR/." "$work_dir/"
  ln -sfn "$MODULES_DIR" "$work_dir/modules"

  # Rewrite the module source so it resolves inside the temp dir without the
  # `../../terraform/modules/` relative path.
  sed -i.bak \
      -e 's|source = "../../terraform/modules/state-backend"|source = "./modules/state-backend"|' \
      "$work_dir/main.tf"
  rm -f "$work_dir/main.tf.bak"

  pushd "$work_dir" >/dev/null

  log_info "Initializing $TF_BIN..."
  $TF_BIN init -input=false -no-color | tail -5

  case "$ACTION" in
    plan)
      log_info "Planning state backend for $account_name..."
      $TF_BIN plan \
        -var="account_name=${account_name}" \
        -var="aws_region=${REGION}" \
        -input=false -no-color
      ;;
    apply)
      log_info "Applying state backend for $account_name..."
      $TF_BIN apply \
        -var="account_name=${account_name}" \
        -var="aws_region=${REGION}" \
        -input=false -no-color -auto-approve

      log_info "State backend deployed for $account_name:"
      log_info "  Bucket: $bucket_name"
      log_info "  Table:  terraform-locks-$account_name"
      ;;
  esac

  popd >/dev/null
  clear_role
}

# --- Main -------------------------------------------------------------------
echo
echo "============================================"
echo "  State Backend Deployment — $ACTION"
echo "  Region: $REGION"
echo "============================================"
echo

FAILED_ACCOUNTS=()
SUCCESS_COUNT=0

if [[ "$TARGET_ACCOUNT" == "all" ]]; then
  # Sort for deterministic ordering: management first, then alphabetical.
  ORDERED=("management")
  for name in $(printf '%s\n' "${!ACCOUNTS[@]}" | sort); do
    [[ "$name" == "management" ]] && continue
    ORDERED+=("$name")
  done

  for name in "${ORDERED[@]}"; do
    id="${ACCOUNTS[$name]}"
    if deploy_account "$name" "$id"; then
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
      FAILED_ACCOUNTS+=("$name")
    fi
  done
else
  if [[ -z "${ACCOUNTS[$TARGET_ACCOUNT]+x}" ]]; then
    log_error "Unknown account: $TARGET_ACCOUNT"
    log_error "Valid accounts: ${!ACCOUNTS[*]}"
    exit 1
  fi
  if deploy_account "$TARGET_ACCOUNT" "${ACCOUNTS[$TARGET_ACCOUNT]}"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    FAILED_ACCOUNTS+=("$TARGET_ACCOUNT")
  fi
fi

# --- Summary ----------------------------------------------------------------
echo
echo "============================================"
echo "  Deployment Summary"
echo "============================================"
echo
log_info "Successful: $SUCCESS_COUNT"
if [[ ${#FAILED_ACCOUNTS[@]} -gt 0 ]]; then
  log_error "Failed: ${FAILED_ACCOUNTS[*]}"
  exit 1
else
  log_info "All accounts processed successfully."
fi

if [[ "$ACTION" == "plan" ]]; then
  echo
  echo "To apply, run:"
  echo "  ./scripts/deploy-state-backends.sh apply [account-name]"
fi
