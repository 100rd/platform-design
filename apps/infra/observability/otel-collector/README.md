# OpenTelemetry Collector

Production-ready OpenTelemetry Collector deployment for the gaming platform. Serves as the central telemetry pipeline for collecting, processing, and routing observability data (traces, metrics, logs) to backend systems.

## Architecture

### Two-Tier Collection Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                         Applications                             │
│  (Game Services, APIs, Microservices with OTel SDKs)            │
└────────────┬────────────────────────────────────┬───────────────┘
             │                                    │
             │ OTLP                              │ OTLP
             │ (4317/4318)                       │ (4317/4318)
             ▼                                    ▼
┌─────────────────────────┐         ┌─────────────────────────┐
│  OTel Agent (DaemonSet) │         │  OTel Agent (DaemonSet) │
│  - Per-node collection  │         │  - Per-node collection  │
│  - Host metrics         │         │  - Host metrics         │
│  - Log collection       │         │  - Log collection       │
│  - Low resource usage   │         │  - Low resource usage   │
└───────────┬─────────────┘         └───────────┬─────────────┘
            │                                    │
            │ Forward OTLP                       │ Forward OTLP
            │                                    │
            └──────────────┬─────────────────────┘
                          ▼
            ┌──────────────────────────┐
            │  OTel Gateway (3 pods)   │
            │  - Central processing    │
            │  - Tail sampling         │
            │  - Batch optimization    │
            │  - Routing to backends   │
            └──────────┬───────────────┘
                       │
         ┌─────────────┼─────────────┬─────────────┐
         ▼             ▼             ▼             ▼
    ┌────────┐   ┌─────────┐   ┌───────┐   ┌──────────┐
    │ Tempo  │   │Prometheus│   │ Loki  │   │Pyroscope │
    │(Traces)│   │(Metrics) │   │(Logs) │   │(Profiles)│
    └────────┘   └─────────┘   └───────┘   └──────────┘
```

### Why Two Tiers?

**Agent (DaemonSet)**:
- Runs on every node
- Collects telemetry from local pods
- Gathers host and Kubernetes metrics
- Low resource footprint (200m CPU, 256Mi RAM)
- Reduces network hops for pod telemetry
- Provides node-level visibility

**Gateway (Deployment)**:
- Central processing and routing
- Advanced processing (tail sampling, filtering)
- Batching and optimization
- High availability (3 replicas)
- Scales independently of nodes
- Single point for backend configuration

## Installation

### Prerequisites

1. Kubernetes cluster (EKS) running
2. Monitoring namespace created:
   ```bash
   kubectl create namespace monitoring
   kubectl label namespace monitoring name=monitoring
   ```

3. Backend services deployed (Prometheus, Tempo, Loki, Pyroscope)

### Deploy Gateway Collector

```bash
# Deploy the gateway (centralized collector)
helm dependency update
helm upgrade --install otel-collector . \
  --namespace monitoring \
  --values values.yaml \
  --wait
```

### Deploy Agent Collector

```bash
# Deploy the agent (per-node collector)
helm upgrade --install otel-agent . \
  --namespace monitoring \
  --values values.yaml \
  --values values-daemonset.yaml \
  --wait
```

### Deploy Both Together

```bash
# Deploy complete two-tier architecture
helm dependency update

# Install gateway
helm upgrade --install otel-collector . \
  --namespace monitoring \
  --values values.yaml

# Install agent
helm upgrade --install otel-agent . \
  --namespace monitoring \
  --values values.yaml \
  --values values-daemonset.yaml
```

## Configuration

### Sending Telemetry from Applications

#### Environment Variables

Set these in your application deployments:

```yaml
env:
  # OTLP endpoint (use agent for local collection)
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector-agent.monitoring.svc.cluster.local:4317"

  # Or use gateway directly
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector-gateway.monitoring.svc.cluster.local:4317"

  # Service name
  - name: OTEL_SERVICE_NAME
    value: "game-api"

  # Resource attributes
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment=production,service.version=1.2.3"

  # Trace sampling
  - name: OTEL_TRACES_SAMPLER
    value: "parentbased_traceidratio"
  - name: OTEL_TRACES_SAMPLER_ARG
    value: "0.1"  # Sample 10% at SDK level
```

#### SDK Configuration Examples

**Node.js (TypeScript)**:

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-grpc';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'game-api',
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.2.3',
    [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: 'production',
  }),
  traceExporter: new OTLPTraceExporter({
    url: 'http://otel-collector-agent.monitoring.svc.cluster.local:4317',
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url: 'http://otel-collector-agent.monitoring.svc.cluster.local:4317',
    }),
    exportIntervalMillis: 60000,
  }),
});

sdk.start();
```

**Python**:

```python
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource

resource = Resource.create({
    "service.name": "game-matchmaking",
    "service.version": "2.1.0",
    "deployment.environment": "production",
})

# Traces
trace_provider = TracerProvider(resource=resource)
trace_provider.add_span_processor(
    BatchSpanProcessor(
        OTLPSpanExporter(
            endpoint="otel-collector-agent.monitoring.svc.cluster.local:4317",
            insecure=True,
        )
    )
)
trace.set_tracer_provider(trace_provider)

# Metrics
metric_reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(
        endpoint="otel-collector-agent.monitoring.svc.cluster.local:4317",
        insecure=True,
    )
)
meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
metrics.set_meter_provider(meter_provider)
```

**Go**:

```go
package main

import (
    "context"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)

func initTracer(ctx context.Context) error {
    res, err := resource.New(ctx,
        resource.WithAttributes(
            semconv.ServiceName("game-leaderboard"),
            semconv.ServiceVersion("3.0.1"),
            semconv.DeploymentEnvironment("production"),
        ),
    )
    if err != nil {
        return err
    }

    conn, err := grpc.DialContext(ctx,
        "otel-collector-agent.monitoring.svc.cluster.local:4317",
        grpc.WithTransportCredentials(insecure.NewCredentials()),
    )
    if err != nil {
        return err
    }

    traceExporter, err := otlptracegrpc.New(ctx, otlptracegrpc.WithGRPCConn(conn))
    if err != nil {
        return err
    }

    bsp := sdktrace.NewBatchSpanProcessor(traceExporter)
    tracerProvider := sdktrace.NewTracerProvider(
        sdktrace.WithSampler(sdktrace.TraceIDRatioBased(0.1)),
        sdktrace.WithResource(res),
        sdktrace.WithSpanProcessor(bsp),
    )

    otel.SetTracerProvider(tracerProvider)
    return nil
}
```

**Java (Spring Boot)**:

```yaml
# application.yaml
management:
  otlp:
    tracing:
      endpoint: http://otel-collector-agent.monitoring.svc.cluster.local:4318
  tracing:
    sampling:
      probability: 0.1

spring:
  application:
    name: game-inventory
```

### Custom Sampling Rules

The tail sampling processor in the gateway uses intelligent sampling:

```yaml
# Already configured in values.yaml
tail_sampling:
  policies:
    # Keep all errors
    - name: error-sample
      type: status_code
      status_code:
        status_codes: [ERROR]

    # Keep slow requests (> 2s)
    - name: slow-traces
      type: latency
      latency:
        threshold_ms: 2000

    # Keep critical game events
    - name: game-critical-events
      type: string_attribute
      string_attribute:
        key: event.type
        values:
          - player.death
          - player.levelup
          - purchase.completed

    # Sample 10% of everything else
    - name: probabilistic-sample
      type: probabilistic
      probabilistic:
        sampling_percentage: 10
```

### Pipeline Customization

To add custom processors or exporters, edit `values.yaml`:

```yaml
gateway:
  config:
    processors:
      # Add your custom processor
      span_metrics:
        metrics_exporter: prometheus
        latency_histogram_buckets: [100ms, 500ms, 1s, 2s, 5s]
        dimensions:
          - name: http.method
          - name: http.status_code

    exporters:
      # Add custom exporter
      otlp/custom:
        endpoint: custom-backend.company.com:4317
        tls:
          insecure: false
          cert_file: /certs/tls.crt
          key_file: /certs/tls.key

    service:
      pipelines:
        traces:
          processors: [..., span_metrics]
          exporters: [..., otlp/custom]
```

## Monitoring the Collector

### Metrics

The collector exposes its own metrics on port 8888:

```bash
# Port-forward to access metrics
kubectl port-forward -n monitoring svc/otel-collector-gateway 8888:8888

# View metrics
curl http://localhost:8888/metrics
```

Key metrics to monitor:

- `otelcol_receiver_accepted_spans` - Spans received
- `otelcol_receiver_refused_spans` - Spans rejected
- `otelcol_processor_batch_batch_send_size` - Batch sizes
- `otelcol_exporter_sent_spans` - Spans exported
- `otelcol_exporter_send_failed_spans` - Export failures
- `otelcol_process_uptime` - Collector uptime
- `otelcol_process_memory_rss` - Memory usage

### Dashboards

ServiceMonitor resources are automatically created. Import Grafana dashboards:

- **OTel Collector Dashboard**: ID 15983
- **OTel Collector Data Flow**: ID 12553

### Troubleshooting

#### Enable Debug Logging

```bash
# Edit values.yaml
gateway:
  config:
    service:
      telemetry:
        logs:
          level: debug  # Change from info to debug
```

#### Check Collector Logs

```bash
# Gateway logs
kubectl logs -n monitoring -l app.kubernetes.io/component=gateway --tail=100 -f

# Agent logs
kubectl logs -n monitoring -l app.kubernetes.io/component=agent --tail=100 -f
```

#### Test Telemetry Flow

```bash
# Send test span
kubectl run -n monitoring test-telemetry --rm -it --restart=Never \
  --image=curlimages/curl -- \
  curl -X POST http://otel-collector-gateway:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": {"stringValue": "test-service"}
        }]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "0123456789abcdef0123456789abcdef",
          "spanId": "0123456789abcdef",
          "name": "test-span",
          "kind": 1,
          "startTimeUnixNano": "1000000000000000000",
          "endTimeUnixNano": "1000000001000000000"
        }]
      }]
    }]
  }'
```

#### Access zpages (Live Debugging)

```bash
# Port-forward zpages
kubectl port-forward -n monitoring svc/otel-collector-gateway 55679:55679

# Open in browser
open http://localhost:55679/debug/tracez
open http://localhost:55679/debug/pipelinez
```

#### Common Issues

**High Memory Usage**:
- Check batch sizes: Reduce `send_batch_size` in batch processor
- Enable memory limiter: Already configured to limit at 80%
- Check for data spikes: Review incoming telemetry rates

**Data Not Reaching Backends**:
- Check exporter logs for errors
- Verify backend endpoints are reachable
- Check network policies allow egress
- Verify backend authentication/credentials

**High Cardinality**:
- Use filter processor to drop high-cardinality attributes
- Configure metric relabeling in ServiceMonitor
- Use attributes processor to aggregate or drop labels

## Performance Tuning

### For High-Throughput Environments

```yaml
gateway:
  replicaCount: 5  # Increase replicas

  resources:
    requests:
      cpu: 4000m      # More CPU
      memory: 8Gi     # More memory

  autoscaling:
    maxReplicas: 20   # Allow scaling

  config:
    processors:
      batch:
        send_batch_size: 2000      # Larger batches
        timeout: 5s                # Faster sends

    exporters:
      otlp/tempo:
        sending_queue:
          queue_size: 10000        # Larger queue
          num_consumers: 20        # More workers
```

### For Cost Optimization

```yaml
gateway:
  config:
    processors:
      # More aggressive sampling
      tail_sampling:
        policies:
          - name: probabilistic-sample
            type: probabilistic
            probabilistic:
              sampling_percentage: 5  # Sample 5% instead of 10%

      # Filter more aggressively
      filter:
        traces:
          span:
            - 'attributes["http.target"] matches "^/health.*"'
            - 'attributes["http.target"] matches "^/metrics.*"'
            - 'resource.attributes["service.name"] == "test-service"'
```

## Security

### TLS Configuration

To enable TLS for OTLP endpoints:

```yaml
gateway:
  extraVolumes:
    - name: tls-certs
      secret:
        secretName: otel-tls-certs

  extraVolumeMounts:
    - name: tls-certs
      mountPath: /certs
      readOnly: true

  config:
    receivers:
      otlp:
        protocols:
          grpc:
            tls:
              cert_file: /certs/tls.crt
              key_file: /certs/tls.key
```

### Authentication

For backend authentication:

```yaml
gateway:
  config:
    exporters:
      prometheusremotewrite:
        headers:
          Authorization: "Bearer ${PROMETHEUS_TOKEN}"

      loki:
        headers:
          X-Scope-OrgID: "tenant-id"
```

## Production Checklist

- [ ] Both gateway and agent deployed
- [ ] ServiceMonitors created and scraping
- [ ] Network policies applied
- [ ] Resource limits configured
- [ ] Autoscaling enabled for gateway
- [ ] Backend endpoints verified
- [ ] Sample application sending telemetry
- [ ] Grafana dashboards imported
- [ ] Alerts configured for collector health
- [ ] Documentation shared with dev teams

## Support

For issues or questions:
- Platform Team: platform@gaming.com
- Slack: #observability
- Documentation: https://wiki.company.com/observability
