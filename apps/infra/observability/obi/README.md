# OBI / Grafana Beyla -- eBPF Auto-Instrumentation

Implements **ADR-0019** (OBI/Beyla tracing) and **ADR-0026** (observability target architecture).

## What this chart does

Deploys [Grafana Beyla](https://grafana.com/docs/beyla/latest/) as a **DaemonSet** that:

1. Instruments HTTP/gRPC traffic **at the kernel** via eBPF -- zero application code changes.
2. Exports **OTLP traces** to the `otel-collector` gateway (`observability` namespace, port 4317).
3. The collector tail-samples and forwards to **Tempo** for storage and query.

## RED-metric source decision (ADR-0026: one source, not both)

**Chosen source: Tempo's `metrics-generator`.**

Beyla's Prometheus metrics export is **disabled** (`OTEL_METRICS_EXPORTER=none`). Tempo's
`metrics-generator` derives RED metrics (rate, error, duration histograms + service graphs)
from every span it ingests -- including spans from SDK-instrumented services, giving a
single consistent cardinality budget.

Enabling both would produce duplicate RED metrics in Prometheus, causing double cost and
reconciliation pain. Do not re-enable `OTEL_METRICS_EXPORTER` without first disabling
Tempo's `metricsGenerator`.

## Sync-wave ordering

| Wave | Application       | Why                                         |
|------|-------------------|---------------------------------------------|
|   10 | `tempo-stack`     | Storage backend must exist before exporters |
|   15 | `otel-collector`  | Pipeline ready before producers start       |
|   20 | `obi` (this chart)| eBPF producer starts last                   |

Apply in order:

```bash
kubectl apply -f apps/infra/observability/tempo/argocd-application.yaml
kubectl apply -f apps/infra/observability/otel-collector/argocd-application.yaml
kubectl apply -f apps/infra/observability/obi/argocd-application.yaml
```

## Privileges

eBPF auto-instrumentation requires:

| Privilege           | Reason                                           |
|---------------------|--------------------------------------------------|
| `hostNetwork: true` | Observe all node sockets                         |
| `hostPID: true`     | Process discovery for uprobe attachment          |
| `CAP_BPF`           | Load eBPF programs                               |
| `CAP_SYS_PTRACE`    | Uprobe attachment / process memory inspection    |
| `CAP_NET_RAW`       | Raw socket access for network probes             |
| `CAP_PERFMON`       | `perf_event_open` (kernel >= 5.8)                |
| `seccompProfile: Unconfined` | RuntimeDefault blocks BPF syscalls    |

**Node kernel requirement**: Linux >= 5.8 (EKS AL2023 = 6.12, Bottlerocket aws-k8s-1.33+ = 6.12).

## Image

```
grafana/beyla:1.9.3   # released 2025-05-13; multi-arch: linux/amd64 + linux/arm64
```

Pin updates via `values.yaml` `.image.tag`. Verify checksums at
https://github.com/grafana/beyla/releases

## References

- Grafana Beyla docs: https://grafana.com/docs/beyla/latest/
- ADR-0019: docs/adrs/0019-harvest-cilium-ebpf-capabilities.md
- ADR-0026: docs/adrs/0026-observability-target-architecture.md
