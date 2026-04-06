# NVIDIA GPU Operator

Helm chart wrapping the upstream NVIDIA GPU Operator for the gpu-inference cluster.

## Overview

The GPU Operator automates the management of all NVIDIA software components needed to provision
and manage GPUs in Kubernetes:

- GPU drivers (disabled -- using EKS-optimized AMI with pre-installed drivers)
- Container toolkit (nvidia-container-toolkit)
- Device plugin (nvidia-device-plugin)
- DRA driver (Dynamic Resource Allocation for fine-grained GPU scheduling)
- DCGM (Data Center GPU Manager)
- MIG Manager (Multi-Instance GPU partitioning)
- Node Feature Discovery
- GPU Feature Discovery

## Target Hardware

- Instance type: p5.48xlarge
- GPUs: 8x NVIDIA H100 SXM5 (80GB HBM3 each)
- Interconnect: NVSwitch (3.2 TB/s aggregate)

## Key Configuration

| Feature | Setting | Notes |
|---------|---------|-------|
| DRA | Enabled | Kubernetes 1.35 DRA for ResourceClaim-based GPU allocation |
| MIG | Disabled by default | Can be enabled per-node via mig-parted-config |
| Drivers | Pre-installed | EKS AMI includes NVIDIA drivers |
| DCGM Exporter | External | Managed by separate `dcgm-exporter` chart |

## Dependencies

- Kubernetes >= 1.29 (DRA requires >= 1.31)
- EKS-optimized AMI with NVIDIA drivers
- `dcgm-exporter` chart for metrics export
- `victoriametrics` chart for metrics storage

## Values Override

The gpu-inference ApplicationSet loads `values.yaml` from this directory. No additional
`values-gpu-inference.yaml` is needed since this chart is gpu-inference-only.
