# Observability Stack Overview

Complete production observability for gaming platform on Amazon EKS

## Quick Links

- [Full Architecture](./observability-architecture.md)
- [SRE Runbook](./sre-runbook.md)
- [Instrumentation Guide](./instrumentation-guide.md)
- [Alerting Guide](./alerting-guide.md)

## Stack Components

### Metrics: Prometheus + Thanos + Grafana
**Location**: `apps/infra/observability/prometheus-stack/`
- 10M time series at 5K nodes
- 2h local, 1 year S3 retention
- Cost: ~$1,250/month

### Logs: Loki + Fluent Bit  
**Location**: `apps/infra/observability/loki-stack/`
- 500GB/day at 5K nodes
- 30-day retention
- Cost: ~$441/month

### Traces: Tempo + OpenTelemetry
**Location**: `apps/infra/observability/tempo/` + `otel-collector/`
- 1M spans/sec at 5K nodes
- 14-day retention  
- Cost: ~$373/month

### Profiles: Pyroscope
**Location**: `apps/infra/observability/pyroscope/`
- <2% CPU overhead
- 7-day retention
- Cost: ~$200/month

## Total Cost

| Cluster Size | Compute | Storage | Total/Month |
|--------------|---------|---------|-------------|
| 100 nodes | $500 | $100 | **$600** |
| 1000 nodes | $2,400 | $600 | **$3,000** |
| 5000 nodes | $10,000 | $2,000 | **$12,000** |

## Quick Start

```bash
# Deploy all observability components
cd apps/infra/observability

# 1. Prometheus + Thanos
helm install prometheus-stack prometheus-stack/ -n observability

# 2. Loki + Fluent Bit
helm install loki-stack loki-stack/ -n observability

# 3. Tempo
helm install tempo tempo/ -n observability

# 4. OpenTelemetry Collector
helm install otel-collector otel-collector/ -n observability

# 5. Pyroscope
helm install pyroscope pyroscope/ -n observability

# 6. Grafana Dashboards
helm install grafana-dashboards grafana-dashboards/ -n observability

# Access Grafana
kubectl port-forward -n observability svc/prometheus-stack-grafana 3000:80
```

## Data Flow

```
Apps → Collectors → Processing → S3 Storage → Query → Grafana
```

**Collectors**: Prometheus, Fluent Bit, OTel Collector, Pyroscope Agent
**Processing**: Thanos, Loki, Tempo, Pyroscope  
**Storage**: S3 buckets (encrypted, lifecycle policies)
**Query**: Thanos Query, Loki Query, Tempo Query, Pyroscope Query
**Visualization**: Grafana (unified dashboards)

## Key Features

✅ **High Availability**: All components multi-replica with PDB
✅ **Auto-scaling**: HPA based on load
✅ **Cost Optimized**: Spot instances, S3 lifecycle, sampling
✅ **Secure**: IRSA, network policies, encryption
✅ **Correlated**: Trace IDs link metrics → logs → traces → profiles
✅ **Production Ready**: Battle-tested at scale

