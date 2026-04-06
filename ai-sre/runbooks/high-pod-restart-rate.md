---
id: high-pod-restart-rate
name: High Pod Restart Rate Investigation
category: workload-health
severity: medium
clusters: [gpu-inference, platform, blockchain, gpu-analysis]
auto_executable_steps: [1, 2, 3]
approval_required_steps: [4]
---

## Symptoms
- Pod restart count increasing rapidly
- CrashLoopBackOff observed
- OOMKilled events

## Steps

### Step 1: Identify crashing pods (auto)
```kubectl
kubectl get pods -n {namespace} --sort-by='.status.containerStatuses[0].restartCount' | tail -20
```

### Step 2: Check pod events and logs (auto)
```kubectl
kubectl describe pod {pod} -n {namespace}
kubectl logs {pod} -n {namespace} --previous --tail=200
```

### Step 3: Check resource usage (auto)
```query
SELECT timestamp, pod, container, memory_usage_bytes, memory_limit_bytes
FROM k8s_pod_metrics
WHERE namespace = '{namespace}' AND timestamp > now() - INTERVAL 1 HOUR
ORDER BY memory_usage_bytes DESC LIMIT 20
```

### Step 4: Rollback deployment (requires approval)
```kubectl
kubectl rollout undo deployment/{deployment} -n {namespace}
```
