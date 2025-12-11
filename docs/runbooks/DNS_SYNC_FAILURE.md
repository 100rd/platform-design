# Runbook: DNS Sync Failure

**Alert Name:** `DNSSyncFailed`
**Severity:** Critical

## Description
This alert triggers when the OctoDNS synchronization job has failed consistently for 15 minutes. This means changes to the Source of Truth (YAML files) are not being propagated to the DNS providers.

## Trigger Condition
`rate(dns_sync_errors_total[5m]) > 0` for 15m

## Impact
- **Stale Records:** DNS records may be out of date.
- **Drift:** Providers may become inconsistent if manual changes were made.
- **Blocked Updates:** New deployments or record changes will not take effect.

## Immediate Actions
1.  **Check CronJob Logs:**
    ```bash
    kubectl logs -n dns-failover -l job-name=<job-name> --tail=100
    ```
    Look for authentication errors, validation errors, or API rate limits.

2.  **Validate Configuration:**
    - Check if recent changes to `dns-sync/zones/*.yaml` introduced syntax errors.
    - Run the validation script locally:
      ```bash
      octodns-sync --config-file=dns-sync/config/octodns-config.yaml --dry-run
      ```

3.  **Check Secrets:**
    - Verify that API tokens (Cloudflare, Route53) are valid and haven't expired.
    - Check `kubectl get secrets -n dns-failover`.

## Resolution
- **Fix Config:** If a syntax error is found, revert the recent commit or fix the YAML file.
- **Rotate Secrets:** If credentials expired, update the Kubernetes secrets.
- **Manual Sync:** Once fixed, trigger a manual sync job:
    ```bash
    kubectl create job --from=cronjob/dns-sync dns-sync-manual
    ```

## Post-Incident
- Add a pre-commit hook or CI step to validate OctoDNS config before merging to main to prevent syntax errors.
