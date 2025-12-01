# Karpenter Implementation Summary

**Date**: 2025-11-30
**Karpenter Version**: 1.8.1
**Status**: ✅ Complete

## What Was Implemented

### 1. Karpenter Version Update ✅
- Updated from `1.1.1` to `1.8.1` in `terraform/modules/karpenter/variables.tf`
- Latest stable version with improved performance and features

### 2. NodePool Configurations ✅

Created four specialized NodePools to handle different workload types:

#### a. **x86-general-purpose** (Existing - Verified)
- **Location**: `kubernetes/karpenter/x86-nodepool.yaml`
- **Architecture**: x86/amd64
- **Instance Types**: M, C, R series (m6i, m7i, c6i, c7i, r6i, r7i, etc.)
- **Capacity**: 80% spot, 20% on-demand
- **Use Case**: General-purpose workloads, web apps, microservices
- **Cost Savings**: ~60-70% vs on-demand

#### b. **arm64-graviton** (Existing - Verified)
- **Location**: `kubernetes/karpenter/arm64-nodepool.yaml`
- **Architecture**: ARM64
- **Instance Types**: Graviton processors (m7g, c7g, r7g, m6g, c6g, r6g, t4g)
- **Capacity**: 90% spot, 10% on-demand
- **Use Case**: Cost-optimized workloads, cloud-native apps
- **Cost Savings**: ~70-80% vs on-demand x86

#### c. **c-series-compute** (NEW ✨)
- **Location**: `kubernetes/karpenter/c-series-nodepool.yaml`
- **Architecture**: x86/amd64
- **Instance Types**: C series only (c7i, c7a, c6i, c6a, c6in)
- **Capacity**: 70% spot, 30% on-demand
- **Use Case**: CPU-intensive tasks, batch processing, HPC
- **Special**: Requires toleration for `workload-type=compute-intensive`
- **Cost Savings**: ~50-60% vs on-demand

#### d. **spot-flexible** (NEW ✨)
- **Location**: `kubernetes/karpenter/spot-nodepool.yaml`
- **Architecture**: x86/amd64 + ARM64 (multi-arch)
- **Instance Types**: Wide range (M, C, R, T series, both x86 and Graviton)
- **Capacity**: 100% spot
- **Use Case**: Maximum cost savings, interruption-tolerant workloads
- **Special**: Requires toleration for `karpenter.sh/spot=true`
- **Cost Savings**: ~85-92% vs on-demand

### 3. Template System ✅

Created template files for automated rendering:

```
kubernetes/karpenter/templates/
├── render-templates.sh         # Updated to include new NodePools
├── x86-nodepool.yaml.tpl       # Existing
├── arm64-nodepool.yaml.tpl     # Existing
├── c-series-nodepool.yaml.tpl  # NEW ✨
└── spot-nodepool.yaml.tpl      # NEW ✨
```

The template system:
- Extracts cluster values from Terraform outputs
- Renders NodePools with actual IAM role names, cluster name, region
- Generates ready-to-apply YAML files

### 4. Comprehensive Documentation ✅

Created detailed README: `kubernetes/karpenter/README.md`

Includes:
- NodePool comparison table
- Quick start guide
- Deployment examples for each NodePool
- Architecture selection guide
- Best practices
- Cost optimization tips
- Troubleshooting guide
- Monitoring commands

## File Structure

```
project/platform-design/
├── terraform/modules/karpenter/
│   ├── main.tf              # Helm chart deployment
│   ├── variables.tf         # Updated version to 1.8.1 ✅
│   ├── outputs.tf
│   └── versions.tf
│
└── kubernetes/karpenter/
    ├── README.md                        # Comprehensive guide ✅
    │
    ├── x86-nodepool.yaml               # General-purpose x86
    ├── arm64-nodepool.yaml             # Graviton ARM64
    ├── c-series-nodepool.yaml          # NEW - C series compute ✅
    ├── spot-nodepool.yaml              # NEW - 100% spot ✅
    │
    └── templates/
        ├── render-templates.sh         # Updated script ✅
        ├── x86-nodepool.yaml.tpl
        ├── arm64-nodepool.yaml.tpl
        ├── c-series-nodepool.yaml.tpl  # NEW ✅
        └── spot-nodepool.yaml.tpl      # NEW ✅
```

## Quick Start Guide

### Step 1: Deploy Infrastructure

```bash
cd project/platform-design/terraform
terraform init
terraform apply
```

### Step 2: Render NodePool Templates

```bash
cd ../kubernetes/karpenter/templates
./render-templates.sh ../../../terraform
```

This generates:
- `x86-nodepool-rendered.yaml`
- `arm64-nodepool-rendered.yaml`
- `c-series-nodepool-rendered.yaml`
- `spot-nodepool-rendered.yaml`

### Step 3: Apply NodePools to Cluster

```bash
cd ..
kubectl apply -f x86-nodepool-rendered.yaml
kubectl apply -f arm64-nodepool-rendered.yaml
kubectl apply -f c-series-nodepool-rendered.yaml
kubectl apply -f spot-nodepool-rendered.yaml
```

### Step 4: Verify

```bash
# Check NodePools
kubectl get nodepool

# Expected output:
# NAME                  AGE
# x86-general-purpose   1m
# arm64-graviton        1m
# c-series-compute      1m
# spot-flexible         1m

# Check EC2NodeClasses
kubectl get ec2nodeclass

# Check Karpenter controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
```

## Usage Examples

### Example 1: General Web Application (x86)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 3
  template:
    spec:
      nodeSelector:
        karpenter.sh/nodepool: x86-general-purpose
      containers:
      - name: app
        image: nginx:latest
        resources:
          requests:
            cpu: "500m"
            memory: 1Gi
```

### Example 2: Cost-Optimized Microservice (Graviton)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
spec:
  replicas: 5
  template:
    spec:
      nodeSelector:
        karpenter.sh/nodepool: arm64-graviton
        kubernetes.io/arch: arm64
      containers:
      - name: api
        image: my-api:arm64
        resources:
          requests:
            cpu: "1"
            memory: 2Gi
```

### Example 3: CPU-Intensive Job (C-Series)

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: video-encoder
spec:
  template:
    spec:
      nodeSelector:
        karpenter.sh/nodepool: c-series-compute
      tolerations:
      - key: "workload-type"
        operator: "Equal"
        value: "compute-intensive"
        effect: "NoSchedule"
      containers:
      - name: encoder
        image: ffmpeg:latest
        resources:
          requests:
            cpu: "8"
            memory: 16Gi
      restartPolicy: Never
```

### Example 4: Maximum Cost Savings (Spot)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-processor
spec:
  replicas: 10
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
      - name: processor
        image: my-batch-app:latest
        resources:
          requests:
            cpu: "2"
            memory: 4Gi
```

## Cost Optimization Strategy

### Maximum Savings Approach

Combine Graviton + Spot for up to **92-94% cost reduction**:

```yaml
nodeSelector:
  karpenter.sh/nodepool: spot-flexible
  kubernetes.io/arch: arm64  # Will select ARM64 from spot pool
tolerations:
- key: "karpenter.sh/spot"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

### Balanced Approach

Use x86 general-purpose for reliable workloads with good savings:

```yaml
nodeSelector:
  karpenter.sh/nodepool: x86-general-purpose
# Automatically gets 80% spot, 20% on-demand
```

### Performance-First Approach

Use C-series for compute-intensive tasks:

```yaml
nodeSelector:
  karpenter.sh/nodepool: c-series-compute
tolerations:
- key: "workload-type"
  operator: "Equal"
  value: "compute-intensive"
  effect: "NoSchedule"
```

## Monitoring & Operations

### Check NodePool Status

```bash
kubectl get nodepool -o wide
```

### Monitor Karpenter Logs

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```

### View Node Provisioning

```bash
kubectl get nodes -l karpenter.sh/nodepool --watch
```

### Check Spot Interruptions

```bash
kubectl get events --field-selector reason=SpotInterruption
```

## Next Steps

1. **Test Deployment** - Deploy a test workload to each NodePool
2. **Monitor Costs** - Track AWS costs to verify savings
3. **Optimize Settings** - Adjust NodePool limits and ratios based on usage
4. **Add Monitoring** - Set up CloudWatch dashboards for Karpenter metrics
5. **Document Patterns** - Document workload-to-NodePool mapping for your team

## Technical Details

### Karpenter Controller Configuration

- **Namespace**: kube-system
- **Replicas**: 2 (HA)
- **Resource Requests**: 500m CPU, 512Mi memory
- **Resource Limits**: 1000m CPU, 1Gi memory
- **Pod Disruption Budget**: Enabled (minAvailable: 1)

### IAM Integration

- **Controller Role**: Created by EKS Karpenter submodule (Pod Identity)
- **Node Role**: Created by EKS Karpenter submodule
- **Interruption Handling**: SQS queue for spot termination warnings

### Networking

- **Subnets**: Auto-discovered via `karpenter.sh/discovery` tag
- **Security Groups**: Auto-discovered via `karpenter.sh/discovery` tag
- **VPC**: Uses cluster VPC

## Support & Troubleshooting

### Common Issues

1. **Pods not scheduling**: Check tolerations match NodePool taints
2. **Nodes not provisioning**: Verify IAM roles and subnet tags
3. **High costs**: Review NodePool limits and consolidation settings
4. **Spot interruptions**: Increase instance type diversity

### Getting Help

```bash
# Describe NodePool
kubectl describe nodepool <name>

# Describe EC2NodeClass
kubectl describe ec2nodeclass <name>

# Check Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100
```

## References

- [Karpenter v1.8.1 Release Notes](https://github.com/aws/karpenter/releases/tag/v1.8.1)
- [AWS Graviton Getting Started](https://github.com/aws/aws-graviton-getting-started)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Spot Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)

---

**Implementation Complete** ✅

All Karpenter NodePools are configured and ready for deployment!
