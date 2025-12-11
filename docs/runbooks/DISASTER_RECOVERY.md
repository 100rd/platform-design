# Runbook: Disaster Recovery (DR)

**Scenario:** Total System Failure / Region Outage

## Description
This runbook covers scenarios where the automated failover system itself is compromised (e.g., EKS cluster down, AWS region outage) or both DNS providers are failing simultaneously.

## Scenarios

### Scenario A: EKS Cluster / Failover Controller Down
If the control plane is down, the automated failover logic will not run.
**Action:**
1.  **Manual Override:** Log in to the Registrar Portal (e.g., Namecheap, GoDaddy) directly.
2.  **Update Nameservers:** Manually change the nameservers to the healthy provider.
    - *Note: This bypasses all safety checks.*
3.  **Restore Control Plane:**
    - Deploy the stack to a secondary region (e.g., `us-west-2`) using Terraform.
    - Restore the database from the latest snapshot.

### Scenario B: Both Providers Down (Total Outage)
If both Cloudflare and Route53 are down simultaneously (extremely rare).
**Action:**
1.  **Emergency Provider:** Activate a third, emergency DNS provider (e.g., NS1 or Google Cloud DNS).
2.  **Update Registrar:** Point NS records to the emergency provider.
3.  **Deploy Zone:** Manually upload the zone file (`dns-sync/zones/example.com.yaml`) to the emergency provider.

### Scenario C: Corrupted State / Database Failure
If the `dns_failover` database is corrupted.
**Action:**
1.  **Restore Backup:**
    - Identify the latest automated backup in AWS Backup / RDS Snapshots.
    - Restore to a new RDS instance.
2.  **Update Connection:**
    - Update the `database-url` secret in Kubernetes to point to the new instance.
    - Restart the `failover-controller` and `dns-monitor` pods.

## Drills
- **Frequency:** Quarterly.
- **Procedure:** Simulate a "Controller Down" scenario and practice logging into the registrar portal to manually change NS records.
