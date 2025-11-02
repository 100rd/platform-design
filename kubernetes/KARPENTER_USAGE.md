# Karpenter Multi-Architecture Usage Guide

Complete guide for deploying workloads on x86 and ARM64/Graviton nodes using Karpenter.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Architecture Selection](#architecture-selection)
- [Deploying Workloads](#deploying-workloads)
- [NodePool Details](#nodepool-details)
- [Cost Optimization](#cost-optimization)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

**Karpenter** automatically provisions compute nodes based on pod requirements. This setup supports:

- **x86/amd64**: Intel and AMD processors (m6i, m7i, c6i, c7i, r6i, r7i families)
- **ARM64**: AWS Graviton2 and Graviton3 processors (m7g, c7g, r7g, m6g, c6g, r6g, t4g)
- **Mixed Capacity**: Spot instances (primary) + On-Demand (fallback)
- **Auto-Consolidation**: Automatic bin-packing and rightsizing

---

## Prerequisites

1. **EKS Cluster** deployed with Karpenter submodule enabled
2. **Karpenter Helm Chart** installed
3. **kubectl** configured for your cluster
4. **NodePools** applied (x86 and/or ARM64)

### Verify Karpenter is Running

```bash
kubectl get pods -n kube-system | grep karpenter
# Should show: karpenter-controller-xxxxx   Running
```

### Check NodePools

```bash
kubectl get nodepools
# Should show: x86-general-purpose, arm64-graviton
```

---

## Quick Start

### Deploy on x86 Architecture

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-x86-app
spec:
  replicas: 3
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
        karpenter.sh/nodepool: x86-general-purpose
      containers:
        - name: app
          image: nginx:latest
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
```

###Deploy on ARM64/Graviton

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-arm64-app
spec:
  replicas: 5
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
        karpenter.sh/nodepool: arm64-graviton
      containers:
        - name: app
          image: nginx:latest  # Multi-arch image
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
```

---

## Architecture Selection

### How to Choose Architecture

| Use x86 when... | Use ARM64 when... |
|-----------------|-------------------|
| Legacy applications | Cost optimization is priority |
| Proprietary x86-only software | Modern cloud-native apps |
| Maximum compatibility needed | Multi-arch images available |
| Specific x86 dependencies | 20-40% cost savings desired |

### Compatibility Check

**ARM64-Compatible:**
✅ Go, Rust, Python, Node.js, Java
✅ Docker images with `linux/arm64` support
✅ Most open-source software
✅ PostgreSQL, MySQL, Redis, MongoDB, Kafka

**May Need x86:**
⚠️ Proprietary software without ARM builds
⚠️ Legacy applications
⚠️ Some commercial databases

---

## Deploying Workloads

### Step 1: Check Multi-Arch Image Support

```bash
# Check if your image supports both architectures
docker manifest inspect nginx:latest | grep architecture

# Should show both:
# "architecture": "amd64"
# "architecture": "arm64"
```

### Step 2: Add Node Selector

Choose your target architecture:

**For x86:**
```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: amd64
    karpenter.sh/nodepool: x86-general-purpose
```

**For ARM64:**
```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
    karpenter.sh/nodepool: arm64-graviton
```

### Step 3: Set Resource Requests

Karpenter provisions nodes based on resource requests:

```yaml
resources:
  requests:
    cpu: "500m"      # Triggers node provisioning
    memory: "1Gi"    # if no suitable node exists
  limits:
    cpu: "1000m"
    memory: "2Gi"
```

### Step 4: Deploy

```bash
kubectl apply -f your-deployment.yaml

# Watch Karpenter provision nodes
kubectl get nodes -w

# Check pod placement
kubectl get pods -o wide
```

---

## NodePool Details

### x86 NodePool (`x86-general-purpose`)

**Instance Families:**
- **Compute Optimized**: c6i, c6a, c7i, c7a (Intel/AMD latest gen)
- **General Purpose**: m6i, m6a, m7i, m7a
- **Memory Optimized**: r6i, r6a, r7i, r7a

**CPU Options**: 2, 4, 8, 16, 32 cores

**Capacity Mix**: 80% Spot, 20% On-Demand

**Use Cases**:
- General-purpose applications
- Databases requiring x86
- Legacy workloads
- Maximum compatibility

### ARM64 NodePool (`arm64-graviton`)

**Instance Families:**
- **Graviton3**: m7g, c7g, r7g (latest, best performance)
- **Graviton2**: m6g, c6g, r6g
- **Burstable**: t4g (cost-effective for low-traffic apps)
- **Network Optimized**: c7gn (up to 200 Gbps)
- **Storage Optimized**: m7gd, c7gd, r7gd (NVMe SSD)

**CPU Options**: 2, 4, 8, 16, 32, 64 cores

**Capacity Mix**: 90% Spot, 10% On-Demand (more aggressive savings)

**Cost Savings**: 20-40% vs comparable x86

**Use Cases**:
- Microservices
- Web applications
- API servers
- Data processing pipelines
- Cost-sensitive workloads

---

## Cost Optimization

### 1. Prefer Graviton for Savings

```yaml
# Switch from x86 to ARM64 for 20-40% savings
nodeSelector:
  kubernetes.io/arch: arm64
  karpenter.sh/nodepool: arm64-graviton
```

### 2. Right-Size Resource Requests

```yaml
# Don't over-request resources
resources:
  requests:
    cpu: "100m"      # Start small
    memory: "128Mi"  # Scale up if needed
```

### 3. Use Spot Instances

Both NodePools prefer Spot instances automatically:
- x86: 80% Spot / 20% On-Demand
- ARM64: 90% Spot / 10% On-Demand

### 4. Let Karpenter Consolidate

Karpenter automatically:
- Bins pack pods onto fewer nodes
- Consolidates underutilized nodes
- Replaces nodes with cheaper options
- Terminates empty nodes after 30s

### 5. Monitor Costs

```bash
# Check node costs (requires AWS Cost Explorer)
kubectl get nodes -o custom-columns=NAME:.metadata.name,INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type

# Compare x86 vs ARM64 costs
# ARM64 will show 20-40% lower costs for same workload
```

---

## Troubleshooting

### Pods Stuck in Pending

**Check pod events:**
```bash
kubectl describe pod <pod-name>
```

**Common Issues:**

1. **No matching NodePool**
   ```
   Error: No NodePool matched pod requirements
   ```
   **Fix**: Verify nodeSelector matches NodePool labels

2. **Resource limits too high**
   ```
   Error: Insufficient resources
   ```
   **Fix**: Check NodePool limits (cpu: 1000, memory: 1000Gi)

3. **Wrong architecture**
   ```
   Error: Pod not scheduling
   ```
   **Fix**: Ensure image supports target architecture

### Karpenter Not Provisioning Nodes

**Check Karpenter logs:**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```

**Common Issues:**

1. **IAM permissions**
   ```
   Error: AccessDenied
   ```
   **Fix**: Verify IAM role and policies

2. **Subnet not tagged**
   ```
   Error: No subnets found
   ```
   **Fix**: Ensure subnets have `karpenter.sh/discovery: cluster-name` tag

3. **Security group not tagged**
   ```
   Error: No security groups found
   ```
   **Fix**: Ensure security groups have `karpenter.sh/discovery: cluster-name` tag

### Nodes Not Consolidating

**Check consolidation settings:**
```bash
kubectl describe nodepool x86-general-purpose
# Look for: consolidationPolicy: WhenEmptyOrUnderutilized
```

**Force consolidation:**
```bash
# Consolidation happens automatically every 30s
# To trigger immediately, delete underutilized nodes:
kubectl delete node <node-name>
```

### Wrong Architecture Pods

**Verify pod architecture:**
```bash
kubectl get pod <pod-name> -o jsonpath='{.spec.nodeSelector}'

# Should show: {"kubernetes.io/arch":"arm64"} or {"kubernetes.io/arch":"amd64"}
```

**Check running architecture:**
```bash
kubectl exec <pod-name> -- uname -m
# arm64 (aarch64) or x86_64 (amd64)
```

---

## Best Practices

### 1. Use Multi-Arch Images

Build or use images that support both architectures:

```dockerfile
# Build multi-arch image
docker buildx build --platform linux/amd64,linux/arm64 -t myapp:latest .
```

### 2. Set Resource Requests Accurately

```yaml
# Measure actual usage first, then set requests
resources:
  requests:
    cpu: "100m"      # Based on actual usage
    memory: "256Mi"  # Not arbitrary large values
```

### 3. Use PodDisruptionBudgets

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: my-app
```

### 4. Implement Pod Anti-Affinity

Spread pods across nodes and AZs:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: my-app
          topologyKey: kubernetes.io/hostname
```

### 5. Use HorizontalPodAutoscaler

Let HPA scale pods, Karpenter scales nodes:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 3
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### 6. Monitor and Alert

```bash
# Watch Karpenter metrics
kubectl top nodes

# Check pod distribution
kubectl get pods -o wide --sort-by='.spec.nodeName'

# Karpenter Prometheus metrics (if enabled):
# - karpenter_nodes_created
# - karpenter_nodes_terminated
# - karpenter_pods_state
```

---

## Example Workflows

### Migrate x86 App to ARM64

1. **Verify image compatibility:**
   ```bash
   docker manifest inspect myapp:latest | grep architecture
   ```

2. **Create test deployment:**
   ```yaml
   # test-arm64.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: myapp-arm64-test
   spec:
     replicas: 1
     template:
       spec:
         nodeSelector:
           kubernetes.io/arch: arm64
   ```

3. **Deploy and test:**
   ```bash
   kubectl apply -f test-arm64.yaml
   kubectl logs -f deployment/myapp-arm64-test
   ```

4. **Compare performance:**
   ```bash
   # Run load tests on both architectures
   # Compare latency, throughput, and cost
   ```

5. **Gradual rollout:**
   ```yaml
   # Canary: 10% ARM64, 90% x86
   # Then: 50% ARM64, 50% x86
   # Finally: 100% ARM64
   ```

### Scale Testing

```bash
# 1. Deploy test workload
kubectl apply -f test-deployment.yaml

# 2. Scale up
kubectl scale deployment test-app --replicas=50

# 3. Watch Karpenter provision nodes
watch kubectl get nodes

# 4. Check node provisioning time
# Should be < 60 seconds

# 5. Scale down
kubectl scale deployment test-app --replicas=0

# 6. Watch consolidation
# Nodes should terminate after 30s
```

---

## Additional Resources

- [Karpenter Documentation](https://karpenter.sh/)
- [AWS Graviton Getting Started](https://github.com/aws/aws-graviton-getting-started)
- [EKS Best Practices - Karpenter](https://aws.github.io/aws-eks-best-practices/karpenter/)
- [Multi-Arch Container Images](https://www.docker.com/blog/multi-arch-build-and-images-the-simple-way/)

---

## Support

**Issues?** Check:
1. Karpenter logs: `kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter`
2. NodePool status: `kubectl describe nodepool <name>`
3. Pod events: `kubectl describe pod <name>`

**Questions?** See [troubleshooting guide](#troubleshooting) above.

---

**🚀 Happy autoscaling with Karpenter and multi-architecture support!**
