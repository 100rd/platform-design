# Prometheus Stack - Production Observability for Large-Scale EKS

Production-ready Prometheus + Thanos + Grafana stack designed for large-scale Kubernetes clusters running 1,000-5,000 nodes and 100,000+ pods.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Query Layer                               │
│  ┌──────────────────┐      ┌──────────────────┐                │
│  │  Grafana         │─────▶│  Thanos Query    │                │
│  │  Dashboards      │      │  Frontend        │                │
│  └──────────────────┘      └────────┬─────────┘                │
│                                      │                           │
│                             ┌────────▼─────────┐                │
│                             │  Thanos Query    │                │
│                             └────────┬─────────┘                │
│                                      │                           │
└──────────────────────────────────────┼───────────────────────────┘
                                       │
┌──────────────────────────────────────┼───────────────────────────┐
│                      Storage Layer   │                           │
│                                      │                           │
│  ┌──────────────────┐      ┌────────▼─────────┐                │
│  │  Prometheus      │─────▶│  Thanos Sidecar  │                │
│  │  (2h retention)  │      │                  │                │
│  └──────────────────┘      └────────┬─────────┘                │
│                                      │                           │
│                             ┌────────▼─────────┐                │
│                             │  Thanos Store    │◀───────────┐   │
│                             │  Gateway         │            │   │
│                             └──────────────────┘            │   │
│                                                             │   │
│                             ┌──────────────────┐            │   │
│                             │  Thanos          │            │   │
│                             │  Compactor       │────────────┘   │
│                             └────────┬─────────┘                │
│                                      │                           │
└──────────────────────────────────────┼───────────────────────────┘
                                       │
                                       ▼
                            ┌──────────────────┐
                            │  S3 Bucket       │
                            │  (1y retention)  │
                            │  - Raw: 30d      │
                            │  - 5m: 90d       │
                            │  - 1h: 1y        │
                            └──────────────────┘
```

### Components

1. **Prometheus** (kube-prometheus-stack)
   - 2 replicas for HA
   - 2h local retention (SSD)
   - Thanos sidecar enabled
   - Functional sharding ready

2. **Thanos**
   - Query Frontend: Caching layer (Memcached)
   - Query: Aggregates data from sidecars and store gateway
   - Store Gateway: Queries historical data from S3
   - Compactor: Downsampling and retention management
   - Bucket Web: S3 bucket browser

3. **Grafana**
   - Pre-configured dashboards
   - Multiple data sources (Prometheus, Thanos, Loki, Tempo, Pyroscope)
   - OAuth/SSO ready

4. **Alertmanager**
   - 3 replicas for HA
   - Slack + PagerDuty integration
   - Intelligent alert routing

## Scale Characteristics

| Metric | Value | Notes |
|--------|-------|-------|
| Nodes | 1,000 - 5,000 | Tested at ultra-scale |
| Pods | 100,000+ | With metric relabeling |
| Active Series | ~10M | @ 5K nodes, 100K pods |
| Ingestion Rate | 5M samples/s | Per Prometheus instance |
| Query Latency | P99 < 5s | With Thanos caching |
| Local Retention | 2h | SSD storage |
| Long-term Retention | 1y | S3 with downsampling |
| Storage Cost | ~$500/mo | @ 10M series |

## Prerequisites

### Required Components

1. **EKS Cluster** (v1.27+)
   - IRSA (IAM Roles for Service Accounts) enabled
   - VPC CNI with prefix delegation
   - Karpenter for node scaling

2. **AWS Resources**
   - S3 bucket for Thanos
   - IAM role with S3 access
   - Secrets Manager (optional, for credentials)

3. **Kubernetes Operators**
   - External Secrets Operator (recommended)
   - Prometheus Operator (installed by chart)

### Optional Components

- **Loki** for log aggregation
- **Tempo** for distributed tracing
- **Pyroscope** for continuous profiling
- **ArgoCD** for GitOps deployment

## Installation

### 1. Create S3 Bucket (Terraform)

```hcl
# terraform/s3-thanos.tf
resource "aws_s3_bucket" "thanos" {
  bucket = "thanos-metrics-${var.cluster_name}-${var.region}"

  tags = {
    Name        = "Thanos Metrics Storage"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "thanos" {
  bucket = aws_s3_bucket.thanos.id

  rule {
    id     = "retention"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "thanos" {
  bucket = aws_s3_bucket.thanos.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

### 2. Create IAM Role for IRSA

```hcl
# terraform/iam-thanos.tf
data "aws_iam_policy_document" "thanos_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:monitoring:thanos"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "thanos" {
  name               = "thanos-s3-access-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.thanos_assume_role.json

  tags = {
    Name        = "Thanos S3 Access"
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "thanos_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      aws_s3_bucket.thanos.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.thanos.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "thanos_s3" {
  name   = "thanos-s3-policy"
  role   = aws_iam_role.thanos.id
  policy = data.aws_iam_policy_document.thanos_s3.json
}

output "thanos_iam_role_arn" {
  value       = aws_iam_role.thanos.arn
  description = "IAM role ARN for Thanos ServiceAccount"
}
```

### 3. Install via Helm

```bash
# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Create namespace
kubectl create namespace monitoring

# Install Prometheus Stack
helm upgrade --install prometheus-stack . \
  --namespace monitoring \
  --values values.yaml \
  --values values-thanos.yaml \
  --set kube-prometheus-stack.prometheus.prometheusSpec.externalLabels.cluster=eks-us-east-1 \
  --set thanos.serviceAccount.annotations."eks\.amazonaws\.io/role-arn"=arn:aws:iam::123456789012:role/thanos-s3-access \
  --wait \
  --timeout 10m
```

### 4. Verify Installation

```bash
# Check pods
kubectl get pods -n monitoring

# Expected output:
# prometheus-stack-kube-prometheus-prometheus-0          3/3     Running
# prometheus-stack-kube-prometheus-prometheus-1          3/3     Running
# prometheus-stack-grafana-xxx                           1/1     Running
# prometheus-stack-kube-prometheus-alertmanager-0        2/2     Running
# prometheus-stack-kube-prometheus-alertmanager-1        2/2     Running
# prometheus-stack-kube-prometheus-alertmanager-2        2/2     Running
# prometheus-stack-kube-state-metrics-xxx                1/1     Running
# prometheus-stack-node-exporter-xxx (DaemonSet)         1/1     Running
# thanos-query-xxx                                       1/1     Running
# thanos-query-frontend-xxx                              1/1     Running
# thanos-storegateway-xxx                                1/1     Running
# thanos-compactor-xxx                                   1/1     Running

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prometheus-prometheus 9090:9090
# Open: http://localhost:9090/targets

# Check Grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
# Open: http://localhost:3000
# Default credentials: admin / changeme
```

## Configuration

### Scaling Considerations

#### When to Scale Prometheus

Monitor these metrics to decide when to scale:

```promql
# Ingestion rate per Prometheus instance
rate(prometheus_tsdb_head_samples_appended_total[5m])
# Threshold: > 5M samples/s per instance

# Active series count
prometheus_tsdb_head_series
# Threshold: > 10M series per instance

# Query latency P99
histogram_quantile(0.99, rate(prometheus_http_request_duration_seconds_bucket[5m]))
# Threshold: > 5s
```

**Scaling Options:**

1. **Vertical Scaling** (increase resources)
   ```yaml
   prometheus:
     prometheusSpec:
       resources:
         requests:
           cpu: 8000m      # Up from 4000m
           memory: 64Gi    # Up from 32Gi
         limits:
           cpu: 16000m
           memory: 128Gi
   ```

2. **Horizontal Scaling** (sharding)
   ```yaml
   prometheus:
     prometheusSpec:
       shards: 2  # Split workload across 2 Prometheus instances

       # Shard 0: System namespaces
       # Shard 1: Application namespaces

       # Configure via ServiceMonitor labels:
       serviceMonitorSelector:
         matchExpressions:
         - key: prometheus-shard
           operator: In
           values:
           - shard-$(SHARD_ID)
   ```

#### When to Scale Thanos Components

**Query/Query Frontend:**
```promql
# Query latency
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{handler="query"}[5m]))
# Threshold: > 10s

# Query concurrency
sum(thanos_query_concurrent_gate_queries_in_flight)
# Threshold: > 80% of max_concurrent
```

Scale by increasing replicas:
```yaml
thanos:
  query:
    replicaCount: 4  # Up from 2
  queryFrontend:
    replicaCount: 4  # Up from 2
```

**Store Gateway:**
```promql
# Index cache hit rate
rate(thanos_store_index_cache_hits_total[5m]) / rate(thanos_store_index_cache_requests_total[5m])
# Threshold: < 80%
```

Increase index cache size:
```yaml
thanos:
  storegateway:
    resources:
      requests:
        memory: 8Gi   # Up from 4Gi
    extraFlags:
    - --index-cache-size=4GB  # Up from 2GB
```

### Resource Sizing Guide

| Cluster Size | Active Series | Prometheus CPU | Prometheus Memory | Storage (2h) |
|--------------|---------------|----------------|-------------------|--------------|
| 100 nodes | 500K | 1 core | 8Gi | 10Gi |
| 500 nodes | 2M | 2 cores | 16Gi | 20Gi |
| 1000 nodes | 5M | 4 cores | 32Gi | 50Gi |
| 3000 nodes | 10M | 8 cores | 64Gi | 100Gi |
| 5000 nodes | 15M | 12 cores | 96Gi | 150Gi |

### Alert Routing

Customize alertmanager routing in `values.yaml`:

```yaml
alertmanager:
  alertmanagerSpec:
    config:
      route:
        routes:
        # Example: Route by namespace
        - matchers:
          - namespace = production
          receiver: 'pagerduty-prod'
          continue: true

        # Example: Route by severity
        - matchers:
          - severity = critical
          receiver: 'pagerduty-critical'
          group_wait: 10s

        # Example: Route by team label
        - matchers:
          - team = backend
          receiver: 'slack-backend'
```

### Grafana Data Sources

Configure additional data sources in `values.yaml`:

```yaml
grafana:
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
      # Add custom Prometheus
      - name: Prometheus-Production
        type: prometheus
        url: http://prometheus-production:9090
        access: proxy

      # Add Mimir/Cortex
      - name: Mimir
        type: prometheus
        url: http://mimir-query-frontend:8080/prometheus
        access: proxy
```

## Monitoring the Monitoring Stack

### Key Metrics to Watch

**Prometheus Health:**
```promql
# WAL corruption
prometheus_tsdb_wal_corruptions_total

# Compaction failures
prometheus_tsdb_compactions_failed_total

# Out of order samples (indicates clock skew)
rate(prometheus_tsdb_out_of_order_samples_total[5m])

# Memory usage
process_resident_memory_bytes{job="prometheus"}
```

**Thanos Health:**
```promql
# Sidecar upload failures
rate(thanos_objstore_bucket_operation_failures_total[5m])

# Store Gateway sync issues
thanos_blocks_meta_sync_failures_total

# Compactor failures
thanos_compact_group_compactions_failures_total
```

### Dashboards

Pre-installed dashboards:

1. **Kubernetes Cluster** (GrafanaID: 7249)
   - Overview of cluster resources
   - Node, pod, namespace metrics

2. **Node Exporter Full** (GrafanaID: 1860)
   - Detailed node-level metrics
   - CPU, memory, disk, network

3. **Prometheus Stats** (GrafanaID: 19105)
   - Prometheus internal metrics
   - Ingestion rate, storage, queries

4. **Karpenter** (GrafanaID: 20524)
   - Node provisioning metrics
   - Consolidation savings

5. **ArgoCD** (custom)
   - Application sync status
   - Deployment health

### SLO Dashboards

Create custom SLO dashboard:

```json
{
  "dashboard": {
    "title": "Platform SLOs",
    "panels": [
      {
        "title": "API Server Availability",
        "targets": [
          {
            "expr": "apiserver:availability:sli * 100"
          }
        ],
        "thresholds": [
          { "value": 99.95, "color": "red" },
          { "value": 99.99, "color": "green" }
        ]
      },
      {
        "title": "Error Budget Remaining",
        "targets": [
          {
            "expr": "apiserver:error_budget:remaining:30d * 100"
          }
        ]
      }
    ]
  }
}
```

## Troubleshooting

### Common Issues

#### 1. High Memory Usage

**Symptom:** Prometheus OOMKilled

**Diagnosis:**
```bash
# Check active series
kubectl exec -n monitoring prometheus-stack-kube-prometheus-prometheus-0 -c prometheus -- \
  promtool tsdb analyze /prometheus

# Check top series by metric name
kubectl exec -n monitoring prometheus-stack-kube-prometheus-prometheus-0 -c prometheus -- \
  promtool tsdb analyze /prometheus --limit=20
```

**Solution:**
1. Add metric relabeling to drop high-cardinality metrics
2. Increase memory limits
3. Enable sharding

#### 2. Thanos Sidecar Upload Failures

**Symptom:** `thanos_objstore_bucket_operation_failures_total` increasing

**Diagnosis:**
```bash
# Check sidecar logs
kubectl logs -n monitoring prometheus-stack-kube-prometheus-prometheus-0 -c thanos-sidecar

# Verify IRSA permissions
kubectl describe sa -n monitoring thanos

# Test S3 access
kubectl run -n monitoring aws-cli --rm -it --image amazon/aws-cli -- \
  s3 ls s3://thanos-metrics-us-east-1/
```

**Solution:**
1. Verify IAM role ARN in ServiceAccount annotation
2. Check S3 bucket policy
3. Verify OIDC provider configuration

#### 3. Slow Queries

**Symptom:** Grafana dashboards timing out

**Diagnosis:**
```promql
# Check query duration
topk(10,
  rate(prometheus_http_request_duration_seconds_sum{handler="query"}[5m])
  /
  rate(prometheus_http_request_duration_seconds_count{handler="query"}[5m])
)

# Check concurrent queries
prometheus_engine_queries
```

**Solution:**
1. Reduce query time range
2. Use recording rules for complex queries
3. Enable Thanos query caching
4. Optimize PromQL queries

#### 4. Alert Fatigue

**Symptom:** Too many alerts firing

**Solution:**
1. Review and tune alert thresholds
2. Add inhibition rules to prevent cascading alerts
3. Implement alert grouping by namespace/team
4. Use silence rules for maintenance windows

### Debug Commands

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090/targets

# Check Alertmanager alerts
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prometheus-alertmanager 9093:9093
# Visit: http://localhost:9093

# Check Thanos Store Gateway blocks
kubectl port-forward -n monitoring svc/thanos-storegateway 10902:10902
# Visit: http://localhost:10902/stores

# Check Thanos Bucket Web
kubectl port-forward -n monitoring svc/thanos-bucketweb 8080:8080
# Visit: http://localhost:8080

# Tail Prometheus logs
kubectl logs -n monitoring prometheus-stack-kube-prometheus-prometheus-0 -c prometheus -f

# Exec into Prometheus pod
kubectl exec -n monitoring prometheus-stack-kube-prometheus-prometheus-0 -c prometheus -- /bin/sh
```

## Cost Optimization

### Storage Costs

**S3 Storage (estimated):**
- Raw metrics (30d): ~500 GB @ $0.023/GB = $11.50/mo
- Downsampled 5m (90d): ~150 GB @ $0.0125/GB (IA) = $1.88/mo
- Downsampled 1h (1y): ~100 GB @ $0.004/GB (Glacier IR) = $0.40/mo

**Total: ~$14/mo for 10M active series**

### Compute Costs

**EKS Node Costs (estimated):**
- Prometheus (2x r6i.2xlarge): 2 × $0.504/h × 730h = $735/mo
- Thanos (4x t3.xlarge): 4 × $0.1664/h × 730h = $486/mo
- Grafana (1x t3.medium): 1 × $0.0416/h × 730h = $30/mo

**Total: ~$1,251/mo**

### Optimization Tips

1. **Use Karpenter for compute**
   - Right-size instances
   - Use Spot for non-critical components

2. **Aggressive metric relabeling**
   - Drop unnecessary metrics
   - Reduce label cardinality

3. **S3 Intelligent-Tiering**
   - Automatic cost optimization
   - ~30% savings

4. **Recording rules**
   - Pre-compute expensive queries
   - Reduce query load

## Security Considerations

### Network Policies

```yaml
# Example: Restrict Prometheus access
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prometheus-network-policy
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: prometheus
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from Grafana
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: grafana
    ports:
    - protocol: TCP
      port: 9090
  # Allow from Thanos Query
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/component: query
    ports:
    - protocol: TCP
      port: 10901
  egress:
  # Allow to kube-apiserver
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
  # Allow to S3 (via VPC endpoint)
  - to:
    - podSelector:
        matchLabels:
          app: aws-vpc-endpoint
```

### RBAC

The chart creates appropriate RBAC:
- ServiceAccount with minimal permissions
- ClusterRole for resource discovery
- RoleBinding scoped to monitoring namespace

### Secrets Management

**Best Practice:** Use External Secrets Operator

```yaml
# Example: Grafana admin password from AWS Secrets Manager
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-admin-credentials
  namespace: monitoring
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: grafana-admin-credentials
  data:
  - secretKey: admin-password
    remoteRef:
      key: monitoring/grafana
      property: admin-password
```

## Upgrade Guide

### Backup Before Upgrade

```bash
# Export Prometheus data (last 2h)
kubectl port-forward -n monitoring prometheus-stack-kube-prometheus-prometheus-0 9090:9090 &
promtool tsdb dump /prometheus --min-time=$(date -u -d '2 hours ago' +%s)000 --max-time=$(date -u +%s)000 > backup.json

# Export Grafana dashboards
kubectl get configmaps -n monitoring -l grafana_dashboard=1 -o yaml > grafana-dashboards-backup.yaml

# Export PrometheusRules
kubectl get prometheusrules -n monitoring -o yaml > prometheus-rules-backup.yaml
```

### Upgrade Process

```bash
# Update chart dependencies
helm dependency update

# Test upgrade (dry-run)
helm upgrade prometheus-stack . \
  --namespace monitoring \
  --values values.yaml \
  --values values-thanos.yaml \
  --dry-run \
  --debug

# Perform upgrade
helm upgrade prometheus-stack . \
  --namespace monitoring \
  --values values.yaml \
  --values values-thanos.yaml \
  --wait \
  --timeout 15m

# Verify upgrade
kubectl get pods -n monitoring
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=100
```

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Thanos Documentation](https://thanos.io/tip/thanos/getting-started.md/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Grafana Documentation](https://grafana.com/docs/)
- [AWS EKS Best Practices - Observability](https://aws.github.io/aws-eks-best-practices/observability/)
- [SLO/Error Budget Guide](https://sre.google/workbook/implementing-slos/)

## Support

For issues or questions:
- Platform Team Slack: #platform-observability
- On-call: PagerDuty "Platform-Monitoring"
- Runbooks: https://runbooks.internal.example.com/
