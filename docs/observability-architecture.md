# Observability Architecture - EKS Gaming Platform

## Executive Summary

This document describes the complete observability stack for the production gaming platform running on AWS EKS. The stack provides comprehensive visibility into:

- **Metrics**: Time-series data for resource utilization, performance, and business KPIs
- **Logs**: Structured event data for debugging and auditing
- **Traces**: Distributed request flows across microservices
- **Profiles**: Continuous profiling for performance optimization

### Stack at a Glance

| Signal | Technology | Storage | Retention | Query Interface |
|--------|-----------|---------|-----------|-----------------|
| Metrics | Prometheus + Thanos | S3 | 2h local, 1 year S3 | PromQL via Grafana |
| Logs | Fluent Bit + Loki | S3 | 30 days | LogQL via Grafana |
| Traces | OTel Collector + Tempo | S3 | 14 days | TraceQL via Grafana |
| Profiles | Pyroscope | S3 | 7 days | Flame graphs via Grafana |

**Design Principles**:
- Unified query experience through Grafana
- S3 for cost-effective long-term storage
- Separation of hot (query) and cold (storage) data
- Cloud-native, Kubernetes-first architecture
- Open-source, vendor-neutral stack

---

## Architecture Diagram

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          EKS Gaming Platform                                │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                    Application Services                               │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐             │  │
│  │  │Game API  │  │MatchMake │  │ Leaderbd │  │ Inventory│  ...        │  │
│  │  │          │  │          │  │          │  │          │             │  │
│  │  │ OTel SDK │  │ OTel SDK │  │ OTel SDK │  │ OTel SDK │             │  │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘             │  │
│  └───────┼─────────────┼─────────────┼─────────────┼────────────────────┘  │
│          │             │             │             │                       │
│          │ OTLP        │ OTLP        │ OTLP        │ OTLP                  │
│          │ (Traces,    │ (Traces,    │ (Traces,    │ (Traces,              │
│          │  Metrics)   │  Metrics)   │  Metrics)   │  Metrics)             │
│          │             │             │             │                       │
│  ┌───────▼─────────────▼─────────────▼─────────────▼────────────────────┐  │
│  │           OpenTelemetry Collector (DaemonSet)                        │  │
│  │  • Collect traces, metrics from apps                                 │  │
│  │  • Add K8s metadata                                                  │  │
│  │  • Forward to gateway                                                │  │
│  └────────────────────────────┬─────────────────────────────────────────┘  │
│                               │                                            │
│                               │ OTLP                                       │
│                               ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │         OpenTelemetry Collector Gateway (3 replicas)                │  │
│  │  • Central processing                                               │  │
│  │  • Tail sampling (keep errors, slow requests)                       │  │
│  │  • Batch and route to backends                                      │  │
│  └───────┬──────────────────────┬───────────────────────────────────────┘  │
│          │                      │                                          │
└──────────┼──────────────────────┼──────────────────────────────────────────┘
           │                      │
           │                      │
    ┌──────▼───────┐       ┌──────▼───────┐
    │   Metrics    │       │    Traces    │
    │              │       │              │
    │  Prometheus  │       │    Tempo     │
    │  (2 pods)    │       │ (distributed)│
    │     │        │       │      │       │
    │     ▼        │       │      ▼       │
    │   Thanos     │       │   Tempo      │
    │  Sidecar     │       │  Ingester    │
    │     │        │       │      │       │
    └─────┼────────┘       └──────┼───────┘
          │                       │
          │ Upload blocks         │ Upload blocks
          ▼                       ▼
    ┌─────────────────────────────────────┐
    │           AWS S3                    │
    │                                     │
    │  • thanos-metrics/                  │
    │  • tempo-traces/                    │
    │  • loki-logs/                       │
    │  • pyroscope-profiles/              │
    │                                     │
    │  Lifecycle: Standard → IA → Glacier │
    └─────────────────────────────────────┘
          │                       │
          │ Query blocks          │ Query blocks
          ▼                       ▼
    ┌─────────────────────────────────────┐
    │        Thanos Query                 │
    │        Tempo Query                  │
    │        Loki Query                   │
    │        Pyroscope Query              │
    └──────────────┬──────────────────────┘
                   │
                   │ Unified queries
                   ▼
    ┌─────────────────────────────────────┐
    │           Grafana                   │
    │                                     │
    │  • Dashboards                       │
    │  • Explore                          │
    │  • Alerting                         │
    │  • Correlations                     │
    └─────────────────────────────────────┘


┌──────────────────────────────────────────────────────────┐
│                   Logs Pipeline                          │
│                                                          │
│  Container logs → Fluent Bit (DaemonSet)                │
│                         │                                │
│                         ▼                                │
│                   Loki Distributor                       │
│                         │                                │
│                         ▼                                │
│                   Loki Ingester                          │
│                         │                                │
│                         ▼                                │
│                      S3 (loki-logs/)                     │
│                         │                                │
│                         ▼                                │
│                   Loki Querier                           │
│                         │                                │
│                         ▼                                │
│                      Grafana                             │
└──────────────────────────────────────────────────────────┘


┌──────────────────────────────────────────────────────────┐
│              Continuous Profiling Pipeline               │
│                                                          │
│  App pprof endpoints → Pyroscope Agent (scrape)         │
│                              │                           │
│  App SDK (push) ────────────▶│                           │
│                              ▼                           │
│                     Pyroscope Distributor                │
│                              │                           │
│                              ▼                           │
│                     Pyroscope Ingester                   │
│                              │                           │
│                              ▼                           │
│                   S3 (pyroscope-profiles/)               │
│                              │                           │
│                              ▼                           │
│                     Pyroscope Querier                    │
│                              │                           │
│                              ▼                           │
│                          Grafana                         │
└──────────────────────────────────────────────────────────┘
```

---

## Component Overview

### Metrics: Prometheus + Thanos

**Architecture**: Prometheus for recent data (2h), Thanos for long-term storage (1 year)

**Components**:

1. **Prometheus** (2 replicas, HA)
   - Scrapes metrics from Kubernetes components
   - ServiceMonitors for auto-discovery
   - Local TSDB with 2h retention
   - Thanos sidecar for S3 upload

2. **Thanos Sidecar**
   - Uploads Prometheus blocks to S3 every 2 hours
   - Enables querying recent local data

3. **Thanos Query Frontend** (2 replicas)
   - Query caching layer (reduces backend load)
   - Query splitting for large time ranges

4. **Thanos Query** (2 replicas)
   - Aggregates data from sidecars and store gateway
   - Deduplicates metrics from HA Prometheus

5. **Thanos Store Gateway** (2 replicas)
   - Queries historical data from S3
   - Index caching for performance

6. **Thanos Compactor** (1 replica)
   - Downsampling: raw → 5m → 1h
   - Block compaction for storage efficiency
   - Retention enforcement

**Data Flow**:
```
Targets → Prometheus → Local TSDB (2h) → Thanos Sidecar → S3
                                              ↓
                                        Store Gateway
                                              ↓
                                        Thanos Query
                                              ↓
                                           Grafana
```

**Storage Tiers**:
- **Hot** (0-2h): Prometheus local SSD (fast queries, expensive)
- **Warm** (2h-30d): S3 Standard (raw metrics)
- **Cold** (30d-90d): S3 IA (5-minute downsampled)
- **Archive** (90d-1y): S3 Glacier IR (1-hour downsampled)

**Scaling Triggers**:
- Active series > 10M per instance → Vertical scale or shard
- Query latency P99 > 5s → Add Thanos Query replicas
- Ingestion rate > 5M samples/s → Add Prometheus shard

---

### Logs: Fluent Bit + Loki

**Architecture**: Simple Scalable mode (separate read/write/backend components)

**Components**:

1. **Fluent Bit** (DaemonSet)
   - Runs on every node
   - Tails container logs from `/var/log/containers/`
   - Multiline parsing (stack traces)
   - Kubernetes metadata enrichment
   - Low memory footprint (~50Mi per node)

2. **Loki Gateway** (2 replicas)
   - NGINX reverse proxy
   - Load balancing for distributors
   - Rate limiting

3. **Loki Distributor** → **Loki Write** (3 replicas, HPA)
   - Ingests logs from Fluent Bit
   - Validates and rate-limits
   - Hashes streams to ingesters
   - Autoscales based on ingestion rate

4. **Loki Ingester** (part of Write component)
   - Buffers logs in memory
   - Creates compressed chunks
   - Uploads to S3

5. **Loki Querier** → **Loki Read** (3 replicas, HPA)
   - Executes LogQL queries
   - Reads from ingesters and S3
   - Autoscales based on query load

6. **Loki Compactor** → **Loki Backend** (2 replicas)
   - Compacts old chunks
   - Applies retention policies
   - Cleans up old data

**Data Flow**:
```
Pods → stdout/stderr → /var/log/containers/*.log
                              ↓
                        Fluent Bit (DaemonSet)
                              ↓
                      Loki Write (Ingester)
                              ↓
                         S3 (chunks/)
                              ↓
                     Loki Read (Querier)
                              ↓
                           Grafana
```

**Index vs Chunks**:
- **Index**: TSDB format, stores label combinations (fast lookups)
- **Chunks**: Compressed log data in S3 (bulk storage)

**Scaling Triggers**:
- Ingestion > 100 MB/s → Scale Write replicas
- Query latency > 5s → Scale Read replicas
- Compaction lag > 1h → Increase compactor resources

---

### Traces: OpenTelemetry Collector + Tempo

**Architecture**: Two-tier collection (agent + gateway) with distributed storage

**Components**:

1. **OpenTelemetry Collector Agent** (DaemonSet)
   - Collects traces from apps on each node
   - Adds Kubernetes metadata
   - Forwards to gateway

2. **OpenTelemetry Collector Gateway** (3 replicas, HPA)
   - Central processing
   - Tail sampling (keeps 100% errors, 100% slow, 10% others)
   - Batch optimization
   - Routes to Tempo

3. **Tempo Distributor** (3 replicas)
   - Receives traces via OTLP
   - Validates and rate-limits
   - Hashes to ingesters

4. **Tempo Ingester** (3 replicas)
   - Buffers traces in memory
   - Creates Parquet blocks
   - Uploads to S3

5. **Tempo Query Frontend** (2 replicas)
   - Query caching
   - Query splitting

6. **Tempo Querier** (2 replicas)
   - Executes TraceQL queries
   - Reads from S3

7. **Tempo Compactor** (1 replica)
   - Compacts small blocks
   - Enforces retention (14 days)

**Data Flow**:
```
App (OTel SDK) → OTel Agent → OTel Gateway (tail sampling)
                                      ↓
                              Tempo Distributor
                                      ↓
                              Tempo Ingester
                                      ↓
                               S3 (blocks/)
                                      ↓
                              Tempo Querier
                                      ↓
                                  Grafana
```

**Sampling Strategy**:
- **Head sampling** (app): 10% at SDK level (reduces network traffic)
- **Tail sampling** (gateway):
  - 100% of errors (status = error)
  - 100% of slow traces (> 2s)
  - 100% of critical events (e.g., payments)
  - 10% probabilistic for rest

**Scaling Triggers**:
- Ingestion latency > 1s → Scale distributors
- Query latency > 5s → Scale queriers
- Flush failures → Increase ingester memory

---

### Profiles: Pyroscope

**Architecture**: Distributed profiling with scraping and push modes

**Components**:

1. **Pyroscope Agent** (optional, for scraping)
   - Scrapes pprof endpoints from apps
   - Supports Go, Java, Python, Node.js

2. **Pyroscope Distributor** (2 replicas)
   - Receives profiles via push or scrape
   - Validates and rate-limits

3. **Pyroscope Ingester** (3 replicas)
   - Stores profiles in TSDB blocks
   - Uploads to S3

4. **Pyroscope Querier** (2 replicas)
   - Generates flame graphs
   - Supports diff views

5. **Pyroscope Store Gateway** (2 replicas)
   - Queries S3 for historical profiles

6. **Pyroscope Compactor** (1 replica)
   - Compacts blocks
   - Enforces 7-day retention

**Data Flow**:
```
App pprof endpoint → Pyroscope Agent (scrape)
                            ↓
App Pyroscope SDK ────────▶ Distributor
                            ↓
                        Ingester
                            ↓
                     S3 (blocks/)
                            ↓
                   Querier + Store Gateway
                            ↓
                         Grafana
```

**Profile Types**:
- **CPU**: Where time is spent (100 Hz sampling)
- **Memory**: Allocation and in-use objects
- **Goroutines**: Number of goroutines over time
- **Mutex**: Lock contention
- **Block**: Blocking operations

**Overhead**: < 2% CPU in production

---

## Data Retention Policies

### Metrics Retention

| Tier | Duration | Resolution | Storage | Cost/Month* |
|------|----------|-----------|---------|-------------|
| Hot (Prometheus) | 2 hours | Raw (15s) | Local SSD | Included in compute |
| Warm (S3 Standard) | 30 days | Raw (15s) | S3 Standard | $11.50 |
| Cold (S3 IA) | 90 days | 5-minute | S3 IA | $1.88 |
| Archive (S3 Glacier) | 1 year | 1-hour | Glacier IR | $0.40 |

*Estimated for 10M active series

**Total Metrics Storage Cost**: ~$14/month

### Logs Retention

| Tier | Duration | Storage | Cost/Month* |
|------|----------|---------|-------------|
| Hot | 7 days | S3 Standard | $16.10 |
| Warm | 23 days | S3 Intelligent-Tiering | $12.65 |

*Estimated for 100GB/day ingestion

**Total Logs Storage Cost**: ~$29/month

### Traces Retention

| Tier | Duration | Storage | Cost/Month* |
|------|----------|---------|-------------|
| Active | 14 days | S3 Standard | $23.00 |

*Estimated for 1TB/month with 10% sampling

**Total Traces Storage Cost**: ~$23/month

### Profiles Retention

| Tier | Duration | Storage | Cost/Month* |
|------|----------|---------|-------------|
| Active | 7 days | S3 Standard | $8-10 |

*Estimated for 50 services

**Total Profiles Storage Cost**: ~$10/month

### Audit Logs (Separate Bucket)

| Tier | Duration | Storage | Compliance |
|------|----------|---------|------------|
| Active | 90 days | S3 Standard | SOC 2, GDPR |

---

## Scaling Guidelines

### When to Scale Each Component

#### Prometheus

**Metrics to Monitor**:
```promql
# Ingestion rate (threshold: > 5M samples/s)
rate(prometheus_tsdb_head_samples_appended_total[5m])

# Active series (threshold: > 10M)
prometheus_tsdb_head_series

# Query latency P99 (threshold: > 5s)
histogram_quantile(0.99, rate(prometheus_http_request_duration_seconds_bucket[5m]))
```

**Scaling Options**:
1. **Vertical**: Increase CPU/memory (4 cores, 32Gi → 8 cores, 64Gi)
2. **Horizontal**: Enable sharding (split by namespace)
3. **Optimization**: Add metric relabeling to drop high-cardinality labels

#### Thanos Components

**Query/Query Frontend** (CPU-bound):
```promql
# Query latency P99 (threshold: > 10s)
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{handler="query"}[5m]))

# Query concurrency (threshold: > 80% of max)
sum(thanos_query_concurrent_gate_queries_in_flight)
```
→ Scale replicas from 2 to 4-6

**Store Gateway** (memory-bound):
```promql
# Cache hit rate (threshold: < 80%)
rate(thanos_store_index_cache_hits_total[5m]) /
rate(thanos_store_index_cache_requests_total[5m])
```
→ Increase memory and index cache size

#### Loki

**Write Component** (ingestion-bound):
```promql
# Ingestion rate (threshold: > 100 MB/s)
rate(loki_distributor_bytes_received_total[5m])
```
→ Scale from 3 to 10+ replicas (HPA configured)

**Read Component** (query-bound):
```promql
# Query latency P95 (threshold: > 5s)
histogram_quantile(0.95, rate(loki_request_duration_seconds_bucket{route="loki_api_v1_query_range"}[5m]))
```
→ Scale from 3 to 10 replicas (HPA configured)

#### Tempo

**Distributor**:
```promql
# Ingestion latency P99 (threshold: > 1s)
histogram_quantile(0.99, rate(tempo_request_duration_seconds_bucket{route="/tempopb.Pusher/Push"}[5m]))
```
→ Scale from 3 to 6+ replicas

**Ingester**:
```promql
# Flush failures (threshold: > 0)
rate(tempo_ingester_flush_failed_total[5m])
```
→ Increase memory, check S3 connectivity

**Querier**:
```promql
# Query latency P95 (threshold: > 5s)
histogram_quantile(0.95, rate(tempo_request_duration_seconds_bucket{route="/api/traces/{traceID}"}[5m]))
```
→ Scale from 2 to 4+ replicas

#### Pyroscope

**Ingester**:
```promql
# Storage usage (threshold: > 80% of disk)
sum(pyroscope_ingester_tsdb_storage_blocks_bytes) / sum(kubelet_volume_stats_capacity_bytes{persistentvolumeclaim=~"pyroscope-ingester.*"})
```
→ Increase PVC size or add replicas

**Querier**:
```promql
# Query duration P99 (threshold: > 10s)
histogram_quantile(0.99, rate(pyroscope_query_duration_seconds_bucket[5m]))
```
→ Scale from 2 to 4 replicas

---

## Resource Sizing Guide

### By Cluster Size

| Cluster | Nodes | Pods | Active Series | Prometheus | Thanos Query | Loki Write | Tempo Dist | Total Monthly Cost |
|---------|-------|------|---------------|------------|--------------|------------|------------|-------------------|
| Small | 100 | 2,000 | 500K | 1c/8Gi | 0.5c/2Gi | 1c/2Gi | 0.5c/1Gi | ~$300 |
| Medium | 500 | 10,000 | 2M | 2c/16Gi | 1c/4Gi | 2c/4Gi | 1c/2Gi | ~$600 |
| Large | 1,000 | 50,000 | 5M | 4c/32Gi | 2c/8Gi | 4c/8Gi | 2c/4Gi | ~$1,200 |
| X-Large | 3,000 | 100,000 | 10M | 8c/64Gi | 4c/16Gi | 6c/12Gi | 3c/6Gi | ~$2,400 |
| Ultra | 5,000 | 150,000 | 15M | 12c/96Gi | 6c/24Gi | 10c/16Gi | 4c/8Gi | ~$3,600 |

*Costs include compute only (EKS nodes), not S3 storage

---

## Cost Estimation

### Compute Costs (Per Month, at 1,000 nodes)

| Component | Instance Type | Count | Cost |
|-----------|--------------|-------|------|
| Prometheus | r6i.2xlarge | 2 | $735 |
| Thanos Query | t3.xlarge | 4 | $486 |
| Loki Write | r6i.xlarge | 6 | $1,102 |
| Loki Read | t3.xlarge | 5 | $608 |
| Tempo Distributor | t3.large | 3 | $228 |
| Tempo Ingester | r6i.xlarge | 3 | $551 |
| Pyroscope | t3.xlarge | 8 | $973 |
| Grafana | t3.medium | 1 | $30 |
| OTel Collector | t3.small | 3 | $45 |
| **Total Compute** | | | **$4,758** |

### Storage Costs (Per Month)

| Data Type | Volume | Storage Class | Cost |
|-----------|--------|---------------|------|
| Metrics (raw, 30d) | 500 GB | S3 Standard | $11.50 |
| Metrics (5m, 90d) | 150 GB | S3 IA | $1.88 |
| Metrics (1h, 1y) | 100 GB | Glacier IR | $0.40 |
| Logs (30d) | 3 TB | S3 Intelligent-Tiering | $29.00 |
| Traces (14d) | 1 TB | S3 Standard | $23.00 |
| Profiles (7d) | 350 GB | S3 Standard | $10.00 |
| **Total Storage** | | | **$75.78** |

### Total Observability Cost

**Monthly**: $4,758 (compute) + $76 (storage) = **$4,834/month**

**Per Node**: $4,834 / 1,000 nodes = **$4.83/node/month**

---

## Security Considerations

### IRSA (IAM Roles for Service Accounts)

All S3 access uses IRSA (no long-lived credentials):

```yaml
# Example ServiceAccount with IRSA
apiVersion: v1
kind: ServiceAccount
metadata:
  name: thanos
  namespace: observability
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/thanos-s3-access
```

**IAM Policy** (least privilege):
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ],
    "Resource": "arn:aws:s3:::thanos-metrics"
  }, {
    "Effect": "Allow",
    "Action": [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ],
    "Resource": "arn:aws:s3:::thanos-metrics/*"
  }]
}
```

### Network Policies

Restrict traffic between components:

```yaml
# Example: Only Grafana can query Prometheus
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prometheus-ingress
  namespace: observability
spec:
  podSelector:
    matchLabels:
      app: prometheus
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: grafana
    - podSelector:
        matchLabels:
          app: thanos-query
    ports:
    - protocol: TCP
      port: 9090
```

### Data Encryption

- **In Transit**: TLS for all inter-component communication
- **At Rest**:
  - S3 server-side encryption (AES-256)
  - EBS volumes encrypted (gp3-encrypted StorageClass)

### Secrets Management

Use External Secrets Operator for rotating credentials:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-admin-password
  namespace: observability
spec:
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: grafana-admin-password
  data:
  - secretKey: admin-password
    remoteRef:
      key: /observability/grafana/admin-password
```

### RBAC

Principle of least privilege for service accounts:

- Prometheus: Read-only access to Kubernetes API (discovery)
- Grafana: Read-only access to datasources (no admin API access)
- Compactors: Read/write to S3, no Kubernetes API access

---

## Disaster Recovery

### Backup Strategies

#### Metrics
- **Prometheus**: No backup needed (data in S3 via Thanos)
- **Thanos**: S3 versioning enabled, cross-region replication (optional)
- **Retention**: 1 year in S3 with lifecycle policies

#### Logs
- **Loki**: Chunks in S3 with versioning
- **Index**: Can be rebuilt from chunks (slow, avoid)
- **Backup**: S3 cross-region replication for compliance

#### Traces
- **Tempo**: Blocks in S3 with versioning
- **No separate backup**: Traces are ephemeral (14-day retention)

#### Profiles
- **Pyroscope**: Blocks in S3
- **No separate backup**: Profiles are ephemeral (7-day retention)

#### Configuration
- **Dashboards**: Stored in Git, auto-provisioned via ConfigMaps
- **Alerts**: Stored in Git as PrometheusRules
- **Datasources**: Provisioned via Helm values

### Recovery Procedures

#### Complete Cluster Loss

**Scenario**: EKS cluster destroyed, need to restore observability

**Recovery Time Objective (RTO)**: 2 hours
**Recovery Point Objective (RPO)**: 0 (no data loss, data in S3)

**Steps**:

1. **Provision new EKS cluster** (30 min)
   ```bash
   eksctl create cluster -f cluster.yaml
   ```

2. **Deploy observability stack** (60 min)
   ```bash
   # Prometheus + Thanos
   helm install prometheus-stack ./prometheus-stack -n observability

   # Loki
   helm install loki-stack ./loki-stack -n observability

   # Tempo
   helm install tempo-stack ./tempo -n observability

   # Pyroscope
   helm install pyroscope ./pyroscope -n observability

   # Grafana
   helm install grafana ./grafana -n observability
   ```

3. **Verify S3 connectivity** (10 min)
   ```bash
   # Check Thanos can query historical data
   kubectl logs -n observability -l app=thanos-query

   # Verify Loki can read chunks
   kubectl logs -n observability -l app=loki-read
   ```

4. **Restore Grafana state** (20 min)
   - Dashboards auto-provisioned from Git
   - Datasources auto-configured via Helm
   - Users restored from external IdP (OAuth)

**Result**: Historical data immediately available via S3 backends

#### S3 Bucket Deletion

**Scenario**: Accidental deletion of S3 bucket

**Mitigation**:
- S3 versioning enabled (can restore deleted objects)
- S3 MFA Delete enabled (requires MFA to delete bucket)
- Bucket policy denies deletion without specific role

**Recovery**:
```bash
# List deleted objects
aws s3api list-object-versions \
  --bucket thanos-metrics \
  --prefix "" \
  --output json \
  --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}'

# Restore deleted objects
aws s3api delete-object \
  --bucket thanos-metrics \
  --key <object-key> \
  --version-id <delete-marker-version-id>
```

#### Component Failure

**Prometheus down**: Thanos Query still serves historical data from S3
**Thanos Sidecar down**: Prometheus continues scraping, backlog uploaded when sidecar recovers
**Grafana down**: Metrics/logs/traces still collected, queries resume when Grafana returns

---

## Correlation and Unified Observability

### Logs ↔ Traces

**Add trace ID to logs**:

```go
// Go example
span := trace.SpanFromContext(ctx)
traceID := span.SpanContext().TraceID().String()

log.WithFields(log.Fields{
  "trace_id": traceID,
  "span_id":  span.SpanContext().SpanID().String(),
}).Info("Processing request")
```

**Query logs for a trace in Grafana**:
```logql
{namespace="game-services"} | json | trace_id="4bf92f3577b34da6a3ce929d0e0e4736"
```

### Traces → Logs (Trace View)

In Grafana, traces automatically link to logs if trace_id is present in log lines.

### Metrics → Traces (Exemplars)

Prometheus metrics can include trace IDs as exemplars:

```go
// Record metric with exemplar
histogram.ObserveWithExemplar(
  duration.Seconds(),
  prometheus.Labels{"traceID": traceID},
)
```

Query in Grafana shows trace samples for each metric bucket.

### Profiles → Traces

Correlate performance issues:
1. See high latency in trace (e.g., 5s for DB query)
2. Jump to profile for that time range
3. Identify hot function causing slowness

---

## Next Steps

1. **Deploy the stack**: Follow component-specific READMEs in `/apps/infra/observability/`
2. **Instrument applications**: See [Instrumentation Guide](./instrumentation-guide.md)
3. **Set up alerts**: See [Alerting Guide](./alerting-guide.md)
4. **Onboard SRE team**: See [SRE Runbook](./sre-runbook.md)
5. **Create dashboards**: Import standard dashboards, customize for your services

---

## References

- [Prometheus Stack README](../apps/infra/observability/prometheus-stack/README.md)
- [Loki Stack README](../apps/infra/observability/loki-stack/README.md)
- [Tempo README](../apps/infra/observability/tempo/README.md)
- [Pyroscope README](../apps/infra/observability/pyroscope/README.md)
- [OpenTelemetry Collector README](../apps/infra/observability/otel-collector/README.md)
- [Grafana Documentation](https://grafana.com/docs/)
- [AWS EKS Best Practices - Observability](https://aws.github.io/aws-eks-best-practices/observability/)
