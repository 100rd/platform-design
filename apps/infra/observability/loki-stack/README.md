# Loki Stack - Production Logging Infrastructure

Production-ready Grafana Loki + Fluent Bit logging stack for gaming platform running on EKS. Designed to scale from 1,000 to 5,000 nodes with efficient log collection and querying.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Gaming Platform EKS Cluster                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │  Game Pod 1  │  │  Game Pod 2  │  │  Game Pod N  │           │
│  │              │  │              │  │              │           │
│  │ stdout/stderr│  │ stdout/stderr│  │ stdout/stderr│           │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘           │
│         │                 │                 │                    │
│         └─────────────────┴─────────────────┘                    │
│                           │                                      │
│                  /var/log/containers/*.log                       │
│                           │                                      │
│         ┌─────────────────▼─────────────────┐                    │
│         │   Fluent Bit DaemonSet (per node) │                    │
│         │  - Tail container logs             │                    │
│         │  - Parse multiline (Go/Java/Python)│                    │
│         │  - Add K8s metadata                │                    │
│         │  - Buffer with filesystem backend  │                    │
│         │  - CPU: 100m / Mem: 128Mi          │                    │
│         └─────────────────┬─────────────────┘                    │
│                           │                                      │
│                           │ HTTP/gzip                            │
│                           ▼                                      │
│         ┌─────────────────────────────────────┐                  │
│         │     Loki Gateway (Load Balancer)    │                  │
│         │     - NGINX reverse proxy           │                  │
│         │     - 2 replicas                    │                  │
│         └─────────────────┬─────────────────┘                    │
│                           │                                      │
│         ┌─────────────────┴─────────────────┐                    │
│         │                                   │                    │
│         ▼                                   ▼                    │
│  ┌──────────────┐                    ┌──────────────┐            │
│  │ Loki Write   │                    │  Loki Read   │            │
│  │ (Ingestion)  │                    │  (Queries)   │            │
│  │              │                    │              │            │
│  │ 3 replicas   │◄───────────────────┤ 3 replicas   │            │
│  │ HPA: 3-15    │                    │ HPA: 3-10    │            │
│  │ CPU: 1-2 core│                    │ CPU: 0.5-2   │            │
│  │ Mem: 4-8Gi   │                    │ Mem: 2-4Gi   │            │
│  └──────┬───────┘                    └──────────────┘            │
│         │                                                         │
│         │                    ┌──────────────┐                    │
│         │                    │ Loki Backend │                    │
│         │                    │ (Compactor)  │                    │
│         │                    │              │                    │
│         │                    │ 2 replicas   │                    │
│         │                    │ CPU: 0.5-1.5 │                    │
│         │                    │ Mem: 2-4Gi   │                    │
│         │                    └──────┬───────┘                    │
│         │                           │                            │
│         └───────────────────────────┘                            │
│                           │                                      │
│                           │ S3 API                               │
│                           ▼                                      │
└───────────────────────────────────────────────────────────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │       AWS S3            │
              │                         │
              │  loki-chunks/           │
              │  loki-ruler/            │
              │  loki-admin/            │
              │                         │
              │  Retention: 30 days     │
              │  Lifecycle: Glacier     │
              └─────────────────────────┘
```

## Components

### Loki - Simple Scalable Mode

**Architecture**: Separates components by function for independent scaling:
- **Write**: Handles log ingestion, runs ingesters
- **Read**: Handles queries, runs query frontend and queriers
- **Backend**: Runs compactor, ruler, and other background tasks

**Benefits**:
- Independent scaling of read vs write
- Better resource utilization
- Easier to troubleshoot
- Production-ready out of the box

### Fluent Bit - Efficient Log Collector

**Why Fluent Bit over Fluentd?**
- 10x lower memory footprint (~20MB vs ~200MB per node)
- Native Kubernetes support
- Faster processing (C vs Ruby)
- Built-in Loki output plugin

**Configuration**:
- DaemonSet on every node (including Karpenter provisioned)
- Tolerates all taints
- Filesystem buffering for reliability
- Multiline parsing for stack traces
- Kubernetes metadata enrichment

## Storage Design

### S3 Backend

```yaml
Buckets:
  loki-chunks/       # Log chunks (bulk storage)
  loki-ruler/        # Alerting rules
  loki-admin/        # Administrative data

Retention:
  Hot: 7 days (S3 Standard)
  Warm: 23 days (S3 Intelligent-Tiering)
  Total: 30 days

Lifecycle:
  30+ days: Delete (or archive to Glacier)
```

### Index vs Object Storage

- **Index**: TSDB (Time Series Database) - fast lookups
- **Chunks**: S3 - cost-effective bulk storage
- **Compaction**: Runs every 10 minutes to optimize storage

## Log Retention Policy

| Type | Retention | Storage Class | Notes |
|------|-----------|---------------|-------|
| Application Logs | 30 days | S3 Standard → Intelligent-Tiering | Auto-tiered based on access |
| System Logs | 30 days | S3 Standard → Intelligent-Tiering | kubelet, containerd |
| Error Logs | 30 days | S3 Standard | Keep accessible |
| Audit Logs | 90 days | S3 Standard | Compliance (separate bucket) |

## Query Examples (LogQL)

### Basic Queries

```logql
# All logs from a namespace
{k8s_namespace_name="game-servers"}

# Logs from specific pod
{k8s_pod_name="game-server-abc123"}

# Logs from app label
{k8s_labels_app="game-matchmaker"}

# Logs containing error
{k8s_namespace_name="game-servers"} |= "error"

# Logs NOT containing health checks
{k8s_namespace_name="game-servers"} != "health"
```

### Advanced Queries

```logql
# Error rate over time
sum(rate({k8s_namespace_name="game-servers"} |= "error" [5m])) by (k8s_labels_app)

# P95 latency from JSON logs
quantile_over_time(0.95,
  {k8s_labels_app="game-api"}
  | json
  | unwrap latency_ms [5m]
) by (k8s_labels_app)

# Count errors by pod
sum by (k8s_pod_name) (
  count_over_time({k8s_namespace_name="game-servers"} |= "ERROR" [1h])
)

# Stack traces (multiline)
{k8s_labels_app="game-server"} |~ "(?i)(panic|fatal|exception)"

# Regex filter for specific error codes
{k8s_namespace_name="game-servers"}
  |~ "HTTP (5[0-9]{2})"

# JSON field extraction
{k8s_labels_app="game-api"}
  | json
  | status_code >= 500
  | line_format "{{.method}} {{.path}} {{.status_code}}"
```

### Performance Queries

```logql
# High latency requests
{k8s_labels_app="game-api"}
  | json
  | latency_ms > 1000

# Failed matchmaking attempts
{k8s_labels_app="matchmaker"}
  | json
  | status = "failed"
  | line_format "Failed: {{.reason}} - Player: {{.player_id}}"

# Memory pressure logs
{k8s_labels_app="game-server"}
  |~ "(?i)(oom|out of memory|memory pressure)"
```

## Installation

### Prerequisites

1. **S3 Buckets**:
```bash
aws s3 mb s3://loki-chunks --region us-east-1
aws s3 mb s3://loki-ruler --region us-east-1
aws s3 mb s3://loki-admin --region us-east-1
```

2. **IAM Role for IRSA**:
```bash
# Create IAM policy
cat > loki-s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::loki-chunks",
        "arn:aws:s3:::loki-chunks/*",
        "arn:aws:s3:::loki-ruler",
        "arn:aws:s3:::loki-ruler/*",
        "arn:aws:s3:::loki-admin",
        "arn:aws:s3:::loki-admin/*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name LokiS3Access \
  --policy-document file://loki-s3-policy.json

# Create IRSA role (replace CLUSTER_NAME and ACCOUNT_ID)
eksctl create iamserviceaccount \
  --name loki \
  --namespace observability \
  --cluster gaming-production-eks \
  --attach-policy-arn arn:aws:iam::ACCOUNT_ID:policy/LokiS3Access \
  --approve
```

3. **External Secrets for S3 Credentials**:
```bash
# Store credentials in AWS Parameter Store
aws ssm put-parameter \
  --name /observability/loki/s3/access_key_id \
  --value "AKIAIOSFODNN7EXAMPLE" \
  --type SecureString

aws ssm put-parameter \
  --name /observability/loki/s3/secret_access_key \
  --value "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" \
  --type SecureString
```

### Deploy

```bash
# Add Helm repositories
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

# Install
helm upgrade --install loki-stack . \
  --namespace observability \
  --create-namespace \
  --values values.yaml
```

### Verify

```bash
# Check pods
kubectl get pods -n observability -l app.kubernetes.io/name=loki
kubectl get pods -n observability -l app.kubernetes.io/name=fluent-bit

# Check logs are flowing
kubectl logs -n observability -l app.kubernetes.io/name=fluent-bit --tail=50

# Port-forward to query
kubectl port-forward -n observability svc/loki-stack-gateway 3100:80

# Query via curl
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={k8s_namespace_name="default"}' \
  | jq .
```

## Grafana Integration

### Add Loki Data Source

1. In Grafana, go to **Configuration** → **Data Sources**
2. Click **Add data source**
3. Select **Loki**
4. Configure:
   - **Name**: Loki
   - **URL**: `http://loki-stack-gateway.observability.svc.cluster.local`
   - **Timeout**: 300s
5. Click **Save & Test**

### Example Dashboard

```json
{
  "dashboard": {
    "title": "Game Server Logs",
    "panels": [
      {
        "title": "Error Rate",
        "targets": [
          {
            "expr": "sum(rate({k8s_namespace_name=\"game-servers\"} |= \"error\" [5m])) by (k8s_labels_app)"
          }
        ]
      }
    ]
  }
}
```

## Troubleshooting

### Fluent Bit Not Collecting Logs

```bash
# Check Fluent Bit status
kubectl get pods -n observability -l app.kubernetes.io/name=fluent-bit

# Check logs
kubectl logs -n observability -l app.kubernetes.io/name=fluent-bit -f

# Verify configuration
kubectl exec -n observability -it $(kubectl get pod -n observability -l app.kubernetes.io/name=fluent-bit -o jsonpath='{.items[0].metadata.name}') -- fluent-bit -V

# Check metrics endpoint
kubectl port-forward -n observability $(kubectl get pod -n observability -l app.kubernetes.io/name=fluent-bit -o jsonpath='{.items[0].metadata.name}') 2020:2020

# Visit http://localhost:2020/api/v1/metrics/prometheus
```

### Loki Write Errors

```bash
# Check Loki write pods
kubectl get pods -n observability -l app.kubernetes.io/component=write

# Check logs
kubectl logs -n observability -l app.kubernetes.io/component=write --tail=100

# Check ingestion rate limits
kubectl port-forward -n observability svc/loki-stack-gateway 3100:80
curl http://localhost:3100/metrics | grep loki_distributor

# Common issues:
# - Ingestion rate limit exceeded
# - S3 permissions
# - Network policy blocking
```

### Queries Timing Out

```bash
# Check Loki read pods
kubectl get pods -n observability -l app.kubernetes.io/component=read

# Scale up read replicas
kubectl scale deployment/loki-stack-read \
  -n observability \
  --replicas=5

# Check query performance
kubectl logs -n observability -l app.kubernetes.io/component=read | grep "query"

# Optimize queries:
# - Add more label filters
# - Reduce time range
# - Use stream aggregation
```

### S3 Access Issues

```bash
# Check S3 secret
kubectl get secret -n observability loki-s3-credentials -o yaml

# Test S3 access from pod
kubectl run -n observability s3-test \
  --image=amazon/aws-cli \
  --rm -it \
  --command -- aws s3 ls s3://loki-chunks/

# Check IRSA annotation
kubectl describe sa -n observability loki | grep eks.amazonaws.com/role-arn

# Verify IAM role trust policy
aws iam get-role --role-name loki-s3-access
```

### High Memory Usage

```bash
# Check resource usage
kubectl top pods -n observability -l app.kubernetes.io/name=loki

# Adjust limits in values.yaml:
loki:
  write:
    resources:
      limits:
        memory: 16Gi  # Increase if needed

# Check chunk configuration
kubectl logs -n observability -l app.kubernetes.io/component=write | grep chunk

# Symptoms:
# - OOMKilled pods
# - Slow ingestion
# - High GC pressure
```

### Network Policy Issues

```bash
# Disable network policies temporarily
kubectl delete networkpolicy -n observability --all

# Test connectivity
kubectl run -n observability test-pod \
  --image=curlimages/curl \
  --rm -it \
  --command -- curl http://loki-stack-gateway/ready

# Re-enable one by one
kubectl apply -f templates/networkpolicy.yaml
```

## Monitoring & Alerts

### Key Metrics to Monitor

```promql
# Ingestion rate
sum(rate(loki_distributor_bytes_received_total[5m])) by (tenant)

# Query latency (p95)
histogram_quantile(0.95,
  rate(loki_request_duration_seconds_bucket{route="loki_api_v1_query_range"}[5m])
)

# Failed ingestion
sum(rate(loki_distributor_ingester_append_failures_total[5m]))

# Compactor runs
sum(rate(loki_compactor_runs_completed_total[5m]))

# Fluent Bit errors
sum(rate(fluentbit_output_errors_total[5m])) by (name)
```

### Recommended Alerts

```yaml
groups:
  - name: loki
    rules:
      - alert: LokiIngestionRateLimitReached
        expr: sum(rate(loki_distributor_ingester_appends_total[5m])) by (tenant) > 50
        for: 5m
        annotations:
          summary: "Loki ingestion rate limit reached"

      - alert: LokiCompactorNotRunning
        expr: absent(loki_compactor_runs_completed_total)
        for: 15m
        annotations:
          summary: "Loki compactor not running"

      - alert: FluentBitHighErrorRate
        expr: sum(rate(fluentbit_output_errors_total[5m])) > 10
        for: 5m
        annotations:
          summary: "Fluent Bit experiencing high error rate"
```

## Performance Tuning

### For High Volume (>1TB/day)

```yaml
loki:
  write:
    replicas: 10
    autoscaling:
      maxReplicas: 30
    resources:
      limits:
        memory: 16Gi

  loki:
    limits_config:
      ingestion_rate_mb: 100
      ingestion_burst_size_mb: 200
      max_streams_per_user: 200000
```

### For Cost Optimization

```yaml
loki:
  loki:
    limits_config:
      retention_period: 168h  # 7 days instead of 30

    compactor:
      retention_delete_worker_count: 300  # Faster deletion
```

### For Query Performance

```yaml
loki:
  read:
    replicas: 5
    resources:
      limits:
        memory: 8Gi  # More memory for cache

  loki:
    query_scheduler:
      max_outstanding_requests_per_tenant: 4096
```

## Security

### Network Policies
- Fluent Bit can only send to Loki
- Loki only accepts from Fluent Bit and Grafana
- Components communicate only as needed

### Secrets Management
- S3 credentials via External Secrets
- IRSA for pod-level S3 access
- No hardcoded credentials

### Multi-Tenancy
- Tenant ID: `game-platform`
- Can add more tenants with different retention/limits
- Separate by environment if needed

## Cost Estimation

### Infrastructure (assuming 1000 nodes)

```
Loki Write (3-15 replicas):
  - Average: 6 replicas × $0.05/hour = $216/month

Loki Read (3-10 replicas):
  - Average: 5 replicas × $0.03/hour = $108/month

Loki Backend (2 replicas):
  - 2 replicas × $0.03/hour = $43/month

Fluent Bit (1000 nodes):
  - Minimal overhead, no additional cost

Total Compute: ~$367/month
```

### Storage (assuming 100GB/day ingestion)

```
S3 Storage (30 days):
  - 3TB × $0.023/GB = $69/month

S3 Requests:
  - PUT: $5/month
  - GET: $0.40/month

Total Storage: ~$74/month
```

**Total Estimated Cost**: ~$441/month for 1000 nodes

## Roadmap

- [ ] Add alerting rules (Prometheus Ruler)
- [ ] Implement log sampling for high-volume services
- [ ] Add log-based metrics (derived metrics)
- [ ] Set up retention by tenant
- [ ] Implement global rate limiting
- [ ] Add log anonymization/redaction
- [ ] Multi-region replication

## References

- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)
- [Loki Simple Scalable Mode](https://grafana.com/docs/loki/latest/fundamentals/architecture/deployment-modes/#simple-scalable)

## Support

For issues or questions:
- Internal: #observability-team
- Runbook: [Loki Runbook](https://wiki.company.com/loki-runbook)
- Escalation: Platform Team on-call
