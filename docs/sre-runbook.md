# SRE Runbook - Observability Operations

This runbook provides operational procedures for the SRE team managing the observability stack on EKS.

---

## Table of Contents

1. [Daily Checks](#daily-checks)
2. [On-Call Procedures](#on-call-procedures)
3. [Incident Response](#incident-response)
4. [Common Scenarios](#common-scenarios)
5. [Maintenance Procedures](#maintenance-procedures)

---

## Daily Checks

### Morning Health Review (15 minutes)

Run these checks every morning to ensure observability stack health:

#### 1. Check Observability Stack Health

```bash
# Check all pods are running
kubectl get pods -n observability

# Expected: All pods in Running state, no CrashLoopBackOff

# Quick health check script
kubectl get pods -n observability -o json | \
  jq -r '.items[] | select(.status.phase != "Running") |
  "\(.metadata.name): \(.status.phase)"'
```

**Dashboard**: [Observability Stack Health](https://grafana/d/observability-health)

**Key Metrics to Review**:
```promql
# Any pods not ready?
kube_pod_status_ready{namespace="observability", condition="false"} > 0

# Any pods restarting frequently?
rate(kube_pod_container_status_restarts_total{namespace="observability"}[1h]) > 0.1

# High memory usage (> 90%)?
container_memory_working_set_bytes{namespace="observability"} /
container_spec_memory_limit_bytes{namespace="observability"} > 0.9
```

#### 2. Check Data Ingestion Rates

**Metrics**:
```bash
# Port-forward Prometheus
kubectl port-forward -n observability svc/prometheus-stack-kube-prometheus-prometheus 9090:9090 &

# Check ingestion rate
curl -s 'http://localhost:9090/api/v1/query?query=rate(prometheus_tsdb_head_samples_appended_total[5m])' | \
  jq '.data.result[0].value[1]'

# Expected: ~1-5M samples/second (depends on cluster size)
```

**Logs**:
```promql
# Loki ingestion rate (MB/s)
sum(rate(loki_distributor_bytes_received_total[5m])) / 1024 / 1024

# Expected: 10-100 MB/s (depends on cluster size)
```

**Traces**:
```promql
# Tempo ingestion rate (spans/s)
sum(rate(tempo_distributor_spans_received_total[5m]))

# Expected: 1000-50000 spans/s (depends on sampling)
```

#### 3. Check Storage Health

```bash
# S3 bucket sizes
aws s3 ls s3:// --recursive --summarize | grep "Total Size"

# Expected growth rates:
# - thanos-metrics: ~20-50 GB/day
# - loki-logs: ~100 GB/day
# - tempo-traces: ~50-100 GB/day
# - pyroscope-profiles: ~10-20 GB/day
```

**Prometheus storage**:
```promql
# Local TSDB size (should be < 50 GB with 2h retention)
prometheus_tsdb_storage_blocks_bytes / 1024 / 1024 / 1024
```

**Thanos compaction lag**:
```promql
# Time since last compaction (should be < 2h)
time() - thanos_compact_group_compactions_success_timestamp_seconds
```

#### 4. Review Overnight Alerts

```bash
# Check Alertmanager for fired alerts
kubectl port-forward -n observability svc/prometheus-stack-kube-prometheus-alertmanager 9093:9093 &

# Open in browser
open http://localhost:9093
```

Or check Slack channel: **#observability-alerts**

**Common alerts to review**:
- `PrometheusHighMemoryUsage`
- `LokiIngestionRateLimitReached`
- `TempoIngesterFlushFailures`
- `ThanosCompactorNotRunning`

#### 5. Check Query Performance

**Dashboard**: [Query Performance](https://grafana/d/query-performance)

```promql
# Prometheus query latency P95 (should be < 5s)
histogram_quantile(0.95,
  rate(prometheus_http_request_duration_seconds_bucket{handler="query"}[5m])
)

# Loki query latency P95 (should be < 5s)
histogram_quantile(0.95,
  rate(loki_request_duration_seconds_bucket{route="loki_api_v1_query_range"}[5m])
)

# Tempo query latency P95 (should be < 5s)
histogram_quantile(0.95,
  rate(tempo_request_duration_seconds_bucket{route="/api/traces/{traceID}"}[5m])
)
```

---

## On-Call Procedures

### Escalation Paths

**Level 1** (Initial Response): On-call SRE
- Acknowledge alert within 5 minutes
- Initial triage and diagnosis
- Attempt standard remediation

**Level 2** (Expert Escalation): Senior SRE + Platform Team
- Escalate after 30 minutes if unresolved
- Complex issues requiring deep system knowledge

**Level 3** (Critical Escalation): Engineering Leadership
- Escalate for user-impacting issues > 1 hour
- Coordinate cross-team response

### PagerDuty Integration

**Alert Routing**:
- **Critical**: Page on-call SRE immediately (5 min ACK required)
- **Warning**: Create incident, notify Slack (1 hour ACK)
- **Info**: Log to Slack only, no page

**PagerDuty Services**:
- `observability-platform` - Metrics, logs, traces infrastructure
- `application-monitoring` - Application-level alerts

### Initial Triage Steps

When paged, follow this checklist:

1. **Acknowledge alert** (PagerDuty or Alertmanager)

2. **Check alert details**
   - What is alerting?
   - What threshold was breached?
   - Is it a single instance or cluster-wide?

3. **Assess user impact**
   - Are queries failing? (Check Grafana)
   - Is data being lost? (Check ingestion rates)
   - Is this affecting application monitoring?

4. **Check related systems**
   - EKS cluster health: `kubectl get nodes`
   - S3 bucket accessibility
   - Network connectivity

5. **Review recent changes**
   - Recent deployments? (`helm history -n observability`)
   - Configuration changes?
   - Kubernetes version upgrades?

6. **Execute runbook** (see Common Scenarios below)

7. **Document in incident channel**
   - Create thread in #incidents
   - Post findings and actions
   - Tag relevant people

### Communication Templates

**Initial Incident Report** (Slack #incidents):
```
🚨 INCIDENT: [Brief description]
━━━━━━━━━━━━━━━━━━━━━━━━━━━
Alert: [Alert name]
Severity: [Critical/Warning]
Time: [UTC timestamp]
Impact: [User-facing impact, if any]
Status: Investigating

Assigned: @oncall-sre
```

**Status Update** (every 30 minutes):
```
📊 UPDATE: [Incident name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━
Status: [Investigating/Mitigating/Resolved]
Actions taken:
  • [Action 1]
  • [Action 2]
Next steps:
  • [Next action]
ETA: [Estimated resolution time]
```

**Resolution** (post-incident):
```
✅ RESOLVED: [Incident name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━
Duration: [Start time - End time]
Root cause: [Brief description]
Resolution: [What fixed it]
Follow-up: [Link to post-mortem doc]
```

---

## Incident Response

### Using Observability Signals for Troubleshooting

When investigating an incident, use signals in this order:

#### 1. Metrics (Initial Detection)

**Purpose**: Identify WHAT is broken and WHEN it started

**Dashboard**: [Platform Overview](https://grafana/d/platform-overview)

**Key queries**:
```promql
# Service error rate spike
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)

# Service latency increase
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)
)

# Resource saturation
node_cpu_usage_percent > 90
node_memory_usage_percent > 90
```

**Questions to answer**:
- Which service(s) are affected?
- When did the issue start?
- Is it impacting all instances or just some?
- What's the blast radius?

#### 2. Logs (Context)

**Purpose**: Understand WHY it's broken (error messages, stack traces)

**Query in Grafana Explore** (Loki):
```logql
# Find errors in affected service
{namespace="game-services", app="game-api"}
  |= "error" or "ERROR" or "exception"
  | json
  | status_code >= 500

# Find recent deployments (potential cause)
{namespace="game-services"}
  |~ "(?i)(deployed|rollout|scaled)"

# Find resource issues
{namespace="game-services"}
  |~ "(?i)(oom|out of memory|killed)"
```

**Questions to answer**:
- What error messages are appearing?
- Are there stack traces? (click to expand multiline)
- Did a deployment just happen?
- Are there resource exhaustion errors?

#### 3. Traces (Root Cause)

**Purpose**: Identify WHERE in the request flow the issue occurs

**Query in Grafana Explore** (Tempo):
```traceql
# Find slow traces
{ duration > 5s && service.name = "game-api" }

# Find error traces
{ status = error && service.name = "game-api" }

# Find traces with specific operation
{ span.http.route = "/api/v1/matchmaking" && duration > 1s }
```

**What to look for**:
- Which span is taking the longest? (waterfall view)
- Are database queries slow?
- Are external API calls timing out?
- Is there a cascade of errors?

**Flame graph analysis**:
- Wide bars = time-consuming operations
- Deep stacks = many nested calls
- Red spans = errors

#### 4. Profiles (Performance Deep Dive)

**Purpose**: Identify WHICH CODE is causing performance issues

**When to use**:
- High CPU usage but unclear why
- Memory leaks suspected
- Goroutine leaks
- Lock contention

**Query in Grafana Explore** (Pyroscope):
```
# Compare CPU profile before/after incident
{service_name="game-api"}
  time range: [incident start - 1h] to [incident start + 1h]
```

**Diff view**:
- Green = decreased CPU (good)
- Red = increased CPU (investigate these functions)

**What to look for**:
- Unexpected functions in top 10 CPU consumers
- Regex operations in hot path
- JSON marshaling/unmarshaling overhead
- Database connection pool exhaustion

### Complete Investigation Workflow

**Example: High Latency Incident**

1. **Metrics**: P95 latency increased from 200ms to 5s at 10:30 UTC
   ```promql
   histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{service="game-api"}[5m]))
   ```

2. **Logs**: Find error logs around 10:30 UTC
   ```logql
   {namespace="game-services", app="game-api"} | json | latency_ms > 1000
   ```
   → Find: "Database connection pool exhausted"

3. **Traces**: Sample slow traces
   ```traceql
   { service.name = "game-api" && duration > 2s }
   ```
   → Find: 90% of time spent in `db.Query()` span

4. **Profiles**: Compare CPU profile at 10:25 vs 10:35
   → Find: `pgx.(*Conn).Query` consuming 80% more CPU

**Root Cause**: Database connection pool exhaustion due to slow queries

**Resolution**: Scale up database read replicas, increase connection pool size

---

## Common Scenarios

### Scenario 1: High Latency Investigation

**Symptom**: Users reporting slow API responses

**Dashboard**: [Service Performance](https://grafana/d/service-performance)

**Investigation**:

```bash
# Step 1: Identify affected service
# Check all services for latency spikes
promql: histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)
)

# Step 2: Check resource saturation
# CPU
promql: container_cpu_usage_seconds_total / container_spec_cpu_quota

# Memory
promql: container_memory_working_set_bytes / container_spec_memory_limit_bytes

# Step 3: Query logs for errors
logql: {namespace="game-services", app="$SERVICE"}
  |= "slow" or "timeout" or "latency"

# Step 4: Sample slow traces
traceql: { service.name = "$SERVICE" && duration > 1s }
  # Look at waterfall view to identify slow spans

# Step 5: Check for database issues
logql: {namespace="game-services", app="$SERVICE"}
  | json
  | db_query_duration_ms > 500

# Step 6: Check for external API issues
traceql: { service.name = "$SERVICE" && span.http.host =~ "external-api.*" }
```

**Common Causes**:
- Database connection pool exhausted
- External API degradation
- Memory pressure causing GC pauses
- Network issues (check network policies)

**Remediation**:

```bash
# Temporary: Scale up replicas
kubectl scale deployment/$SERVICE -n game-services --replicas=10

# Check for recent config changes
kubectl rollout history deployment/$SERVICE -n game-services

# Rollback if needed
kubectl rollout undo deployment/$SERVICE -n game-services
```

---

### Scenario 2: Memory Leak Detection

**Symptom**: Pods OOMKilled frequently, increasing memory usage

**Dashboard**: [Memory Usage](https://grafana/d/memory-usage)

**Investigation**:

```bash
# Step 1: Identify leaking pods
kubectl get events -n game-services --field-selector reason=OOMKilled

# Step 2: Check memory growth rate
promql: rate(container_memory_working_set_bytes{pod=~"$POD"}[1h])

# Step 3: Check Pyroscope memory profile
# In Grafana Explore (Pyroscope):
# - Select: memory:alloc_objects:count:space:bytes
# - App: $SERVICE
# - Compare: [24h ago] vs [now]
# - Look for growing allocations

# Step 4: Check for goroutine leaks (Go apps)
# In Pyroscope:
# - Select: goroutine:goroutine:count::
# - Look for steady growth

# Step 5: Query logs for clues
logql: {namespace="game-services", app="$SERVICE"}
  |~ "(?i)(leak|memory|gc|heap)"
```

**Common Causes**:
- Unclosed database connections
- Growing caches without eviction
- Goroutine leaks (missing context cancellation)
- Large response buffering

**Remediation**:

```bash
# Immediate: Restart pods to free memory
kubectl rollout restart deployment/$SERVICE -n game-services

# Temporary: Increase memory limits
kubectl patch deployment/$SERVICE -n game-services \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"$SERVICE","resources":{"limits":{"memory":"4Gi"}}}]}}}}'

# Long-term: Fix code (based on profile analysis)
# - Add connection pool limits
# - Add cache size limits
# - Fix goroutine leaks
# - Use streaming instead of buffering
```

---

### Scenario 3: Error Spike Analysis

**Symptom**: Sudden increase in 5xx errors

**Dashboard**: [Error Rates](https://grafana/d/error-rates)

**Investigation**:

```bash
# Step 1: Identify error rate
promql: sum(rate(http_requests_total{status=~"5.."}[5m])) by (service, status)

# Step 2: Find error logs
logql: {namespace="game-services"}
  | json
  | status_code >= 500
  | line_format "{{.timestamp}} {{.service}} {{.message}}"

# Step 3: Find error traces (100% sampled)
traceql: { status = error }
  # Click on trace, expand to see error details

# Step 4: Check for deployment correlation
# Did errors start after a deployment?
kubectl rollout history deployment -n game-services

# Step 5: Check dependencies
# Are downstream services healthy?
promql: up{namespace="game-services"} == 0
```

**Common Causes**:
- Bad deployment (new bug introduced)
- Dependency failure (database, external API)
- Rate limiting hit
- Configuration error

**Remediation**:

```bash
# If caused by recent deployment: Rollback
kubectl rollout undo deployment/$SERVICE -n game-services

# If caused by dependency: Scale or failover
kubectl scale deployment/$DEPENDENCY -n game-services --replicas=5

# If rate limit: Increase limits or implement backoff
# Check external API quotas

# If config error: Revert ConfigMap/Secret
kubectl rollout restart deployment/$SERVICE -n game-services
```

---

### Scenario 4: Node Failure Response

**Symptom**: Node becomes NotReady, pods evicted

**Dashboard**: [Node Health](https://grafana/d/node-health)

**Investigation**:

```bash
# Step 1: Identify unhealthy node
kubectl get nodes
kubectl describe node $NODE

# Step 2: Check node metrics
promql: node_cpu_usage_percent{node="$NODE"}
promql: node_memory_usage_percent{node="$NODE"}
promql: node_disk_io_time_seconds_total{node="$NODE"}

# Step 3: Check for OOM killer
logql: {job="node-exporter", node="$NODE"} |= "oom"

# Step 4: Check kubelet logs
kubectl logs -n kube-system -l component=kubelet --field-selector spec.nodeName=$NODE

# Step 5: Check which pods were on node
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=$NODE
```

**Remediation**:

```bash
# Mark node unschedulable
kubectl cordon $NODE

# Drain node (gracefully evict pods)
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data

# If node is truly dead, delete it (Karpenter will replace)
kubectl delete node $NODE

# Verify pods rescheduled
kubectl get pods --all-namespaces -o wide | grep $NODE
# Should be empty

# Check Karpenter provisioned new node
kubectl get nodes -l karpenter.sh/provisioner-name

# Uncordon if node recovered
kubectl uncordon $NODE
```

**Observability Impact**:
- Fluent Bit on that node stops collecting logs (tolerable, short-term loss)
- OTel Collector agent stops collecting traces (new node will have agent)
- Prometheus continues scraping other nodes
- No data loss for S3-backed storage (Thanos, Loki, Tempo)

---

### Scenario 5: Deployment Rollback

**Symptom**: New deployment causing issues

**Dashboard**: [Deployment Status](https://grafana/d/deployment-status)

**Investigation**:

```bash
# Step 1: Check recent deployments
kubectl rollout history deployment/$SERVICE -n game-services

# Step 2: Compare metrics before/after deployment
# In Grafana, set time range to [deploy time - 1h] to [now]
promql: rate(http_requests_total{service="$SERVICE", status=~"5.."}[5m])

# Step 3: Check logs for new errors
logql: {namespace="game-services", app="$SERVICE"}
  | json
  | line_format "{{.level}} {{.message}}"
  | filter level == "error"

# Step 4: Compare traces before/after
traceql: { service.name = "$SERVICE" }
# Use time range picker to compare
```

**Rollback Procedure**:

```bash
# Option 1: Rollback to previous version
kubectl rollout undo deployment/$SERVICE -n game-services

# Option 2: Rollback to specific revision
kubectl rollout undo deployment/$SERVICE -n game-services --to-revision=3

# Monitor rollback progress
kubectl rollout status deployment/$SERVICE -n game-services

# Verify metrics improved
# Check dashboard for error rate decrease
```

**Post-Rollback**:
```bash
# Create incident post-mortem
# Document:
# - What changed in the deployment?
# - What broke?
# - Why didn't pre-prod catch it?
# - How to prevent in future? (better tests, gradual rollout, etc.)
```

---

## Maintenance Procedures

### Upgrading Observability Stack

**Frequency**: Quarterly (or as needed for security patches)

**Preparation** (1 week before):

1. **Review release notes**
   - Prometheus Operator: https://github.com/prometheus-operator/prometheus-operator/releases
   - Thanos: https://github.com/thanos-io/thanos/releases
   - Loki: https://github.com/grafana/loki/releases
   - Tempo: https://github.com/grafana/tempo/releases
   - Grafana: https://grafana.com/docs/grafana/latest/whatsnew/

2. **Test in staging**
   ```bash
   # Upgrade in staging cluster
   helm upgrade prometheus-stack ./prometheus-stack \
     -n observability \
     --values values.yaml \
     --values values-staging.yaml
   ```

3. **Create backup**
   ```bash
   # Backup Grafana dashboards
   kubectl get configmaps -n observability -l grafana_dashboard=1 -o yaml \
     > grafana-dashboards-backup-$(date +%Y%m%d).yaml

   # Backup Prometheus rules
   kubectl get prometheusrules -n observability -o yaml \
     > prometheus-rules-backup-$(date +%Y%m%d).yaml

   # Backup Helm values
   helm get values prometheus-stack -n observability > values-backup-$(date +%Y%m%d).yaml
   ```

**Upgrade Procedure**:

```bash
# 1. Update Helm chart dependencies
cd prometheus-stack
helm dependency update

# 2. Dry-run to see changes
helm upgrade prometheus-stack . \
  -n observability \
  --values values.yaml \
  --dry-run --debug

# 3. Perform upgrade
helm upgrade prometheus-stack . \
  -n observability \
  --values values.yaml \
  --wait \
  --timeout 15m

# 4. Monitor rollout
watch kubectl get pods -n observability

# 5. Verify health
kubectl logs -n observability -l app.kubernetes.io/name=prometheus --tail=100
kubectl logs -n observability -l app.kubernetes.io/name=thanos-query --tail=100

# 6. Test queries in Grafana
# - Run sample PromQL query
# - Run sample LogQL query
# - Load a trace by ID

# 7. Check for alerts
kubectl get prometheusrules -n observability
```

**Rollback if needed**:
```bash
helm rollback prometheus-stack -n observability
```

---

### Rotating Credentials

**Frequency**: Every 90 days (compliance requirement)

**S3 Credentials**:

```bash
# 1. Create new IAM access key
aws iam create-access-key --user-name thanos-s3-user

# 2. Update secret in Parameter Store
aws ssm put-parameter \
  --name /observability/thanos/s3_access_key_id \
  --value "NEW_ACCESS_KEY" \
  --overwrite

aws ssm put-parameter \
  --name /observability/thanos/s3_secret_access_key \
  --value "NEW_SECRET_KEY" \
  --overwrite \
  --type SecureString

# 3. External Secrets Operator will auto-update the K8s secret

# 4. Restart pods to pick up new credentials
kubectl rollout restart statefulset/prometheus-stack-kube-prometheus-prometheus -n observability
kubectl rollout restart deployment/thanos-query -n observability

# 5. Verify S3 access
kubectl logs -n observability -l app.kubernetes.io/component=thanos-sidecar | grep -i "s3"

# 6. Delete old access key
aws iam delete-access-key --user-name thanos-s3-user --access-key-id OLD_ACCESS_KEY
```

**Grafana Admin Password**:

```bash
# 1. Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# 2. Update in Parameter Store
aws ssm put-parameter \
  --name /observability/grafana/admin-password \
  --value "$NEW_PASSWORD" \
  --overwrite \
  --type SecureString

# 3. External Secrets Operator will update secret

# 4. Restart Grafana
kubectl rollout restart deployment/grafana -n observability

# 5. Verify new password works
curl -u admin:$NEW_PASSWORD http://grafana.observability.svc.cluster.local/api/health
```

---

### Cleaning Up Old Data

**S3 Lifecycle Policies** (automated, verify):

```bash
# Check lifecycle policy for Thanos
aws s3api get-bucket-lifecycle-configuration --bucket thanos-metrics

# Should see:
# - Transition to IA after 30 days
# - Transition to Glacier after 90 days
# - Expiration after 365 days

# Check lifecycle policy for Loki
aws s3api get-bucket-lifecycle-configuration --bucket loki-logs

# Should see:
# - Transition to IA after 7 days
# - Expiration after 30 days
```

**Manual Cleanup** (if needed):

```bash
# List old blocks in Thanos bucket
aws s3 ls s3://thanos-metrics/ --recursive | \
  awk '{if ($1 < "2023-01-01") print $4}'

# Delete blocks older than 1 year (if lifecycle failed)
aws s3 rm s3://thanos-metrics/ \
  --recursive \
  --exclude "*" \
  --include "*/01E*" \
  --dryrun  # Remove --dryrun to actually delete
```

**Local Disk Cleanup**:

```bash
# Check Prometheus TSDB size
kubectl exec -n observability prometheus-stack-kube-prometheus-prometheus-0 -c prometheus -- \
  du -sh /prometheus

# Should be < 50 GB with 2h retention

# If too large, check retention settings
kubectl get prometheus -n observability -o yaml | grep retention

# Or manually compact
kubectl exec -n observability prometheus-stack-kube-prometheus-prometheus-0 -c prometheus -- \
  promtool tsdb analyze /prometheus
```

---

### Capacity Planning

**Monthly Review**:

```bash
# 1. Check current resource utilization
kubectl top nodes -l node.kubernetes.io/workload=observability
kubectl top pods -n observability

# 2. Check growth trends in Grafana
# Dashboard: [Capacity Planning]
# - Metrics ingestion rate trend (last 30 days)
# - Log ingestion rate trend
# - Trace ingestion rate trend
# - Storage growth rate

# 3. Forecast next month
# Rule of thumb:
# - Add 1 Prometheus shard per 5M additional active series
# - Add 2 Loki Write replicas per 50 MB/s ingestion increase
# - Add 1 Tempo Distributor per 10K additional spans/s

# 4. Check S3 storage costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-02-01 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter file://s3-filter.json

# 5. Optimize if needed
# - Increase retention downsampling
# - Adjust log sampling
# - Tune trace sampling rates
```

**Scaling Decision Matrix**:

| Metric | Threshold | Action |
|--------|-----------|--------|
| Prometheus ingestion | > 5M samples/s | Add shard or vertical scale |
| Loki Write CPU | > 80% | Scale replicas (HPA will do this) |
| Loki Read latency | P95 > 5s | Scale Read replicas |
| Tempo Distributor latency | P99 > 1s | Scale distributors |
| S3 storage cost | > $500/month | Review retention policies |
| Query latency | P95 > 10s | Add querier replicas |

---

## Emergency Contacts

**On-Call Rotation**: See PagerDuty schedule

**Escalation**:
- **Platform Team Lead**: @platform-lead (Slack)
- **Engineering Manager**: @eng-manager (Slack, phone in PagerDuty)
- **AWS Support**: 1-800-XXX-XXXX (Premium Support)

**Vendor Support**:
- **Grafana Labs**: support@grafana.com (Enterprise license)
- **AWS EKS**: Via AWS Support Console

**Runbook Repository**: https://github.com/company/runbooks
**Incident Template**: https://wiki.company.com/incident-template

---

## Post-Incident Procedures

After resolving an incident:

1. **Update Incident Log**
   - Document in incident tracking system
   - Add timeline of events
   - Note root cause

2. **Schedule Post-Mortem** (within 48 hours)
   - Invite: On-call SRE, service owner, stakeholders
   - Use template: https://wiki.company.com/post-mortem-template

3. **Create Action Items**
   - Prevent recurrence (code fix, alert tuning, runbook update)
   - Improve detection (better alerts, dashboards)
   - Reduce MTTR (automation, documentation)

4. **Update Runbook**
   - Add new scenario if not covered
   - Update steps based on what worked
   - Share learnings with team

5. **Share Learnings**
   - Post in #sre-learnings Slack channel
   - Present in weekly SRE sync
   - Update training materials

---

**Remember**: The goal of observability is to reduce MTTR (Mean Time To Resolution). Always document your findings to help the next person on-call!
