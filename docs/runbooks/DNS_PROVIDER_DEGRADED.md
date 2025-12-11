# Runbook: DNS Provider Degraded

**Alert Name:** `DNSProviderDegraded`
**Severity:** Warning

## Description
This alert triggers when a DNS provider's health score drops below 70 but is still above the critical failure threshold (20). This indicates performance issues or partial outages.

## Trigger Condition
`dns_provider_health_score < 70`

## Impact
- **Performance:** Users may experience slower DNS resolution times.
- **Reliability:** Increased risk of query failures.

## Immediate Actions
1.  **Investigate Metrics:**
    - Check Grafana "Provider Health" dashboard.
    - Identify if the issue is high latency (`DNSHighQueryLatency`) or increased error rate.
    - Determine if the issue is global or regional (check `check_location` in logs).

2.  **Check Provider Status:**
    - Visit the provider's status page.
    - Search for recent reports on Twitter/X or DownDetector.

3.  **Analyze Traffic:**
    - Check if there is an unusual spike in DNS queries (DDoS attack?).
    - Check `dns_query_duration_seconds` histogram.

## Resolution
- **Monitor Closely:** If the provider acknowledges an incident, monitor the situation. The system will automatically failover if it degrades further.
- **Manual Failover:** If the degradation is severe (e.g., 50% packet loss) but not triggering the automatic threshold, consider a **Manual Failover**:
    ```bash
    tools/dns-admin failover <provider_name>
    ```
    *Note: Obtain approval from the on-call lead before manually failing over.*

## Post-Incident
- Document the cause of degradation in the incident log.
- Adjust health scoring thresholds if false positives occur frequently.
