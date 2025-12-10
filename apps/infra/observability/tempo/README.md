# Tempo Distributed Tracing Stack

Production-ready distributed tracing system using Grafana Tempo with OpenTelemetry support for the gaming platform.

## Architecture Overview

### Component Breakdown

```
┌─────────────────────────────────────────────────────────────────┐
│                     Trace Ingestion Layer                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Distributor (3 replicas)                     │  │
│  │  • OTLP gRPC :4317                                        │  │
│  │  • OTLP HTTP :4318                                        │  │
│  │  • Jaeger gRPC :14250, HTTP :14268                        │  │
│  │  • Zipkin :9411                                           │  │
│  │  • Rate limiting & validation                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                            │                                     │
│                            ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Ingester (3 replicas)                        │  │
│  │  • Buffers traces                                         │  │
│  │  • Creates blocks                                         │  │
│  │  • Writes to S3                                           │  │
│  │  • 50Gi local storage per replica                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      Storage Layer (S3)                          │
├─────────────────────────────────────────────────────────────────┤
│  • 14-day retention                                              │
│  • Zstd compression                                              │
│  • Bloom filters for fast lookups                                │
│  • Automatic compaction                                          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      Query Layer                                 │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Query Frontend (2 replicas)                       │  │
│  │  • Query caching                                          │  │
│  │  • Query splitting                                        │  │
│  │  • Request queuing                                        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                            │                                     │
│                            ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │            Querier (2 replicas)                           │  │
│  │  • Reads from S3                                          │  │
│  │  • TraceQL execution                                      │  │
│  │  • Search execution                                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    Background Jobs                               │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Compactor (1 replica)                             │  │
│  │  • Block compaction                                       │  │
│  │  • Retention enforcement                                  │  │
│  │  • Index optimization                                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │      Metrics Generator (1 replica)                        │  │
│  │  • RED metrics from traces                                │  │
│  │  • Service graphs                                         │  │
│  │  • Remote write to Prometheus                             │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Features

- **Multi-protocol ingestion**: OTLP, Jaeger, Zipkin
- **Scalable architecture**: Independent scaling of all components
- **Efficient storage**: S3 backend with compression and bloom filters
- **Fast queries**: TraceQL support with caching
- **Metrics generation**: Automatic RED metrics from traces
- **High availability**: Multi-replica deployment with anti-affinity

## Deployment

### Prerequisites

1. **EKS Cluster** with kubectl configured
2. **Helm 3** installed
3. **S3 bucket** created for trace storage
4. **AWS credentials** stored in AWS Secrets Manager
5. **External Secrets Operator** installed (for S3 credentials)
6. **Prometheus Operator** installed (for ServiceMonitor)

### S3 Bucket Setup

```bash
# Create S3 bucket
aws s3 mb s3://tempo-traces-prod --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket tempo-traces-prod \
  --versioning-configuration Status=Enabled

# Set lifecycle policy for cost optimization
cat > lifecycle.json <<EOF
{
  "Rules": [{
    "Id": "DeleteOldTraces",
    "Status": "Enabled",
    "Prefix": "traces/",
    "Expiration": {
      "Days": 14
    }
  }]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
  --bucket tempo-traces-prod \
  --lifecycle-configuration file://lifecycle.json
```

### Store S3 Credentials in AWS Secrets Manager

```bash
# Create secret with S3 credentials
aws secretsmanager create-secret \
  --name tempo/s3-credentials \
  --description "S3 credentials for Tempo trace storage" \
  --secret-string '{
    "access_key_id": "YOUR_ACCESS_KEY",
    "secret_access_key": "YOUR_SECRET_KEY"
  }'
```

### Install Tempo Stack

```bash
# Add Grafana Helm repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Tempo stack
helm install tempo-stack . \
  --namespace observability \
  --create-namespace \
  --values values.yaml \
  --values values-override.yaml

# Verify deployment
kubectl get pods -n observability -l app.kubernetes.io/name=tempo-distributed

# Check distributor is receiving traces
kubectl logs -n observability -l app.kubernetes.io/component=distributor
```

### Verify Installation

```bash
# Check all components are running
kubectl get pods -n observability -l app=tempo

# Expected output:
# tempo-stack-distributor-0        1/1  Running
# tempo-stack-distributor-1        1/1  Running
# tempo-stack-distributor-2        1/1  Running
# tempo-stack-ingester-0           1/1  Running
# tempo-stack-ingester-1           1/1  Running
# tempo-stack-ingester-2           1/1  Running
# tempo-stack-querier-0            1/1  Running
# tempo-stack-querier-1            1/1  Running
# tempo-stack-query-frontend-0     1/1  Running
# tempo-stack-query-frontend-1     1/1  Running
# tempo-stack-compactor-0          1/1  Running
# tempo-stack-metrics-generator-0  1/1  Running

# Check services
kubectl get svc -n observability -l app=tempo

# Port-forward to query frontend (for testing)
kubectl port-forward -n observability svc/tempo-stack-query-frontend 3100:3100
```

## Application Instrumentation

### OpenTelemetry SDK Configuration

#### Option 1: OpenTelemetry Collector (Recommended)

Deploy OTEL Collector as a DaemonSet or sidecar:

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024

  resource:
    attributes:
      - key: cluster.name
        value: gaming-platform-prod
        action: insert
      - key: environment
        value: production
        action: insert

exporters:
  otlp:
    endpoint: tempo-stack-distributor.observability.svc.cluster.local:4317
    tls:
      insecure: true
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 1000

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [resource, batch]
      exporters: [otlp]
```

#### Option 2: Direct Application Instrumentation

##### Go Application

```go
package main

import (
    "context"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
)

func initTracer(ctx context.Context) (*sdktrace.TracerProvider, error) {
    // Create OTLP exporter
    exporter, err := otlptracegrpc.New(ctx,
        otlptracegrpc.WithEndpoint("tempo-stack-distributor.observability.svc.cluster.local:4317"),
        otlptracegrpc.WithInsecure(),
    )
    if err != nil {
        return nil, err
    }

    // Create resource with service information
    res, err := resource.New(ctx,
        resource.WithAttributes(
            semconv.ServiceName("game-server"),
            semconv.ServiceVersion("1.0.0"),
            semconv.ServiceNamespace("gaming"),
            semconv.DeploymentEnvironment("production"),
        ),
    )
    if err != nil {
        return nil, err
    }

    // Create tracer provider
    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(res),
        sdktrace.WithSampler(sdktrace.ParentBased(
            sdktrace.TraceIDRatioBased(0.1), // Sample 10% of traces
        )),
    )

    otel.SetTracerProvider(tp)
    return tp, nil
}

// Usage in HTTP handler
func handleRequest(w http.ResponseWriter, r *http.Request) {
    tracer := otel.Tracer("game-server")
    ctx, span := tracer.Start(r.Context(), "handle_game_action")
    defer span.End()

    // Add attributes
    span.SetAttributes(
        attribute.String("user.id", "user123"),
        attribute.String("game.id", "game456"),
    )

    // Do work...
    result, err := processGameAction(ctx)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
    }
}
```

##### Python Application (FastAPI)

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# Initialize tracer
resource = Resource(attributes={
    "service.name": "player-service",
    "service.version": "1.0.0",
    "service.namespace": "gaming",
    "deployment.environment": "production",
})

provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(
    endpoint="tempo-stack-distributor.observability.svc.cluster.local:4317",
    insecure=True,
)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# Instrument FastAPI app
app = FastAPI()
FastAPIInstrumentor.instrument_app(app)

# Manual tracing
tracer = trace.get_tracer(__name__)

@app.get("/player/{player_id}")
async def get_player(player_id: str):
    with tracer.start_as_current_span("get_player_data") as span:
        span.set_attribute("player.id", player_id)
        player = await fetch_player(player_id)
        return player
```

##### Node.js Application

```javascript
const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

// Initialize tracer
const provider = new NodeTracerProvider({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'matchmaking-service',
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
    [SemanticResourceAttributes.SERVICE_NAMESPACE]: 'gaming',
    [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: 'production',
  }),
});

const exporter = new OTLPTraceExporter({
  url: 'http://tempo-stack-distributor.observability.svc.cluster.local:4317',
});

provider.addSpanProcessor(new BatchSpanProcessor(exporter));
provider.register();

// Use in Express app
const express = require('express');
const { trace } = require('@opentelemetry/api');

const app = express();
const tracer = trace.getTracer('matchmaking-service');

app.post('/match', async (req, res) => {
  const span = tracer.startSpan('create_match');
  span.setAttribute('match.mode', req.body.mode);

  try {
    const match = await createMatch(req.body);
    span.setStatus({ code: 0 }); // OK
    res.json(match);
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: 2, message: error.message }); // ERROR
    res.status(500).json({ error: error.message });
  } finally {
    span.end();
  }
});
```

### Kubernetes Service Annotation (Auto-instrumentation)

For automatic sidecar injection:

```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    # Inject OpenTelemetry collector sidecar
    sidecar.opentelemetry.io/inject: "true"
spec:
  containers:
    - name: app
      env:
        # Configure OTLP endpoint (localhost with sidecar)
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://localhost:4317"
        - name: OTEL_SERVICE_NAME
          value: "my-service"
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "service.namespace=gaming,deployment.environment=production"
```

## Querying Traces

### Grafana Integration

1. **Add Tempo Data Source**:
   - Navigate to Configuration > Data Sources
   - Add Tempo data source
   - URL: `http://tempo-stack-query-frontend.observability.svc.cluster.local:3100`
   - Save & Test

2. **Explore Traces**:
   - Go to Explore
   - Select Tempo data source
   - Search by:
     - Trace ID
     - Service name
     - Duration
     - Tags

### TraceQL Query Examples

TraceQL is Tempo's query language for traces:

#### Basic Queries

```traceql
# Find all traces for a specific service
{ service.name = "game-server" }

# Find slow requests (>1s)
{ duration > 1s }

# Find errors
{ status = error }

# Combine conditions
{ service.name = "game-server" && duration > 500ms }

# Find traces with specific attribute
{ span.user_id = "user123" }
```

#### Advanced Queries

```traceql
# Find traces where game server calls player service
{ service.name = "game-server" }
  && { service.name = "player-service" }

# Find database queries taking >100ms
{ span.kind = "client" && span.db.system = "postgresql" && duration > 100ms }

# Find traces with high span count (complex operations)
{ rootSpanCount > 50 }

# Find traces in a specific time range with errors
{ status = error && timestamp >= "2025-12-09T00:00:00Z" }

# Find traces for specific game session
{ span.game_session_id = "session-abc-123" }
```

#### Service Performance Analysis

```traceql
# Find 95th percentile latency for a service
{ service.name = "matchmaking-service" } | quantile(duration, 0.95)

# Count errors by service
{ status = error } | count by service.name

# Average span duration by operation
{ service.name = "game-server" } | avg(duration) by span.name
```

### API Queries

```bash
# Search by trace ID
curl "http://tempo-query-frontend.observability.svc.cluster.local:3100/api/traces/TRACE_ID"

# Search by tags
curl -G "http://tempo-query-frontend.observability.svc.cluster.local:3100/api/search" \
  --data-urlencode 'tags=service.name=game-server'

# TraceQL query
curl -G "http://tempo-query-frontend.observability.svc.cluster.local:3100/api/search" \
  --data-urlencode 'q={ service.name = "game-server" && duration > 1s }'
```

## Monitoring & Alerting

### Key Metrics to Monitor

The ServiceMonitors automatically collect these metrics:

#### Distributor Metrics
- `tempo_distributor_received_spans_total`: Spans received
- `tempo_distributor_spans_received_total`: Rate of ingestion
- `tempo_distributor_bytes_received_total`: Data volume
- `tempo_request_duration_seconds`: Request latency

#### Ingester Metrics
- `tempo_ingester_blocks_flushed_total`: Blocks written to S3
- `tempo_ingester_bytes_received_total`: Ingestion rate
- `tempo_ingester_live_traces`: Active traces in memory
- `tempo_ingester_flush_queue_length`: Flush backlog

#### Query Metrics
- `tempo_query_frontend_queries_total`: Query rate
- `tempo_query_frontend_queries_duration_seconds`: Query latency
- `tempo_querier_spans_per_query`: Query efficiency
- `tempo_query_frontend_result_cache_hit_ratio`: Cache efficiency

#### Storage Metrics
- `tempo_tempodb_blocklist_length`: Blocks in storage
- `tempo_tempodb_compaction_blocks_total`: Compaction activity
- `tempo_tempodb_backend_request_duration_seconds`: S3 latency

### Example Prometheus Alerts

```yaml
groups:
  - name: tempo-alerts
    interval: 30s
    rules:
      # High ingestion latency
      - alert: TempoHighIngestionLatency
        expr: |
          histogram_quantile(0.99,
            rate(tempo_request_duration_seconds_bucket{route="/tempopb.Pusher/Push"}[5m])
          ) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Tempo ingestion latency is high"
          description: "P99 ingestion latency is {{ $value }}s"

      # High query latency
      - alert: TempoHighQueryLatency
        expr: |
          histogram_quantile(0.95,
            rate(tempo_request_duration_seconds_bucket{route="/api/traces/{traceID}"}[5m])
          ) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Tempo query latency is high"
          description: "P95 query latency is {{ $value }}s"

      # Ingester flush failures
      - alert: TempoIngesterFlushFailures
        expr: |
          rate(tempo_ingester_flush_failed_total[5m]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Tempo ingester flush failures detected"
          description: "Ingester {{ $labels.pod }} is failing to flush blocks"

      # Compactor behind
        - alert: TempoCompactorBehind
        expr: |
          tempo_tempodb_compaction_outstanding_blocks > 100
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Tempo compactor is behind"
          description: "{{ $value }} blocks waiting for compaction"

      # Low cache hit rate
      - alert: TempoLowCacheHitRate
        expr: |
          rate(tempo_query_frontend_result_cache_hits_total[5m]) /
          rate(tempo_query_frontend_result_cache_requests_total[5m]) < 0.5
        for: 15m
        labels:
          severity: info
        annotations:
          summary: "Tempo cache hit rate is low"
          description: "Cache hit rate is {{ $value | humanizePercentage }}"
```

## Troubleshooting

### Traces Not Appearing

1. **Check distributor logs**:
```bash
kubectl logs -n observability -l app.kubernetes.io/component=distributor --tail=100
```

2. **Verify endpoint connectivity**:
```bash
# From application pod
kubectl exec -it <app-pod> -- curl -v http://tempo-stack-distributor.observability.svc.cluster.local:4318/v1/traces
```

3. **Check ingester status**:
```bash
kubectl logs -n observability -l app.kubernetes.io/component=ingester --tail=100
```

4. **Verify S3 credentials**:
```bash
kubectl get secret tempo-s3-credentials -n observability -o yaml
```

### High Query Latency

1. **Check compactor status**:
```bash
kubectl logs -n observability -l app.kubernetes.io/component=compactor
```

2. **Review block sizes**:
```bash
aws s3 ls s3://tempo-traces-prod/traces/ --recursive --human-readable
```

3. **Scale queriers**:
```bash
kubectl scale statefulset tempo-stack-querier -n observability --replicas=4
```

### Storage Issues

1. **Check S3 bucket permissions**:
```bash
# Verify IAM policy allows s3:PutObject, s3:GetObject, s3:ListBucket
aws s3api get-bucket-policy --bucket tempo-traces-prod
```

2. **Monitor S3 request metrics**:
```bash
# Check CloudWatch metrics for s3:GetObject, s3:PutObject latencies
```

3. **Review ingester disk usage**:
```bash
kubectl exec -n observability tempo-stack-ingester-0 -- df -h /var/tempo
```

### Component Crashes

1. **Check resource limits**:
```bash
kubectl top pods -n observability -l app=tempo
```

2. **Review OOM kills**:
```bash
kubectl get events -n observability --field-selector reason=OOMKilled
```

3. **Increase resources**:
```bash
# Edit values.yaml and increase resources for affected component
helm upgrade tempo-stack . -n observability --values values.yaml
```

## Performance Tuning

### Ingestion Optimization

- **Increase distributor replicas** for high-volume workloads
- **Adjust batch processor settings** in OTEL collector
- **Tune ingester block settings** for write performance

### Query Optimization

- **Increase querier replicas** for read-heavy workloads
- **Enable caching** with memcached
- **Use TraceQL efficiently** (specific service names, time ranges)

### Storage Optimization

- **Adjust compaction settings** for block size optimization
- **Tune retention period** based on compliance needs
- **Use S3 Intelligent-Tiering** for cost savings

## Cost Optimization

### Storage Costs

- **S3 storage**: ~$0.023/GB/month (Standard)
- **S3 requests**: $0.005 per 1,000 PUT, $0.0004 per 1,000 GET
- **Data transfer**: $0.09/GB out to internet

### Estimated Costs (1TB traces/month)

- **Storage**: $23/month (14-day retention)
- **Requests**: ~$50/month (assuming high read/write)
- **Compute**: ~$300/month (EKS nodes)
- **Total**: ~$373/month

### Cost Reduction Strategies

1. **Sampling**: Reduce trace volume with head-based sampling
2. **Retention**: Decrease retention from 14 to 7 days
3. **Compression**: Already enabled (zstd)
4. **S3 Lifecycle**: Transition to Glacier for long-term retention

## Security Considerations

1. **Network Policies**: Restrict access to Tempo components
2. **RBAC**: Limit who can query traces (may contain PII)
3. **Encryption**:
   - In transit: TLS for all communication
   - At rest: S3 bucket encryption
4. **Secret Rotation**: Regularly rotate S3 credentials
5. **PII Scrubbing**: Use OTEL processor to remove sensitive data

## Integration with Other Tools

### Grafana Dashboards

Import these dashboard IDs:
- **Tempo Operational**: 15228
- **Tempo Service Performance**: 15229
- **RED Metrics from Traces**: (auto-generated by metrics-generator)

### Logs Correlation

Link traces with logs in Grafana:
```json
{
  "datasource": "Loki",
  "expr": "{job=\"game-server\"} | logfmt | trace_id=\"${__trace.traceId}\""
}
```

### Metrics Correlation

The metrics generator automatically creates:
- `traces_spanmetrics_calls_total`: Request rate
- `traces_spanmetrics_duration_bucket`: Latency histogram
- `traces_spanmetrics_size_total`: Request/response sizes
- `traces_service_graph_request_total`: Service dependencies

## Maintenance

### Regular Tasks

- **Weekly**: Review storage costs and usage
- **Monthly**: Review and update sampling rates
- **Quarterly**: Review retention policies
- **As needed**: Scale components based on load

### Upgrading

```bash
# Update Helm repository
helm repo update

# Check for new versions
helm search repo grafana/tempo-distributed

# Upgrade (with rollback capability)
helm upgrade tempo-stack . \
  --namespace observability \
  --values values.yaml \
  --values values-override.yaml

# Rollback if needed
helm rollback tempo-stack -n observability
```

## Support

- **Tempo Documentation**: https://grafana.com/docs/tempo/latest/
- **TraceQL Guide**: https://grafana.com/docs/tempo/latest/traceql/
- **OpenTelemetry Docs**: https://opentelemetry.io/docs/
- **GitHub Issues**: https://github.com/grafana/tempo/issues

---

**Next Steps**: Integrate Tempo with your Grafana stack and start instrumenting your microservices!
