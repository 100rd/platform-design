# Karpenter NodePool Configurations

This directory contains Karpenter NodePool configurations for the EKS cluster. Karpenter is an open-source Kubernetes cluster autoscaler that provides fast, flexible node provisioning.

## Overview

**Karpenter Version**: 1.8.1

We have configured four specialized NodePools to handle different workload types:

1. **x86-general-purpose** - General-purpose x86 workloads (M, C, R series)
2. **arm64-graviton** - Cost-optimized ARM64/Graviton workloads
3. **c-series-compute** - Compute-intensive workloads (C series only)
4. **spot-flexible** - Maximum cost savings with 100% spot instances

## NodePool Comparison

| NodePool | Architecture | Instance Types | Capacity Type | Best For | Cost Savings |
|----------|-------------|----------------|---------------|----------|--------------|
| x86-general-purpose | x86/amd64 | M, C, R series | 80% spot, 20% on-demand | General workloads | ~60-70% |
| arm64-graviton | ARM64 | Graviton (m7g, c7g, r7g) | 90% spot, 10% on-demand | Cost-sensitive workloads | ~70-80% |
| c-series-compute | x86/amd64 | C series only | 70% spot, 30% on-demand | CPU-intensive tasks | ~50-60% |
| spot-flexible | x86 + ARM64 | All M, C, R, T series | 100% spot | Interruption-tolerant | ~85-92% |

## Quick Start

### 1. Render Templates

Before applying NodePools, render the templates with your cluster-specific values:

```bash
cd kubernetes/karpenter/templates
./render-templates.sh ../../../terraform
```

This will generate:
- `x86-nodepool-rendered.yaml`
- `arm64-nodepool-rendered.yaml`
- `c-series-nodepool-rendered.yaml`
- `spot-nodepool-rendered.yaml`

### 2. Apply NodePools

Apply all NodePools to your cluster:

```bash
cd kubernetes/karpenter
kubectl apply -f x86-nodepool-rendered.yaml
kubectl apply -f arm64-nodepool-rendered.yaml
kubectl apply -f c-series-nodepool-rendered.yaml
kubectl apply -f spot-nodepool-rendered.yaml
```

Or apply selectively based on your needs:

```bash
# Only spot instances for cost optimization
kubectl apply -f spot-nodepool-rendered.yaml

# Only Graviton for cost + performance
kubectl apply -f arm64-nodepool-rendered.yaml
```

### 3. Verify Installation

```bash
# Check NodePools
kubectl get nodepool

# Check EC2NodeClasses
kubectl get ec2nodeclass

# Check Karpenter controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
```

## Using NodePools in Your Deployments

### General Purpose (x86)

**Use for**: Web applications, microservices, general workloads

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  template:
    spec:
      nodeSelector:
        karpenter.sh/nodepool: x86-general-purpose
        kubernetes.io/arch: amd64
      containers:
      - name: app
        image: my-app:latest
        resources:
          requests:
            cpu: "1"
            memory: 2Gi
```

### Graviton (ARM64)

**Use for**: Cost-sensitive applications, stateless services, containerized apps

**Savings**: 20-40% better price/performance vs x86

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: arm64-app
spec:
  replicas: 5
  template:
    spec:
      nodeSelector:
        karpenter.sh/nodepool: arm64-graviton
        kubernetes.io/arch: arm64
      containers:
      - name: app
        image: my-app:latest  # Must support ARM64
        resources:
          requests:
            cpu: "500m"
            memory: 1Gi
```

**Important**: Ensure your container images support ARM64 architecture.

### C-Series Compute

**Use for**: CPU-intensive tasks, batch processing, video encoding, ML inference

**Note**: Requires toleration for workload-type taint

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: compute-intensive-job
spec:
  replicas: 2
  template:
    spec:
      nodeSelector:
        karpenter.sh/nodepool: c-series-compute
        instance-category: c-series
      tolerations:
      - key: "workload-type"
        operator: "Equal"
        value: "compute-intensive"
        effect: "NoSchedule"
      containers:
      - name: processor
        image: my-compute-app:latest
        resources:
          requests:
            cpu: "4"
            memory: 8Gi
          limits:
            cpu: "8"
            memory: 16Gi
```

### Spot Flexible

**Use for**: Stateless apps, batch jobs, CI/CD, development/staging

**Savings**: Up to 90% vs on-demand pricing

**Note**: Requires toleration for spot taint

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spot-app
spec:
  replicas: 10  # Use higher replica count for resilience
  template:
    spec:
      nodeSelector:
        karpenter.sh/nodepool: spot-flexible
      tolerations:
      - key: "karpenter.sh/spot"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
      containers:
      - name: app
        image: my-app:latest
        resources:
          requests:
            cpu: "500m"
            memory: 1Gi
```

## Architecture Selection Guide

### Choose x86 when:
- You need broad software compatibility
- Using legacy applications
- Maximum performance for single-threaded workloads
- Vendor-specific software requires x86

### Choose ARM64/Graviton when:
- Cost optimization is a priority
- Running cloud-native applications
- Using containerized microservices
- Workloads support ARM64 (most modern apps do)
- Better energy efficiency matters

### Choose C-Series when:
- CPU is the primary bottleneck
- Running compute-intensive batch jobs
- Video/image processing
- High-performance computing (HPC)
- Machine learning inference
- Scientific simulations

### Choose Spot when:
- Workloads are interruption-tolerant
- Running stateless applications
- Batch processing with retry logic
- Development/testing environments
- Cost is the primary concern
- Using queue-based processing

## Best Practices

### 1. Pod Disruption Budgets

Always use PodDisruptionBudgets with spot instances:

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

### 2. Graceful Shutdown

Handle SIGTERM signals for spot interruptions:

```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 15"]
```

### 3. Right-Sizing Resources

Request only what you need:

```yaml
resources:
  requests:
    cpu: "500m"      # What you need
    memory: 1Gi
  limits:
    cpu: "1000m"     # Maximum allowed
    memory: 2Gi
```

### 4. Use Topology Spread

Distribute pods across nodes and zones:

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: my-app
```

### 5. Monitor Spot Interruptions

Watch for spot interruption events:

```bash
kubectl get events --field-selector reason=SpotInterruption
```

## Monitoring Karpenter

### Check NodePool Status

```bash
kubectl get nodepool -o wide
```

### View Provisioner Logs

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```

### Monitor Node Provisioning

```bash
kubectl get nodes -l karpenter.sh/nodepool --watch
```

### Check EC2NodeClass

```bash
kubectl describe ec2nodeclass
```

## Troubleshooting

### Pods Not Scheduling

1. Check NodePool requirements match pod requirements
2. Verify pod tolerations for tainted NodePools
3. Check NodePool capacity limits
4. Review Karpenter logs

```bash
kubectl describe pod <pod-name>
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100
```

### Nodes Not Provisioning

1. Verify IAM roles and policies
2. Check subnet and security group tags
3. Ensure instance types are available in your region
4. Review AWS Service Quotas

```bash
kubectl describe nodepool <nodepool-name>
```

### Spot Interruptions Too Frequent

1. Increase instance type diversity
2. Add on-demand capacity
3. Use PodDisruptionBudgets
4. Implement proper graceful shutdown

## Cost Optimization Tips

### 1. Prefer Graviton + Spot

Combine ARM64 and spot for maximum savings (up to 92-94%):

```yaml
nodeSelector:
  kubernetes.io/arch: arm64
  capacity-type: spot
tolerations:
- key: "karpenter.sh/spot"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

### 2. Use Consolidation

Karpenter automatically consolidates underutilized nodes. Monitor with:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter | grep consolidation
```

### 3. Set Appropriate Limits

Configure NodePool limits to control costs:

```yaml
limits:
  cpu: "100"
  memory: 200Gi
```

### 4. Use Mixed Capacity Types

Balance cost and reliability with spot/on-demand mix already configured in NodePools.

## Example Workloads

### Web Application (High Availability)

```yaml
# Use general-purpose with mixed capacity
nodeSelector:
  karpenter.sh/nodepool: x86-general-purpose
# 80% spot, 20% on-demand (configured in NodePool)
```

### Batch Processing

```yaml
# Use 100% spot for maximum savings
nodeSelector:
  karpenter.sh/nodepool: spot-flexible
tolerations:
- key: "karpenter.sh/spot"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

### Machine Learning Inference

```yaml
# Use C-series for CPU-intensive inference
nodeSelector:
  karpenter.sh/nodepool: c-series-compute
tolerations:
- key: "workload-type"
  operator: "Equal"
  value: "compute-intensive"
  effect: "NoSchedule"
```

### Microservices (Cost-Optimized)

```yaml
# Use Graviton for 20-40% cost savings
nodeSelector:
  karpenter.sh/nodepool: arm64-graviton
  kubernetes.io/arch: arm64
```

## Additional Resources

- [Karpenter Documentation](https://karpenter.sh/)
- [AWS Graviton Getting Started](https://github.com/aws/aws-graviton-getting-started)
- [EKS Best Practices - Karpenter](https://aws.github.io/aws-eks-best-practices/karpenter/)
- [Spot Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)

## Support

For issues or questions:
1. Check Karpenter logs
2. Review AWS CloudWatch logs
3. Verify IAM permissions
4. Check AWS Service Quotas

```bash
# Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter

# Describe NodePool
kubectl describe nodepool <name>

# Describe EC2NodeClass
kubectl describe ec2nodeclass <name>
```
