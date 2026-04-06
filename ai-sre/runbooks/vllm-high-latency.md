---
id: vllm-high-latency
name: vLLM Inference High Latency
category: inference
severity: high
clusters: [gpu-inference]
auto_executable_steps: [1, 2, 3]
approval_required_steps: [4, 5]
---

## Symptoms
- vLLM p99 latency exceeding SLO threshold
- Request queue depth growing
- GPU memory pressure on inference nodes

## Steps

### Step 1: Check vLLM metrics (auto)
```query
vllm_num_requests_waiting{namespace="gpu-inference"}
vllm_avg_generation_throughput_toks_per_s{namespace="gpu-inference"}
vllm_gpu_cache_usage_perc{namespace="gpu-inference"}
```

### Step 2: Check GPU memory and utilization (auto)
```kubectl
kubectl top pods -n gpu-inference --sort-by=memory | head -20
```

### Step 3: Check for recent config changes (auto)
```query
git log --since="4h" --oneline -- apps/gpu-inference/vllm/
```

### Step 4: Scale up vLLM replicas (requires approval)
```kubectl
kubectl scale deployment/vllm-inference -n gpu-inference --replicas={target_replicas}
```

### Step 5: Adjust KV cache configuration (requires approval)
```kubectl
kubectl edit configmap vllm-config -n gpu-inference
```
