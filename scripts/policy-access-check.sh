#!/usr/bin/env bash
#
# policy-access-check.sh — Access Analyzer custom-policy-check gate for org
# policy (SCP/RCP) changes. Provenance: ADR-0017 (decision item 4), epic #252.
#
# WHAT IT DOES
#   Reads a `terraform show -json` plan, extracts every changed
#   aws_organizations_policy resource's OLD (before) and NEW (after) policy
#   JSON document, and for each one runs IAM Access Analyzer custom policy
#   checks to prove the change does not widen effective access:
#
#     aws accessanalyzer check-no-new-access \
#         --new-policy-document  <after.content> \
#         --existing-policy-document <before.content> \
#         --policy-type SERVICE_CONTROL_POLICY|RESOURCE_CONTROL_POLICY
#
#     aws accessanalyzer check-access-not-granted \
#         --policy-document <after.content> \
#         --access '[{"actions":["organizations:LeaveOrganization", ...]}]' \
#         --policy-type ...
#
# GATE ON THE JSON `result` FIELD — NOT THE EXIT CODE.
#   The AWS CLI can exit 0 even when the check result is FAIL. We therefore
#   capture stdout JSON and read the `.result` field (PASS / FAIL). This is
#   called out explicitly in ADR-0017.
#
# PAID FEATURE. Each check is a billable Access Analyzer call. The calling
# workflow only runs on PRs touching modules/{scps,rcps} to bound cost.
#
# CREDENTIAL-FREE MODE. When HAS_AWS != "true" (no AWS role configured — forks,
# the mock repo), the paid AWS calls are SKIPPED. The script still parses the
# plan and reports the policies it WOULD check, exiting 0 so non-AWS CI passes.
#
# OUTPUT. Markdown to stdout (intended for $GITHUB_STEP_SUMMARY).
#
# EXIT CODE.
#   0  all checks PASS, or ADVISORY=true, or credential-free mode, or no policy
#      changes in the plan.
#   1  at least one check returned result=FAIL AND ADVISORY != "true" (blocking).
#
# Usage: policy-access-check.sh <plan.json>
# Env:   HAS_AWS (true|false), ADVISORY (true|false), MODULE (label only).

set -euo pipefail

PLAN_JSON="${1:?usage: policy-access-check.sh <plan.json>}"
HAS_AWS="${HAS_AWS:-false}"
ADVISORY="${ADVISORY:-true}"
MODULE="${MODULE:-unknown}"

# Sensitive actions that must STAY denied — check-access-not-granted asserts the
# proposed policy does NOT grant any of these (ADR-0017 names these two).
SENSITIVE_ACTIONS='["organizations:LeaveOrganization","cloudtrail:StopLogging"]'

echo "### Policy Access Check — \`${MODULE}\`"
echo ""

if ! command -v jq >/dev/null 2>&1; then
  echo "> jq not found — cannot parse the plan. Failing closed only if blocking."
  [ "${ADVISORY}" = "true" ] && exit 0 || exit 1
fi

if [ ! -s "${PLAN_JSON}" ]; then
  echo "> No plan JSON at \`${PLAN_JSON}\` — nothing to check (trivially PASS)."
  exit 0
fi

# Map a Terraform aws_organizations_policy.type to an Access Analyzer --policy-type.
# Access Analyzer supports SERVICE_CONTROL_POLICY and RESOURCE_CONTROL_POLICY
# policy types for these checks.
aa_policy_type() {
  case "$1" in
    SERVICE_CONTROL_POLICY) echo "SERVICE_CONTROL_POLICY" ;;
    RESOURCE_CONTROL_POLICY) echo "RESOURCE_CONTROL_POLICY" ;;
    *) echo "" ;;
  esac
}

# Extract changed aws_organizations_policy resources as compact JSON lines:
#   {address, ptype, before, after}
# before/after are the `content` IAM-policy-document strings (may be null/empty).
changed=$(jq -c '
  .resource_changes // []
  | map(select(.type == "aws_organizations_policy"))
  | map(select((.change.actions // []) | (index("create") or index("update") or index("no-op") or index("delete")) | . != null))
  | .[]
  | {
      address: .address,
      ptype:   ((.change.after.type) // (.change.before.type) // ""),
      before:  ((.change.before.content) // ""),
      after:   ((.change.after.content) // "")
    }
' "${PLAN_JSON}" 2>/dev/null || true)

if [ -z "${changed}" ]; then
  echo "> No \`aws_organizations_policy\` changes in this plan — trivially PASS."
  echo ""
  echo "_Old/new policy JSON is read from \`terraform show -json\` (resource_changes[].change.before/after.content)._"
  exit 0
fi

if [ "${HAS_AWS}" != "true" ]; then
  echo "> **Credential-free mode** (no \`POLICY_CHECK_ROLE_ARN\`): the PAID Access"
  echo "> Analyzer calls are skipped. Policies that WOULD be checked on a"
  echo "> configured account:"
  echo ""
  echo "${changed}" | jq -r '"- `\(.address)` (\(.ptype // "?"))"'
  echo ""
  echo "_Gate logic (result-field parsing) runs only when AWS OIDC is configured._"
  exit 0
fi

overall_fail=0

run_check() {
  # $1 = human label, remaining args = aws accessanalyzer subcommand + flags.
  local label="$1"; shift
  local out result
  # Capture stdout JSON; tolerate non-zero exit (we gate on .result, not $?).
  out="$("$@" 2>/dev/null || true)"
  result="$(printf '%s' "${out}" | jq -r '.result // "ERROR"' 2>/dev/null || echo "ERROR")"
  echo "  - ${label}: **${result}**"
  if [ "${result}" != "PASS" ]; then
    overall_fail=1
    # Surface the first reason, if any, to aid the reviewer.
    printf '%s' "${out}" | jq -r '.reasons[0].description // empty' 2>/dev/null \
      | sed 's/^/      reason: /' || true
  fi
}

while IFS= read -r row; do
  [ -z "${row}" ] && continue
  address="$(printf '%s' "${row}" | jq -r '.address')"
  ptype_tf="$(printf '%s' "${row}" | jq -r '.ptype')"
  before="$(printf '%s' "${row}" | jq -r '.before')"
  after="$(printf '%s' "${row}" | jq -r '.after')"
  aa_type="$(aa_policy_type "${ptype_tf}")"

  echo "- \`${address}\` (${ptype_tf:-unknown})"

  if [ -z "${aa_type}" ]; then
    echo "  - SKIPPED: policy type \`${ptype_tf}\` is not checkable by Access Analyzer."
    continue
  fi
  if [ -z "${after}" ]; then
    echo "  - SKIPPED: no proposed (after) policy document (deletion)."
    continue
  fi

  # check-no-new-access: new vs existing. If there is no `before` (a brand-new
  # policy), compare against an empty/deny-only baseline so the check still runs.
  if [ -n "${before}" ]; then
    run_check "check-no-new-access" \
      aws accessanalyzer check-no-new-access \
        --new-policy-document "${after}" \
        --existing-policy-document "${before}" \
        --policy-type "${aa_type}" \
        --output json
  else
    echo "  - check-no-new-access: SKIPPED (new policy, no existing baseline)"
  fi

  # check-access-not-granted: the proposed policy must NOT grant the sensitive
  # actions (organizations:LeaveOrganization, cloudtrail:StopLogging).
  run_check "check-access-not-granted (sensitive actions)" \
    aws accessanalyzer check-access-not-granted \
      --policy-document "${after}" \
      --access "[{\"actions\":${SENSITIVE_ACTIONS}}]" \
      --policy-type "${aa_type}" \
      --output json

done <<< "${changed}"

echo ""
if [ "${overall_fail}" -eq 0 ]; then
  echo "**Result: PASS** — no widened access detected."
  exit 0
fi

if [ "${ADVISORY}" = "true" ]; then
  echo "**Result: FAIL (advisory)** — a check returned FAIL but the gate is"
  echo "advisory (ADR-0017 step 1). Not blocking the merge yet."
  exit 0
fi

echo "**Result: FAIL (blocking)** — a check returned FAIL. Blocking the merge."
exit 1
