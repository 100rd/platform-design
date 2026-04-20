#!/usr/bin/env bash
##############################################################################
# detect-drift.sh — Infrastructure drift detection for Terragrunt environments
#
# Runs terraform plan on every Terragrunt unit in the specified environment.
# Parses plan output to detect infrastructure drift.
# Generates a structured JSON report.
#
# Usage:
#   ./scripts/detect-drift.sh --environment <env> [OPTIONS]
#
# Options:
#   --environment ENV     Terragrunt environment directory (dev|staging|prod|network|...)
#   --report-file FILE    Write JSON report to this file (default: /tmp/drift-report.json)
#   --report-format FMT   Output format: json|text (default: text)
#   --timeout SECONDS     Timeout per unit plan in seconds (default: 300)
#   --help                Show this help message
#
# Exit codes:
#   0  — No drift detected (or all units skipped)
#   1  — Drift detected in one or more units
#   2  — Script error (bad arguments, missing tools, etc.)
#
##############################################################################

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants & defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENVIRONMENT=""
REPORT_FILE="/tmp/drift-report.json"
REPORT_FORMAT="text"
PLAN_TIMEOUT=300

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
fi

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*" >&2; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*" >&2; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_drift()   { echo -e "${RED}[DRIFT]${NC} $*" >&2; }
log_section() { echo -e "\n${CYAN}=== $* ===${NC}" >&2; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
show_help() {
  cat <<EOF
detect-drift.sh — Infrastructure drift detection

Usage:
  ./scripts/detect-drift.sh --environment <env> [OPTIONS]

Options:
  --environment ENV     Terragrunt environment (dev|staging|prod|network|...)
  --report-file FILE    JSON report output path (default: /tmp/drift-report.json)
  --report-format FMT   Output format: json|text (default: text)
  --timeout SECONDS     Per-unit plan timeout in seconds (default: 300)
  --help                Show this help

Exit codes:
  0  No drift detected
  1  Drift detected
  2  Script error

Examples:
  ./scripts/detect-drift.sh --environment dev
  ./scripts/detect-drift.sh --environment prod --report-file /tmp/prod-drift.json --report-format json
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --environment)
        ENVIRONMENT="$2"; shift 2 ;;
      --report-file)
        REPORT_FILE="$2"; shift 2 ;;
      --report-format)
        REPORT_FORMAT="$2"; shift 2 ;;
      --timeout)
        PLAN_TIMEOUT="$2"; shift 2 ;;
      --help)
        show_help; exit 0 ;;
      *)
        log_error "Unknown argument: $1"
        show_help
        exit 2 ;;
    esac
  done

  if [ -z "${ENVIRONMENT}" ]; then
    log_error "--environment is required"
    show_help
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
check_prereqs() {
  local missing=()
  for tool in terraform terragrunt jq; do
    if ! command -v "${tool}" &>/dev/null; then
      missing+=("${tool}")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing required tools: ${missing[*]}"
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Discover all Terragrunt units under the given environment directory.
# A unit is a directory that contains a terragrunt.hcl file.
# ---------------------------------------------------------------------------
discover_units() {
  local env_dir="${PROJECT_DIR}/terragrunt/${ENVIRONMENT}"

  if [ ! -d "${env_dir}" ]; then
    log_error "Environment directory not found: ${env_dir}"
    exit 2
  fi

  find "${env_dir}" -name "terragrunt.hcl" \
    | xargs -I{} dirname {} \
    | sort
}

# ---------------------------------------------------------------------------
# Run terraform plan on a single unit.
# Writes plan output to a temp file.
# Returns:
#   0 — no changes (no drift)
#   1 — has changes (drift detected)
#   2 — plan failed (error)
# ---------------------------------------------------------------------------
plan_unit() {
  local unit_path="$1"
  local plan_output_file="$2"
  local unit_name
  unit_name=$(echo "${unit_path}" | sed "s|${PROJECT_DIR}/||")

  log_info "Planning: ${unit_name}"

  # Run init (quiet)
  if ! timeout "${PLAN_TIMEOUT}" terragrunt init \
      --non-interactive \
      --terragrunt-no-auto-init=false \
      -no-color \
      2>&1 | tail -3 >/dev/null; then
    log_warn "Init failed for ${unit_name} — skipping"
    echo "INIT_FAILED" > "${plan_output_file}"
    return 2
  fi

  # Run plan and capture output
  set +e
  timeout "${PLAN_TIMEOUT}" terragrunt plan \
    -no-color \
    -detailed-exitcode \
    2>&1 | tee "${plan_output_file}"
  local plan_exit=${PIPESTATUS[0]}
  set -e

  # terraform plan -detailed-exitcode:
  #   0 — no changes
  #   1 — error
  #   2 — changes present (drift)
  return ${plan_exit}
}

# ---------------------------------------------------------------------------
# Parse terraform plan output to extract changed resources.
# Returns JSON array of {action, address} objects.
# ---------------------------------------------------------------------------
parse_changed_resources() {
  local plan_file="$1"

  if [ ! -f "${plan_file}" ] || [ ! -s "${plan_file}" ]; then
    echo "[]"
    return
  fi

  # Extract resource change lines from plan output.
  # Matches patterns like:
  #   # aws_instance.web will be updated in-place
  #   # aws_security_group.main must be replaced
  #   # aws_s3_bucket.logs will be destroyed
  #   # module.eks.aws_iam_role.node will be created
  python3 - <<'PYEOF' "${plan_file}"
import sys, json, re

plan_file = sys.argv[1]
resources = []

action_map = {
    'will be created': 'create',
    'will be updated in-place': 'update',
    'will be destroyed': 'destroy',
    'must be replaced': 'replace',
    'will be replaced, as requested': 'replace',
    'is tainted, so must be replaced': 'replace',
    'will be read during apply': 'read',
}

with open(plan_file) as f:
    for line in f:
        line = line.rstrip()
        # Match resource change annotations
        m = re.match(r'\s*#\s+([\w.\[\]"-]+)\s+(.*)', line)
        if not m:
            continue
        address = m.group(1)
        rest = m.group(2).strip()
        action = None
        for pattern, act in action_map.items():
            if pattern in rest:
                action = act
                break
        if action:
            resources.append({'action': action, 'address': address})

print(json.dumps(resources))
PYEOF
}

# ---------------------------------------------------------------------------
# Count resource change types from terraform plan output.
# Returns JSON: {to_add, to_change, to_destroy}
# ---------------------------------------------------------------------------
parse_change_counts() {
  local plan_file="$1"

  if [ ! -f "${plan_file}" ]; then
    echo '{"to_add":0,"to_change":0,"to_destroy":0}'
    return
  fi

  # Match the summary line: "Plan: X to add, Y to change, Z to destroy."
  local summary
  summary=$(grep -E 'Plan: [0-9]+ to add' "${plan_file}" | tail -1 || echo "")

  if [ -z "${summary}" ]; then
    echo '{"to_add":0,"to_change":0,"to_destroy":0}'
    return
  fi

  local to_add to_change to_destroy
  to_add=$(echo "${summary}"    | grep -oP '\d+ to add'     | grep -oP '\d+' || echo 0)
  to_change=$(echo "${summary}" | grep -oP '\d+ to change'  | grep -oP '\d+' || echo 0)
  to_destroy=$(echo "${summary}"| grep -oP '\d+ to destroy' | grep -oP '\d+' || echo 0)

  printf '{"to_add":%d,"to_change":%d,"to_destroy":%d}' \
    "${to_add:-0}" "${to_change:-0}" "${to_destroy:-0}"
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"
  check_prereqs

  log_section "Drift Detection: ${ENVIRONMENT}"
  log_info "Project dir : ${PROJECT_DIR}"
  log_info "Report file : ${REPORT_FILE}"
  log_info "Started at  : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # Ensure report directory exists
  mkdir -p "$(dirname "${REPORT_FILE}")"

  # Discover units
  local units
  mapfile -t units < <(discover_units)

  if [ ${#units[@]} -eq 0 ]; then
    log_warn "No Terragrunt units found in environment: ${ENVIRONMENT}"
    echo "{\"environment\":\"${ENVIRONMENT}\",\"status\":\"clean\",\"reason\":\"no units found\",\"units\":[]}" \
      > "${REPORT_FILE}"
    exit 0
  fi

  log_info "Found ${#units[@]} unit(s) to check"

  # Results accumulator (JSON lines, assembled at the end)
  local unit_results=()
  local drift_count=0
  local error_count=0
  local clean_count=0

  # Temp directory for plan outputs
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "${tmp_dir}"' EXIT

  # ---------------------------------------------------------------------------
  # Process each unit
  # ---------------------------------------------------------------------------
  for unit in "${units[@]}"; do
    local unit_name
    unit_name=$(echo "${unit}" | sed "s|${PROJECT_DIR}/||")

    local plan_output="${tmp_dir}/plan_$(echo "${unit_name}" | tr '/' '_').txt"

    # Save cwd and switch to unit directory
    local orig_dir="${PWD}"
    cd "${unit}"

    # Run plan
    set +e
    plan_unit "${unit}" "${plan_output}"
    local exit_code=$?
    set -e

    cd "${orig_dir}"

    local status drift_detected changed_resources change_counts
    changed_resources="[]"
    change_counts='{"to_add":0,"to_change":0,"to_destroy":0}'

    case ${exit_code} in
      0)
        status="clean"
        drift_detected="false"
        log_ok "${unit_name}: no drift"
        (( clean_count++ )) || true
        ;;
      2)
        status="drift"
        drift_detected="true"
        changed_resources=$(parse_changed_resources "${plan_output}")
        change_counts=$(parse_change_counts "${plan_output}")
        log_drift "${unit_name}: drift detected"
        (( drift_count++ )) || true
        ;;
      *)
        status="error"
        drift_detected="false"
        log_warn "${unit_name}: plan failed or timed out (exit ${exit_code})"
        (( error_count++ )) || true
        ;;
    esac

    # Build unit result JSON
    unit_results+=("$(jq -n \
      --arg unit "${unit_name}" \
      --arg status "${status}" \
      --argjson drift "${drift_detected}" \
      --argjson changes "${change_counts}" \
      --argjson resources "${changed_resources}" \
      '{unit:$unit, status:$status, drift_detected:$drift, changes:$changes, changed_resources:$resources}'
    )")
  done

  # ---------------------------------------------------------------------------
  # Assemble final report
  # ---------------------------------------------------------------------------
  local overall_status
  if [ ${drift_count} -gt 0 ]; then
    overall_status="drift"
  elif [ ${error_count} -gt 0 ]; then
    overall_status="error"
  else
    overall_status="clean"
  fi

  local units_json
  units_json=$(printf '%s\n' "${unit_results[@]}" | jq -s '.')

  jq -n \
    --arg env "${ENVIRONMENT}" \
    --arg status "${overall_status}" \
    --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --argjson units "${units_json}" \
    --argjson summary "$(jq -n \
      --argjson total ${#units[@]} \
      --argjson drift ${drift_count} \
      --argjson clean ${clean_count} \
      --argjson error ${error_count} \
      '{total:$total,drift:$drift,clean:$clean,error:$error}')" \
    '{
      environment: $env,
      status: $status,
      timestamp: $timestamp,
      summary: $summary,
      units: $units
    }' > "${REPORT_FILE}"

  # ---------------------------------------------------------------------------
  # Print human-readable summary
  # ---------------------------------------------------------------------------
  log_section "Summary: ${ENVIRONMENT}"
  log_info "Total units : ${#units[@]}"
  log_ok   "Clean       : ${clean_count}"

  if [ ${drift_count} -gt 0 ]; then
    log_drift "Drifted     : ${drift_count}"
  else
    log_ok   "Drifted     : 0"
  fi

  if [ ${error_count} -gt 0 ]; then
    log_warn "Errors      : ${error_count}"
  fi

  log_info "Report      : ${REPORT_FILE}"
  log_info "Completed at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  if [ ${drift_count} -gt 0 ]; then
    log_drift "DRIFT DETECTED — exit code 1"
    exit 1
  else
    log_ok "No drift detected — exit code 0"
    exit 0
  fi
}

main "$@"
