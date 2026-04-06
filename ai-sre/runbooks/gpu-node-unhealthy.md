---
id: gpu-node-unhealthy
name: GPU Node Unhealthy Response
category: gpu-health
severity: high
clusters: [gpu-inference, gpu-analysis]
auto_executable_steps: [1, 2, 3]
approval_required_steps: [4, 5]
---

## Symptoms
- DCGM XID errors detected
- GPU utilization drops to 0%
- Pod scheduling failures on GPU nodes

## Steps

### Step 1: Gather GPU diagnostics (auto)
```kubectl
kubectl describe node {node} | grep -A 20 "Allocated resources"
kubectl logs -n gpu-operator -l app=nvidia-dcgm-exporter --tail=100
```

### Step 2: Check recent deployments (auto)
```query
git log --since="2h" --oneline -- apps/gpu-inference/
```

### Step 3: Verify GPU operator status (auto)
```kubectl
kubectl get pods -n gpu-operator -o wide
```

### Step 4: Cordon node (requires approval)
```kubectl
kubectl cordon {node}
```

### Step 5: Drain and replace node (requires approval)
```kubectl
kubectl drain {node} --ignore-daemonsets --delete-emptydir-data
```
