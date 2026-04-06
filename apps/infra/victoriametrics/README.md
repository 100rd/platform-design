# VictoriaMetrics Operator

Helm chart wrapping the upstream VictoriaMetrics Operator for the gpu-inference cluster.

## Overview

VictoriaMetrics replaces kube-prometheus-stack on gpu-inference clusters. It provides:

- VMCluster: distributed time-series storage (vminsert, vmstorage, vmselect)
- VMAgent: Prometheus-compatible scrape agent
- VMAlert: alerting engine with PrometheusRule CRD support
- Alertmanager: notification routing

## Why VictoriaMetrics for GPU Clusters

| Metric | Prometheus + Thanos | VictoriaMetrics |
|--------|--------------------:|----------------:|
| Memory per 1M series | ~3 GB | ~300 MB |
| Compression ratio | ~1.2 bytes/sample | ~0.4 bytes/sample |
| Query language | PromQL | MetricsQL (PromQL superset) |
| Clustering | Thanos sidecar | Native vminsert/vmstorage/vmselect |
| High-cardinality support | Degrades | Handles well |

GPU clusters produce high-cardinality metrics (per-GPU, per-process, per-MIG-slice), making
VictoriaMetrics the better fit.

## Prometheus CRD Compatibility

The VictoriaMetrics Operator automatically converts Prometheus CRDs:

- `ServiceMonitor` -> `VMServiceScrape`
- `PodMonitor` -> `VMPodScrape`
- `PrometheusRule` -> `VMRule`

This means existing ServiceMonitor definitions from other charts (Cilium, GPU Operator, DCGM
Exporter) work without modification.

## Architecture

```
ServiceMonitors/PodMonitors
        |
        v
    VMAgent (2 replicas)
        |
        v
    VMInsert (2 replicas) ---> VMStorage (2 replicas, 100Gi each)
                                    |
                                    v
                               VMSelect (2 replicas) ---> Grafana
                                    |
                                    v
                               VMAlert (2 replicas) ---> Alertmanager
```

## Dependencies

- Kubernetes >= 1.25
- StorageClass `gp3` for VMStorage PVCs
- Grafana configured with VictoriaMetrics datasource
