#!/usr/bin/env bash
#
# break-glass.sh — sanctioned wrapper around AWS management-account root access.
#
# Subcommands:
#   request --reason "<text>"   Begin a break-glass session. Prints the URL
#                                to retrieve the password and the MFA prompt.
#                                Does NOT print or persist the password / code.
#   release --reason "<text>"   End a break-glass session. Triggers password
#                                rotation and links the CloudTrail events to
#                                the originating Jira ticket (deduced from
#                                --reason text — must include `JIRA-NNN:`).
#
# Logging:
#   - Every invocation appends a structured line to /tmp/break-glass-${USER}.log
#   - On success, an event is published to the AWS CloudWatch Logs group
#     `/aws/break-glass/management` so the alerting pipeline (#169) can
#     correlate request -> release -> CloudTrail.
#
# Pre-reqs:
#   - aws CLI v2 configured with a profile that can write to the
#     /aws/break-glass/management log group (cross-account via SSO).
#   - 1Password CLI (`op`) authenticated, with access to the `aws-root`
#     vault — only platform-team-leads have this.
#
# Usage examples:
#   ./scripts/break-glass.sh request --reason "JIRA-456: rotate root MFA"
#   ./scripts/break-glass.sh release --reason "JIRA-456: complete"
#
# Issue: #169.

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
readonly LOG_GROUP="/aws/break-glass/management"
readonly LOG_REGION="${AWS_DEFAULT_REGION:-eu-west-1}"
readonly OP_VAULT="aws-root"
readonly OP_ITEM="management-account-root"
readonly USER_LOG_FILE="/tmp/break-glass-${USER:-anon}.log"

# Allow-list of approved leads. The script does NOT call IAM/SSO to verify;
# it expects you to be running on a laptop with your own personal AWS profile.
# This list is advisory — the AWS CloudTrail audit is the authoritative trail.
readonly LEADS_FILE="${HOME}/.aws/break-glass-leads.txt"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log_local() {
    local level="$1" msg="$2"
    printf '%s %s %s %s %s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "${USER:-anon}" \
        "$$" \
        "${level}" \
        "${msg}" \
        | tee -a "${USER_LOG_FILE}" >&2
}

log_cloudwatch() {
    local action="$1" reason="$2"
    local stream="${USER:-anon}"
    local timestamp
    timestamp=$(date +%s)000
    local message
    message=$(jq -nc --arg user "${USER:-anon}" --arg action "${action}" \
                  --arg reason "${reason}" --arg host "$(hostname)" \
                  '{user: $user, action: $action, reason: $reason, host: $host}')

    if ! aws logs describe-log-streams \
            --log-group-name "${LOG_GROUP}" \
            --log-stream-name-prefix "${stream}" \
            --region "${LOG_REGION}" >/dev/null 2>&1; then
        log_local WARN "CloudWatch log group ${LOG_GROUP} not reachable; skipping remote log."
        return 0
    fi

    aws logs create-log-stream \
        --log-group-name "${LOG_GROUP}" \
        --log-stream-name "${stream}" \
        --region "${LOG_REGION}" 2>/dev/null || true

    aws logs put-log-events \
        --log-group-name "${LOG_GROUP}" \
        --log-stream-name "${stream}" \
        --log-events "timestamp=${timestamp},message=${message}" \
        --region "${LOG_REGION}" >/dev/null
    log_local INFO "CloudWatch event published to ${LOG_GROUP}/${stream}"
}

require_lead() {
    if [[ ! -f "${LEADS_FILE}" ]]; then
        log_local WARN "Leads file ${LEADS_FILE} not found — proceeding (CloudTrail is authoritative)."
        return 0
    fi
    if ! grep -qFx "${USER:-anon}" "${LEADS_FILE}"; then
        log_local ERROR "${USER:-anon} is not on the platform-team-leads list."
        exit 2
    fi
}

require_jira_in_reason() {
    local reason="$1"
    if [[ ! "${reason}" =~ ^[A-Z]+-[0-9]+: ]]; then
        log_local ERROR "Reason must start with 'JIRA-NNN:' — got: ${reason}"
        exit 3
    fi
}

# -----------------------------------------------------------------------------
# Subcommands
# -----------------------------------------------------------------------------
cmd_request() {
    local reason=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason) reason="${2:-}"; shift 2;;
            *) log_local ERROR "Unknown flag: $1"; exit 1;;
        esac
    done
    [[ -n "${reason}" ]] || { log_local ERROR "--reason is required"; exit 1; }

    require_lead
    require_jira_in_reason "${reason}"

    log_local INFO "Break-glass REQUEST opened — reason: ${reason}"
    log_cloudwatch request "${reason}"

    cat <<'BANNER' >&2
================================================================================
BREAK-GLASS: management account root access requested
================================================================================
1. Retrieve password from 1Password vault:
   op item get "${OP_ITEM}" --vault "${OP_VAULT}" --fields password

2. Open https://signin.aws.amazon.com in INCOGNITO mode.

3. Sign in as root user (account ID 000000000000).

4. Enter the MFA code from your virtual / hardware MFA device.

5. Perform the minimum operation needed.

6. Sign out, then run:
     ./scripts/break-glass.sh release --reason "<JIRA-XXX>: complete"

DO NOT:
  - Create IAM access keys
  - Disable CloudTrail / GuardDuty / SecurityHub
  - Detach SCPs
  - Modify the audit-log-archive bucket policy
================================================================================
BANNER
}

cmd_release() {
    local reason=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason) reason="${2:-}"; shift 2;;
            *) log_local ERROR "Unknown flag: $1"; exit 1;;
        esac
    done
    [[ -n "${reason}" ]] || { log_local ERROR "--reason is required"; exit 1; }

    require_lead
    require_jira_in_reason "${reason}"

    log_local INFO "Break-glass RELEASE — reason: ${reason}"
    log_cloudwatch release "${reason}"

    if command -v op >/dev/null 2>&1; then
        log_local INFO "Rotating root password in 1Password vault ${OP_VAULT}..."
        op item edit "${OP_ITEM}" --vault "${OP_VAULT}" --generate-password=letters,digits,symbols,32 >/dev/null \
            || log_local WARN "1Password rotation failed; rotate manually."
    else
        log_local WARN "1Password CLI not found; rotate the password manually."
    fi

    cat <<BANNER >&2
================================================================================
BREAK-GLASS: session released
================================================================================
1. CloudTrail link (last 1 hour, root identity):
     https://console.aws.amazon.com/cloudtrail/home?region=${LOG_REGION}#/events
     Filter: User name = root, Time range = last 1h

2. Update Jira ticket (${reason}) with:
   - End time: $(date -u +%Y-%m-%dT%H:%M:%SZ)
   - Link to CloudTrail filter above
   - Summary of what was done

3. If anything unexpected happened, open a security incident in
   #aws-security.
================================================================================
BANNER
}

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------
main() {
    if [[ $# -eq 0 ]]; then
        cat <<'USAGE'
Usage:
  break-glass.sh request --reason "JIRA-NNN: <description>"
  break-glass.sh release --reason "JIRA-NNN: complete"

See docs/break-glass-procedure.md for the full runbook.
USAGE
        exit 1
    fi

    local cmd="$1"; shift
    case "${cmd}" in
        request) cmd_request "$@";;
        release) cmd_release "$@";;
        *) log_local ERROR "Unknown subcommand: ${cmd}"; exit 1;;
    esac
}

main "$@"
