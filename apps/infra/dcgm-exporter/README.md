# NVIDIA DCGM Exporter

Helm chart wrapping the upstream NVIDIA DCGM Exporter for the gpu-inference cluster.

## Overview

The DCGM Exporter runs as a DaemonSet on all GPU nodes and exports GPU health and performance
metrics in Prometheus format. These metrics are scraped by VictoriaMetrics VMAgent.

## Metric Families (7 total)

| Family | Key Metrics | Use Case |
|--------|-------------|----------|
| GPU Utilization | `DCGM_FI_DEV_GPU_UTIL` | Capacity planning, auto-scaling |
| Memory | `DCGM_FI_DEV_FB_USED`, `FB_FREE` | OOM prevention, model sizing |
| Temperature | `DCGM_FI_DEV_GPU_TEMP`, `MEMORY_TEMP` | Thermal throttling detection |
| Power | `DCGM_FI_DEV_POWER_USAGE` | Cost attribution, power budgets |
| NVLink | `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` | NCCL performance monitoring |
| PCIe | `DCGM_FI_DEV_PCIE_TX/RX_THROUGHPUT` | Data transfer bottlenecks |
| ECC Errors | `DCGM_FI_DEV_ECC_SBE/DBE_VOL_TOTAL` | GPU health, pre-failure detection |

## GPU Health Auto-Taint

The DCGM Exporter provides the metrics; a separate controller watches for:

- **XID errors** (any non-zero): taint node `nvidia.com/gpu-health=unhealthy:NoSchedule`
- **Double-bit ECC errors**: taint node immediately (hardware failure)
- **Temperature > 90C**: warn only (initial rollout)

This prevents scheduling new inference pods onto degraded GPUs.

## DoD Criteria

From `docs/gpu-inference-dod.md`:
- All 7 DCGM metric families present for all GPU nodes
- `DCGM_FI_DEV_GPU_UTIL` time series count = GPU nodes x 8
- `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` present

## Dependencies

- NVIDIA GPU Operator (provides DCGM daemon)
- VictoriaMetrics (scrapes ServiceMonitor)
- Kubernetes node label `nvidia.com/gpu.present: "true"` on GPU nodes
