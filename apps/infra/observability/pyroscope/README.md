# Grafana Pyroscope - Continuous Profiling

Production-ready continuous profiling stack for the gaming platform using Grafana Pyroscope.

## Overview

Continuous profiling helps identify performance bottlenecks in production by collecting and analyzing runtime profiles (CPU, memory, goroutines, etc.) with minimal overhead.

### What is Continuous Profiling?

Traditional profiling is done manually during development. Continuous profiling runs **automatically in production** to:
- Identify performance regressions immediately after deployment
- Find resource leaks before they cause outages
- Optimize hot paths based on real production traffic
- Compare performance across versions and deployments

### Why Pyroscope?

- **Low Overhead**: <2% CPU overhead in production
- **Multi-Language**: Go, Java, Node.js, Python, Rust, Ruby, .NET
- **Scalable**: Handles millions of profiles
- **Open Source**: No vendor lock-in
- **Grafana Integration**: Unified observability platform

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Pods                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ Go App   │  │ Java App │  │ Node App │  │ Python   │   │
│  │ pprof    │  │ async-   │  │ V8       │  │ py-spy   │   │
│  │ :6060    │  │ profiler │  │ profiler │  │ sidecar  │   │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘  └─────┬────┘   │
└────────┼─────────────┼─────────────┼─────────────┼─────────┘
         │             │             │             │
         │ Scrape      │ Push        │ Push        │ Scrape
         │             │             │             │
         └─────────────┴─────────────┴─────────────┘
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │     Pyroscope Distributor (2x)       │
         │    Rate Limiting & Validation        │
         └─────────────┬────────────────────────┘
                       │
                       ▼
         ┌──────────────────────────────────────┐
         │       Pyroscope Ingester (3x)        │
         │        Write-Ahead Log (WAL)         │
         │      TSDB Blocks (local disk)        │
         └─────────────┬────────────────────────┘
                       │
                       │ Flush blocks
                       ▼
         ┌──────────────────────────────────────┐
         │            S3 Storage                 │
         │    (Long-term profile storage)       │
         └──────────────┬───────────────────────┘
                        │
            ┌───────────┴───────────┐
            │                       │
            ▼                       ▼
  ┌─────────────────┐    ┌─────────────────┐
  │  Store Gateway  │    │   Compactor     │
  │  Index Headers  │    │  Block Merging  │
  │      (2x)       │    │  Downsampling   │
  └────────┬────────┘    └─────────────────┘
           │
           ▼
  ┌─────────────────┐
  │    Querier      │
  │  Query Engine   │
  │      (2x)       │
  └────────┬────────┘
           │
           ▼
  ┌─────────────────┐
  │ Query Frontend  │
  │ Query Splitting │
  │      (2x)       │
  └────────┬────────┘
           │
           ▼
  ┌─────────────────┐
  │     Grafana     │
  │  Flame Graphs   │
  │  Diff View      │
  └─────────────────┘
```

## Installation

### Prerequisites

1. **S3 Bucket** for profile storage:
```bash
aws s3 mb s3://gaming-platform-profiling-data --region us-west-2

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket gaming-platform-profiling-data \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Enable lifecycle policy (auto-delete after 7 days)
aws s3api put-bucket-lifecycle-configuration \
  --bucket gaming-platform-profiling-data \
  --lifecycle-configuration file://lifecycle-policy.json
```

2. **IAM Role** (IRSA) for Pyroscope components:
```bash
# Create IAM policy (see templates/pyroscope-s3-secret.yaml for policy document)
aws iam create-policy \
  --policy-name PyroscopeS3Access \
  --policy-document file://iam-policy.json

# Create IAM role with trust relationship
eksctl create iamserviceaccount \
  --name pyroscope-storage \
  --namespace observability \
  --cluster gaming-platform-prod \
  --attach-policy-arn arn:aws:iam::ACCOUNT_ID:policy/PyroscopeS3Access \
  --approve
```

3. **External Secrets** operator configured
4. **StorageClass** for persistent volumes (gp3-encrypted)

### Deploy Pyroscope

```bash
# Add Helm repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Deploy Pyroscope stack
helm upgrade --install pyroscope . \
  --namespace observability \
  --create-namespace \
  --values values.yaml \
  --wait \
  --timeout 10m
```

### Verify Installation

```bash
# Check all components are running
kubectl get pods -n observability -l app.kubernetes.io/name=pyroscope

# Check Pyroscope distributor is ready
kubectl port-forward -n observability svc/pyroscope-distributor 4040:4040

# Visit http://localhost:4040
```

## Instrumenting Applications

### Go Applications

#### Option 1: pprof HTTP Endpoint (Scraping)

```go
import (
    _ "net/http/pprof"
    "net/http"
)

func main() {
    // Enable pprof endpoint
    go func() {
        http.ListenAndServe("localhost:6060", nil)
    }()

    // Your app code
}
```

Add annotations to deployment:
```yaml
annotations:
  pyroscope.io/scrape: "true"
  pyroscope.io/language: "go"
  pyroscope.io/port: "6060"
  pyroscope.io/application-name: "my-app"
```

#### Option 2: Pyroscope SDK (Push)

```go
import "github.com/grafana/pyroscope-go"

func main() {
    pyroscope.Start(pyroscope.Config{
        ApplicationName: "my-app",
        ServerAddress:   "http://pyroscope-distributor.observability.svc.cluster.local:4040",
        ProfileTypes: []pyroscope.ProfileType{
            pyroscope.ProfileCPU,
            pyroscope.ProfileAllocObjects,
            pyroscope.ProfileInuseObjects,
            pyroscope.ProfileGoroutines,
        },
    })

    // Your app code
}
```

### Java Applications

Add Pyroscope Java agent to your container:

**Dockerfile:**
```dockerfile
FROM openjdk:17-slim

# Download Pyroscope Java agent
RUN wget https://github.com/grafana/pyroscope-java/releases/download/v0.12.0/pyroscope.jar \
    -O /app/pyroscope.jar

# Add agent to JVM
ENTRYPOINT ["java", \
  "-javaagent:/app/pyroscope.jar", \
  "-Dpyroscope.application.name=my-java-app", \
  "-Dpyroscope.server.address=http://pyroscope-distributor.observability.svc.cluster.local:4040", \
  "-Dpyroscope.format=jfr", \
  "-Dpyroscope.profiler.event=cpu,alloc,lock", \
  "-jar", "app.jar"]
```

**Deployment annotations:**
```yaml
annotations:
  pyroscope.io/scrape: "true"
  pyroscope.io/language: "java"
  pyroscope.io/application-name: "my-java-app"
  pyroscope.io/push-mode: "true"
```

### Node.js Applications

**Install SDK:**
```bash
npm install @pyroscope/nodejs
```

**Code:**
```javascript
const Pyroscope = require('@pyroscope/nodejs');

Pyroscope.init({
  serverAddress: 'http://pyroscope-distributor.observability.svc.cluster.local:4040',
  appName: 'my-nodejs-app',
  tags: {
    version: process.env.APP_VERSION,
  },
});

Pyroscope.start();
```

### Python Applications

**Install SDK:**
```bash
pip install pyroscope-io
```

**Code:**
```python
import pyroscope

pyroscope.configure(
    application_name="my-python-app",
    server_address="http://pyroscope-distributor.observability.svc.cluster.local:4040",
    tags={"version": "v1.0.0"},
)
```

## Using Pyroscope

### Accessing the UI

```bash
# Port-forward to query frontend
kubectl port-forward -n observability svc/pyroscope-query-frontend 4040:4040

# Open in browser
open http://localhost:4040
```

Or access via Grafana:
- Go to Explore
- Select Pyroscope datasource
- Query profiles

### Reading Flame Graphs

Flame graphs visualize where your application spends time:

```
┌────────────────────────────────────────────────┐ ◄── Root (main)
│               main()                           │
└─────────┬──────────────────────────────┬───────┘
          │                              │
┌─────────▼─────────┐          ┌─────────▼────────┐
│ handleRequest()   │          │  background()    │
│ (60% of time)     │          │  (40% of time)   │
└────────┬──────────┘          └──────────────────┘
         │
    ┌────┴────┐
    │         │
┌───▼────┐ ┌──▼────────┐
│ query  │ │  json     │
│ DB     │ │  marshal  │
│ (40%)  │ │  (20%)    │
└────────┘ └───────────┘
```

**What to look for:**
- **Wide bars** = functions consuming most CPU/memory
- **Tall stacks** = deep call chains (may indicate recursion issues)
- **Flat profiles** = tight loops without much nesting
- **Third-party libraries** = unexpected costs from dependencies

### Comparing Profiles

Compare before/after optimization:

1. **Select time range** for baseline (e.g., last week)
2. **Select comparison range** (e.g., after deployment)
3. **Use diff view** to see changes
   - Green = reduced CPU/memory (good!)
   - Red = increased CPU/memory (needs investigation)

### Common Performance Issues

#### 1. CPU Hotspots

**Symptom:** Single function consuming >50% of CPU time

**Example flame graph:**
```
main() ────────────────────────────────────
  └─ processData() ─────────────────────── (80%)
       └─ regexMatch() ───────────────────  (75%)
```

**Solution:** Optimize regex, cache compiled patterns

#### 2. Memory Allocations

**Symptom:** High allocation rate causing GC pressure

**Look for:**
- `runtime.mallocgc` appearing frequently
- String concatenation in loops
- Unnecessary JSON marshal/unmarshal

**Solution:** Pre-allocate buffers, use sync.Pool, optimize serialization

#### 3. Goroutine Leaks

**Symptom:** Goroutine count growing over time

**Use goroutine profile:**
```bash
# Check current goroutine count
curl http://localhost:6060/debug/pprof/goroutine?debug=1
```

**Look for:**
- Goroutines stuck in channel operations
- Forgotten context cancellations
- Missing timeouts

#### 4. Lock Contention

**Symptom:** High mutex wait times

**Use mutex profile:**
```go
runtime.SetMutexProfileFraction(1)
```

**Look for:**
- Hot mutex locks
- Coarse-grained locking
- Read-heavy locks using Mutex instead of RWMutex

#### 5. Blocking Operations

**Symptom:** Application appears slow despite low CPU

**Use block profile:**
```go
runtime.SetBlockProfileRate(1)
```

**Look for:**
- Channel operations blocking
- Synchronous I/O
- Network calls without timeouts

## Integration with Grafana

### Add Pyroscope Datasource

Datasource is automatically provisioned, or add manually:

1. Configuration → Data Sources → Add data source
2. Select Pyroscope
3. URL: `http://pyroscope-query-frontend.observability.svc.cluster.local:4040`
4. Save & Test

### Create Dashboards

Example dashboard panels:

**CPU Profile Panel:**
```json
{
  "datasource": "Pyroscope",
  "targets": [{
    "profileTypeId": "process_cpu:cpu:nanoseconds:cpu:nanoseconds",
    "labelSelector": "{app=\"game-server\"}",
    "queryType": "profile"
  }]
}
```

**Memory Allocation Panel:**
```json
{
  "datasource": "Pyroscope",
  "targets": [{
    "profileTypeId": "memory:alloc_objects:count:space:bytes",
    "labelSelector": "{app=\"game-server\"}",
    "queryType": "profile"
  }]
}
```

### Alerts

Create alerts based on profile queries:

**High CPU in Single Function:**
```yaml
- alert: HighCPUSingleFunction
  expr: |
    pyroscope_profile_cpu{function="expensiveOperation"} > 0.5
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Function {{ $labels.function }} consuming >50% CPU"
```

**Goroutine Leak:**
```yaml
- alert: GoroutineLeakDetected
  expr: |
    rate(pyroscope_profile_goroutine{app="game-server"}[5m]) > 10
  for: 15m
  labels:
    severity: critical
  annotations:
    summary: "Goroutine count growing rapidly in {{ $labels.app }}"
```

## Best Practices

### Production Configuration

1. **Low overhead** - Keep CPU profiling at 100 Hz (10ms sampling)
2. **Selective profiling** - Use annotations to profile only critical services
3. **Retention** - 7 days is sufficient for profiling data (it's large!)
4. **Tags** - Add version, environment, region tags for easier filtering
5. **Comparison** - Always compare profiles before/after changes

### Development vs Production

| Setting | Development | Production |
|---------|-------------|------------|
| CPU sampling rate | 250 Hz | 100 Hz |
| Memory sampling | 128KB | 512KB |
| Profile types | All | CPU, Memory only |
| Overhead | 5-10% | <2% |

### When to Profile

Profile continuously, but **analyze profiles when:**
- Deploying new versions (regression detection)
- Investigating performance issues
- Optimizing for cost (reduce CPU/memory usage)
- After load tests
- During incident response

### Performance Optimization Workflow

1. **Collect baseline profile** before changes
2. **Make optimization** (code change)
3. **Deploy to staging** with profiling enabled
4. **Run load test** with similar production traffic
5. **Compare profiles** to verify improvement
6. **Deploy to production** and monitor
7. **Compare production profiles** to confirm

## Troubleshooting

### No Profiles Appearing

**Check pod annotations:**
```bash
kubectl get pod my-app-xxx -o jsonpath='{.metadata.annotations}'
```

**Check Pyroscope agent logs:**
```bash
kubectl logs -n observability -l app.kubernetes.io/component=agent
```

**Verify pprof endpoint:**
```bash
kubectl port-forward my-app-xxx 6060:6060
curl http://localhost:6060/debug/pprof/
```

### High Profiler Overhead

**Symptoms:**
- Application CPU usage increased >5% after enabling profiling
- Application latency increased

**Solutions:**
- Reduce CPU sampling rate
- Increase memory sampling threshold
- Use eBPF profiling (lower overhead)
- Profile subset of pods (e.g., 10%)

### S3 Access Issues

**Check IRSA configuration:**
```bash
# Verify service account has role annotation
kubectl get sa pyroscope-storage -n observability -o yaml

# Check pod has service account
kubectl get pod -n observability -l app.kubernetes.io/component=ingester \
  -o jsonpath='{.items[0].spec.serviceAccountName}'

# Test S3 access from pod
kubectl exec -n observability pyroscope-ingester-0 -- \
  aws s3 ls s3://gaming-platform-profiling-data/
```

### Ingesters Not Writing Blocks

**Check ingester logs:**
```bash
kubectl logs -n observability -l app.kubernetes.io/component=ingester
```

**Common issues:**
- S3 permission denied
- Disk full (WAL directory)
- Network issues to S3

**Verify block uploads:**
```bash
aws s3 ls s3://gaming-platform-profiling-data/ --recursive | head -20
```

### Query Performance Issues

**Symptoms:**
- Slow flame graph loading
- Query timeouts

**Solutions:**
- Reduce query time range
- Add more queriers (scale up)
- Check store-gateway cache hit rate
- Verify compaction is running

**Check compactor:**
```bash
kubectl logs -n observability -l app.kubernetes.io/component=compactor
```

## Maintenance

### Monitoring Pyroscope

Key metrics to monitor:

```promql
# Ingestion rate
rate(pyroscope_distributor_received_samples_total[5m])

# Query latency
histogram_quantile(0.99, rate(pyroscope_query_duration_seconds_bucket[5m]))

# Storage usage
sum(pyroscope_ingester_tsdb_storage_blocks_bytes) by (pod)

# Compaction lag
pyroscope_compactor_last_successful_run_timestamp_seconds
```

### Scaling

**Scale distributors** (if ingestion rate is high):
```bash
kubectl scale deployment pyroscope-distributor -n observability --replicas=4
```

**Scale ingesters** (if write throughput is high):
```bash
kubectl scale statefulset pyroscope-ingester -n observability --replicas=5
```

**Scale queriers** (if query latency is high):
```bash
kubectl scale deployment pyroscope-querier -n observability --replicas=4
```

### Cleanup

Delete old profiles from S3 (handled by lifecycle policy):
```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket gaming-platform-profiling-data
```

## Cost Optimization

**Storage costs:**
- Profiling data: ~1GB per service per day
- With 50 services: ~50GB/day = ~1.5TB/month
- S3 Standard: ~$35/month for 1.5TB
- 7-day retention: ~$8-10/month

**Compute costs:**
- Minimal (most components are lightweight)
- Ingesters: Most resource-intensive (memory for WAL)
- Use spot instances for non-critical components

**Reduce costs:**
- Profile subset of pods (10-20%)
- Lower sampling rates
- Shorter retention (3-5 days)
- Use S3 Intelligent-Tiering

## Resources

- **Pyroscope Documentation**: https://grafana.com/docs/pyroscope/
- **Flame Graph Guide**: https://www.brendangregg.com/flamegraphs.html
- **Go pprof**: https://go.dev/blog/pprof
- **async-profiler**: https://github.com/async-profiler/async-profiler
- **eBPF Profiling**: https://www.polarsignals.com/blog/posts/2022/11/29/profiling-without-instrumentation

## Support

For issues or questions:
- Slack: `#observability` or `#performance`
- Runbook: [Performance Troubleshooting](../../docs/runbooks/performance.md)
- Oncall: DevOps/SRE team
