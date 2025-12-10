# Grafana Dashboards

Unified Grafana dashboards for comprehensive platform observability across metrics, logs, traces, and profiles.

## Overview

This Helm chart deploys a curated set of production-ready Grafana dashboards as ConfigMaps. The dashboards are automatically discovered and loaded by Grafana's sidecar container.

## Dashboard Catalog

### Infrastructure Dashboards

#### 1. Cluster Overview
**Purpose**: Single pane of glass for cluster health

**Panels**:
- Cluster status (nodes ready, pods running)
- Resource utilization (CPU, memory, network, disk)
- Karpenter node provisioning stats
- Top resource consumers by namespace
- Recent critical alerts
- Quick navigation links

**Use Case**: First dashboard to check during incidents

#### 2. Node Health
**Purpose**: Deep dive into node-level metrics

**Panels**:
- Node status and conditions
- CPU/memory/disk per node with history
- Network I/O and packet rates
- Karpenter provisioner assignments
- Node cost breakdown (spot vs on-demand)
- Architecture distribution (x86 vs ARM64)

**Use Case**: Investigating node issues, capacity planning

#### 3. Karpenter Autoscaling
**Purpose**: Monitor Karpenter autoscaler performance

**Panels**:
- Provisioning latency (P50, P95, P99)
- Nodes created/terminated over time
- Consolidation savings ($)
- Instance type distribution
- Spot vs on-demand ratio
- Provisioning failures and reasons

**Use Case**: Tuning autoscaling, cost optimization

### Application Dashboards

#### 4. Service Golden Signals (RED)
**Purpose**: Monitor service health using RED metrics

**Panels**:
- **Rate**: Requests per second
- **Errors**: Error rate (4xx, 5xx)
- **Duration**: Latency percentiles (P50, P95, P99)
- Saturation (CPU, memory usage)
- Top endpoints by traffic
- Error breakdown by status code

**Variables**:
- `service` - Select service to monitor
- `namespace` - Filter by namespace

**Data Links**:
- Click on error spike → Jump to traces with errors
- Click on latency spike → Jump to slow traces
- Click on service → Deep dive dashboard

**Use Case**: Real-time service monitoring, SLI tracking

#### 5. Service SLO Monitoring
**Purpose**: Track SLOs and error budgets

**Panels**:
- Availability SLO (target vs actual)
- Latency SLO (P99 < target threshold)
- Error budget remaining (%)
- Burn rate (how fast error budget is consumed)
- SLO compliance over 30 days
- Alerts for budget depletion

**Variables**:
- `service` - Select service
- `slo_target` - Availability target (e.g., 99.9%)

**Use Case**: SRE reporting, release gating

### Observability Stack Dashboards

#### 6. Loki Logs Overview
**Purpose**: Monitor logging infrastructure health

**Panels**:
- Ingestion rate (bytes/sec, lines/sec)
- Query latency (P50, P95, P99)
- Error rates (ingestion, query)
- Storage usage and retention
- Top log producers by namespace
- Fluent Bit agent health

**Use Case**: Troubleshooting log collection issues

#### 7. Tempo Traces Overview
**Purpose**: Monitor tracing infrastructure health

**Panels**:
- Spans ingested per second
- Query latency
- Storage usage
- Service map with error rates
- Trace error rate
- Distributor/Ingester/Querier health

**Use Case**: Troubleshooting trace collection

#### 8. Pyroscope Profiling Overview
**Purpose**: Monitor continuous profiling health

**Panels**:
- Profiles ingested per second
- Storage usage
- Top profiled services
- Query latency
- Component health (distributor, ingester, querier)

**Use Case**: Troubleshooting profiling collection

### Unified Dashboards

#### 9. Service Deep Dive
**Purpose**: Full observability for a single service

**Layout**:
- **Top row**: Golden signals (metrics)
- **Second row**: Recent logs (errors highlighted)
- **Third row**: Trace list (errors and slow traces)
- **Fourth row**: Flame graph embed (CPU profile)

**Correlation**:
- All panels filtered by same service
- Time range synchronized across all panels
- Click on error → See related logs and traces
- Click on trace ID → Jump to Tempo
- Click on "View Profile" → Jump to Pyroscope

**Variables**:
- `service` - Service name
- `namespace` - Service namespace
- `time_range` - Time range for all panels

**Use Case**: Incident response, performance troubleshooting

## Installation

### Prerequisites

1. **Grafana with sidecar enabled**:
```yaml
# In prometheus-stack values.yaml
grafana:
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
```

2. **Data sources configured**: prometheus, thanos, loki, tempo, pyroscope

### Deploy Dashboards

```bash
# Install dashboards
helm upgrade --install grafana-dashboards . \
  --namespace observability \
  --create-namespace

# Verify ConfigMaps created
kubectl get configmaps -n observability -l grafana_dashboard=1

# Check Grafana sidecar logs
kubectl logs -n observability \
  $(kubectl get pods -n observability -l app.kubernetes.io/name=grafana -o name) \
  -c grafana-sc-dashboard
```

### Access Dashboards

```bash
# Port-forward to Grafana
kubectl port-forward -n observability svc/prometheus-stack-grafana 3000:80

# Open browser
open http://localhost:3000

# Default credentials (change in production!)
Username: admin
Password: (from secret)
```

Navigate to **Dashboards** → **Manage** → **observability** folder

## Customization

### Adding Custom Dashboards

1. **Export from Grafana UI**:
   - Create dashboard in Grafana
   - Share → Export → Save to file
   - Copy JSON to `templates/` directory

2. **Create ConfigMap**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-custom-dashboard
  labels:
    grafana_dashboard: "1"
data:
  my-dashboard.json: |
    {
      "dashboard": { ... }
    }
```

3. **Apply**:
```bash
kubectl apply -f my-dashboard-configmap.yaml
```

Grafana sidecar will automatically reload the dashboard.

### Modifying Existing Dashboards

1. Edit dashboard in Grafana UI
2. Export JSON
3. Update ConfigMap in `templates/`
4. Apply with Helm upgrade

### Dashboard Variables

Common variables used across dashboards:

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `cluster` | Constant | - | Cluster name |
| `namespace` | Query | Prometheus | Kubernetes namespace |
| `service` | Query | Prometheus | Service name from ServiceMonitor |
| `pod` | Query | Prometheus | Pod name |
| `node` | Query | Prometheus | Node name |
| `datasource` | Datasource | - | Metrics source (Prometheus/Thanos) |

### Dashboard Annotations

Annotations add context to graphs:

**Deployment annotations** (from Prometheus):
```promql
changes(kube_deployment_status_observed_generation{namespace="$namespace"}[5m]) > 0
```

**Alert annotations** (from Alertmanager):
```promql
ALERTS{alertstate="firing",severity="critical"}
```

## Data Links and Correlation

### Metrics → Traces

Exemplars link metrics to trace IDs:
```promql
http_request_duration_seconds_bucket{service="$service"}
```
Click on exemplar dot → Jump to trace in Tempo

### Logs → Traces

Trace IDs extracted from logs:
```logql
{service="$service"} |= "trace_id"
```
Click on trace_id → Jump to trace in Tempo

### Traces → Logs

From trace span:
- Click "Logs for this span"
- Shows logs with matching trace_id and time range

### Traces → Metrics

From trace:
- Click "Related Metrics"
- Shows service metrics during trace time

### Metrics → Profiles

From high CPU metric:
- Click "View Profile"
- Jump to flame graph in Pyroscope

## Dashboard Organization

### Folder Structure in Grafana

```
observability/
├── Infrastructure/
│   ├── Cluster Overview
│   ├── Node Health
│   └── Karpenter
├── Applications/
│   ├── Service Golden Signals
│   ├── Service SLO
│   └── Service Deep Dive
└── Observability Stack/
    ├── Loki Overview
    ├── Tempo Overview
    └── Pyroscope Overview
```

### Naming Convention

- **Overview dashboards**: High-level metrics, good for NOC displays
- **Detail dashboards**: Deep dive, good for troubleshooting
- **Service dashboards**: Per-service metrics, good for developers

## Best Practices

### For SRE Team

1. **Start with Overview**: Use Cluster Overview as your first check
2. **Follow the RED method**: Rate, Errors, Duration for services
3. **Use Deep Dive for incidents**: Correlate metrics, logs, traces
4. **Set up alerts on dashboards**: Don't rely on manual checking

### For Developers

1. **Monitor your services**: Use Service Golden Signals dashboard
2. **Track SLOs**: Use Service SLO dashboard
3. **Investigate with Deep Dive**: Use Service Deep Dive for debugging
4. **Enable profiling**: Add profiling annotations for performance issues

### Dashboard Design

1. **Keep it simple**: 5-7 panels max for overview dashboards
2. **Use consistent colors**: Red for errors, green for success, blue for info
3. **Add descriptions**: Every panel should have a description
4. **Use thresholds**: Visual indicators for SLOs
5. **Test on different time ranges**: Ensure dashboards work for 1h and 30d views

## Troubleshooting

### Dashboards not appearing

1. Check sidecar is running:
```bash
kubectl logs -n observability deployment/prometheus-stack-grafana -c grafana-sc-dashboard
```

2. Verify labels:
```bash
kubectl get configmaps -n observability -l grafana_dashboard=1
```

3. Check Grafana logs:
```bash
kubectl logs -n observability deployment/prometheus-stack-grafana -c grafana
```

### No data in panels

1. **Check data source**: Ensure datasources are configured and working
2. **Check time range**: Some metrics may not exist in selected range
3. **Check queries**: Test PromQL/LogQL in Explore tab
4. **Check RBAC**: Grafana service account needs read permissions

### Slow dashboard loading

1. **Reduce time range**: Use shorter ranges for high-cardinality data
2. **Use Thanos for long ranges**: Switch to Thanos datasource for >2h queries
3. **Optimize queries**: Use recording rules for expensive queries
4. **Increase timeouts**: Adjust datasource query timeout

## Maintenance

### Regular Tasks

**Weekly**:
- Review dashboard usage analytics
- Update panels based on feedback
- Check for unused variables

**Monthly**:
- Audit dashboard performance
- Update to latest Grafana features
- Archive unused dashboards

**Quarterly**:
- Major dashboard redesigns
- Update SLO targets
- Align with new services

### Backup and Restore

**Backup**:
```bash
# Export all dashboards
kubectl get configmaps -n observability -l grafana_dashboard=1 -o yaml > dashboards-backup.yaml
```

**Restore**:
```bash
# Import dashboards
kubectl apply -f dashboards-backup.yaml
```

## Resources

- [Grafana Documentation](https://grafana.com/docs/)
- [PromQL Guide](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [LogQL Guide](https://grafana.com/docs/loki/latest/logql/)
- [TraceQL Guide](https://grafana.com/docs/tempo/latest/traceql/)
- [Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)

## Support

For issues or questions:
- Slack: #observability
- Email: platform-team@example.com
- Docs: /docs/observability-architecture.md
