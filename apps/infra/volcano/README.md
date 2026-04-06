# Volcano Scheduler

Helm chart wrapping the upstream Volcano batch scheduler for the gpu-inference cluster.

## Overview

Volcano provides GPU-aware batch scheduling with:

- **Gang scheduling**: All-or-nothing pod placement for distributed inference/training jobs.
  If a job requests 8 pods (one per GPU node), either all 8 are scheduled or none.
- **DRA integration**: Works with Kubernetes Dynamic Resource Allocation for ResourceClaim-based
  GPU scheduling (requires Kubernetes >= 1.31).
- **Fair-share queues**: Prevents GPU starvation across teams. Queues have weights and capacity
  limits.
- **Binpack scheduling**: Packs pods onto fewer nodes to maximize GPU utilization and minimize
  cross-node NCCL communication.
- **Preemption**: Lower-priority batch jobs yield GPUs to higher-priority inference workloads.

## Key Scheduling Plugins

| Plugin | Purpose |
|--------|---------|
| gang | All-or-nothing scheduling for multi-GPU jobs |
| dra | Dynamic Resource Allocation for GPU ResourceClaims |
| predicates | Standard Kubernetes scheduling constraints |
| proportion | Fair-share queue resource allocation |
| priority | PriorityClass-based ordering |
| nodeorder | Optimal node selection |
| binpack | GPU-aware bin packing (minimize fragmentation) |

## Queue Architecture

```
gpu-inference (weight: 10, 64 GPUs)
  |-- vllm-serving jobs (high priority)
  |-- lora-adapter jobs (medium priority)
  
gpu-training (weight: 5, 32 GPUs)
  |-- fine-tuning jobs (medium priority)
  
default (weight: 1, reclaimable)
  |-- batch inference jobs (low priority)
```

## Dependencies

- Kubernetes >= 1.29
- NVIDIA GPU Operator (for GPU device plugin and DRA driver)
- VictoriaMetrics (for scheduler metrics)

## DoD Criteria

From `docs/gpu-inference-dod.md`:
- Gang recovery time after single pod failure: < 30 seconds
- Initial gang scheduling time (8 replicas to Running): < 60 seconds
- DRA scheduling for 100 pods: < 5 seconds
