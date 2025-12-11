# Runbook: DNS Failover Initiated

**Alert Name:** `DNSFailoverInitiated`
**Severity:** Critical

## Description
This alert triggers when the Failover Controller has detected a critical failure in an active DNS provider and has initiated the failover process to remove it from the NS records.

## Trigger Condition
`dns_failover_state{state="FAILING_OVER"} == 1`

## Impact
- **Traffic Shift:** DNS traffic is being shifted away from the failed provider.
- **Latency:** Users may experience temporary latency during propagation.
- **Risk:** If the remaining provider also fails, total outage will occur.

## Immediate Actions
1.  **Acknowledge the Alert:**
    - Check the `#ops-alerts` Slack channel.
    - Acknowledge the PagerDuty incident.

2.  **Verify Failover Status:**
    - Run `tools/dns-admin status` to check the current state.
    - Check Grafana "Events" dashboard for "Failover Started" and "Failover Completed" events.

3.  **Check Provider Status:**
    - Check the status page of the failed provider (e.g., Cloudflare Status, AWS Health Dashboard).
    - Check internal health metrics in Grafana "Provider Health" dashboard.

4.  **Monitor Remaining Provider:**
    - Ensure the remaining provider is healthy and handling the increased load.
    - Watch for `DNSHighQueryLatency` alerts on the active provider.

## Resolution
- **Automatic:** The system will transition to `FAILOVER_ACTIVE` once the NS update is confirmed.
- **Manual Intervention:** If the failover gets stuck in `FAILING_OVER` for > 5 minutes:
    1.  Check controller logs: `kubectl logs -n dns-failover -l app=failover-controller`
    2.  Manually verify registrar NS records via their portal.
    3.  If needed, manually update NS records via the registrar portal.

## Post-Incident
- Once the failed provider recovers, follow the **Recovery Runbook** to restore traffic.
