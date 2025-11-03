# Simple EKS + Karpenter Environment

**Quick-start environment for deploying EKS with Karpenter and multi-architecture support (x86 and ARM64/Graviton).**

---

## 📋 What This Deploys

This Terragrunt configuration deploys:

1. **Dedicated VPC** (10.0.0.0/16)
   - 3 public subnets
   - 3 private subnets
   - NAT Gateway for internet access
   - Tagged for Karpenter subnet discovery

2. **EKS Cluster** (Kubernetes 1.34)
   - Latest Kubernetes version
   - Pod Identity enabled
   - 2-3 controller nodes (t3.medium)
   - Karpenter submodule integrated

3. **Karpenter Autoscaling**
   - IAM roles configured
   - SQS queue for spot termination
   - EventBridge rules for capacity management
   - Ready for x86 and ARM64 NodePools

---

## ⚡ Quick Start (5 Minutes)

### Prerequisites

Install required tools:

```bash
# Terragrunt
brew install terragrunt  # macOS
# or download from: https://terragrunt.gruntwork.io/docs/getting-started/install/

# AWS CLI
aws configure  # Set your credentials

# kubectl
brew install kubectl
```

### Deploy

```bash
# 1. Navigate to this directory
cd terragrunt/envs/simple

# 2. Initialize and deploy everything
terragrunt run-all init
terragrunt run-all apply

# 3. Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name simple-eks-cluster

# 4. Verify cluster
kubectl get nodes
# Should show 2-3 nodes (Karpenter controllers)

# 5. Deploy Karpenter NodePools
kubectl apply -f ../../../kubernetes/karpenter/x86-nodepool.yaml
kubectl apply -f ../../../kubernetes/karpenter/arm64-nodepool.yaml

# 6. Verify NodePools
kubectl get nodepools
# Should show: x86-general-purpose, arm64-graviton

# 7. Deploy example applications
kubectl apply -f ../../../kubernetes/deployments/x86-example.yaml
kubectl apply -f ../../../kubernetes/deployments/arm64-graviton-example.yaml

# 8. Watch Karpenter provision nodes
watch kubectl get nodes
# New nodes will appear as pods request resources
```

**That's it! Your EKS cluster with Karpenter is running.**

---

## 📂 Structure

```
terragrunt/envs/simple/
├── README.md              # This file
├── terragrunt.hcl         # Environment configuration
├── vpc/
│   └── terragrunt.hcl     # VPC module configuration
└── eks/
    └── terragrunt.hcl     # EKS + Karpenter configuration
```

---

## 🎯 How to Deploy Workloads

### Option 1: Deploy on x86 (Intel/AMD)

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

Apply it:
```bash
kubectl apply -f my-x86-app.yaml

# Karpenter will automatically provision x86 nodes
kubectl get nodes -l kubernetes.io/arch=amd64
```

### Option 2: Deploy on ARM64/Graviton (20-40% Cheaper)

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

Apply it:
```bash
kubectl apply -f my-arm64-app.yaml

# Karpenter will automatically provision ARM64 Graviton nodes
kubectl get nodes -l kubernetes.io/arch=arm64
```

---

## 🏗️ Architecture Details

### VPC Configuration

| Setting | Value |
|---------|-------|
| CIDR Block | 10.0.0.0/16 |
| Public Subnets | 3 (across 3 AZs) |
| Private Subnets | 3 (across 3 AZs) |
| NAT Gateway | 1 (single NAT) |
| Karpenter Discovery Tag | `karpenter.sh/discovery: simple-eks-cluster` |

### EKS Configuration

| Setting | Value |
|---------|-------|
| Kubernetes Version | 1.34 (latest) |
| Authentication | API_AND_CONFIG_MAP |
| Pod Identity | Enabled |
| IRSA | Enabled (for compatibility) |
| Controller Nodes | 2-3 x t3.medium (On-Demand) |

### Karpenter Configuration

| Feature | Details |
|---------|---------|
| **x86 NodePool** | Instance families: m6i, m7i, c6i, c7i, r6i, r7i |
| | Capacity mix: 80% Spot, 20% On-Demand |
| | CPU options: 2, 4, 8, 16, 32 cores |
| **ARM64 NodePool** | Instance families: m7g, c7g, r7g, m6g, c6g, r6g |
| | Capacity mix: 90% Spot, 10% On-Demand |
| | CPU options: 2, 4, 8, 16, 32, 64 cores |
| | **Cost savings**: 20-40% vs x86 |
| **Consolidation** | After 30s of underutilization |
| **Spot Termination** | Automated via SQS queue |

---

## 💰 Cost Estimation

### Monthly Costs (Approximate)

**Infrastructure (Always Running):**
- EKS Control Plane: ~$73/month
- NAT Gateway: ~$32/month
- Controller Nodes: 2 x t3.medium = ~$60/month
- **Subtotal: ~$165/month**

**Application Workloads (Variable):**
- x86 instances (spot): ~$0.02-0.05/hour per vCPU
- ARM64 Graviton (spot): ~$0.015-0.035/hour per vCPU (20-40% cheaper)

**Example Scenarios:**

| Workload | Architecture | Instances | Monthly Cost |
|----------|--------------|-----------|--------------|
| Dev/Test (low traffic) | ARM64 | 2-3 x t4g.medium | $10-20 |
| Small Production | Mixed | 5-10 mixed | $50-150 |
| Medium Production | Mixed | 10-20 mixed | $150-400 |

**Total Estimated Cost for Dev Cluster: $175-200/month**

### Cost Optimization Tips

1. **Use ARM64/Graviton**: 20-40% savings vs x86
2. **Leverage Spot Instances**: Up to 90% savings vs On-Demand
3. **Enable Consolidation**: Automatic bin-packing saves 30%+
4. **Delete Non-Production Clusters Overnight**: Save 50% on dev/test

---

## 🔧 Configuration

### Customize VPC

Edit `vpc/terragrunt.hcl`:

```hcl
inputs = {
  vpc_cidr = "10.1.0.0/16"  # Change CIDR

  tags = {
    Environment = "production"
    CostCenter  = "engineering"
  }
}
```

### Customize EKS

Edit `eks/terragrunt.hcl`:

```hcl
inputs = {
  cluster_version = "1.34"  # Update K8s version

  # More controller nodes for production
  karpenter_controller_desired_size = 3

  # Add SSM access for debugging
  karpenter_node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}
```

### Customize NodePools

Edit `../../../kubernetes/karpenter/x86-nodepool.yaml`:

```yaml
# Change instance families
- key: karpenter.k8s.aws/instance-family
  operator: In
  values: ["m7i", "c7i"]  # Only latest generation

# Change spot/on-demand ratio
- key: karpenter.sh/capacity-type
  operator: In
  values: ["spot"]  # 100% spot for maximum savings
```

---

## 🎛️ Common Operations

### Scale Up

```bash
# Deploy more replicas - Karpenter auto-scales nodes
kubectl scale deployment my-app --replicas=20
watch kubectl get nodes  # Watch new nodes appear
```

### Scale Down

```bash
# Reduce replicas - Karpenter consolidates nodes
kubectl scale deployment my-app --replicas=2
# Wait 30s, underutilized nodes will be removed
```

### Check Karpenter Logs

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```

### View NodePool Status

```bash
kubectl describe nodepool x86-general-purpose
kubectl describe nodepool arm64-graviton
```

### Check Pod Placement

```bash
# See which nodes pods are running on
kubectl get pods -o wide

# Filter by architecture
kubectl get pods -o wide --field-selector spec.nodeSelector.kubernetes\\.io/arch=arm64
```

### Force Node Consolidation

```bash
# Karpenter will automatically consolidate, but you can force it:
kubectl delete node <underutilized-node-name>
# Karpenter will reschedule pods and provision right-sized nodes
```

---

## 🔍 Troubleshooting

### Pods Stuck in Pending

```bash
# Check pod events
kubectl describe pod <pod-name>

# Common issues:
# 1. Resource requests too high - reduce CPU/memory requests
# 2. No matching NodePool - verify nodeSelector matches NodePool
# 3. Instance type unavailable - check AWS availability in your region
```

### Karpenter Not Provisioning Nodes

```bash
# Check Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f

# Common issues:
# 1. IAM permissions - verify Karpenter IAM role
# 2. Subnet tags missing - check subnets have karpenter.sh/discovery tag
# 3. Security group tags - check security groups have discovery tag
```

### Wrong Architecture

```bash
# Verify pod is on correct architecture
kubectl get pod <pod-name> -o jsonpath='{.spec.nodeName}' | xargs kubectl get node -o json | jq '.metadata.labels["kubernetes.io/arch"]'

# Check inside pod
kubectl exec <pod-name> -- uname -m
# arm64 (aarch64) or x86_64 (amd64)
```

### Nodes Not Consolidating

```bash
# Check consolidation settings
kubectl get nodepool x86-general-purpose -o yaml | grep -A 5 disruption

# Consolidation happens every 30s automatically
# Ensure pods have proper PodDisruptionBudgets
```

---

## 🧹 Cleanup

### Delete Applications First

```bash
# Delete example deployments
kubectl delete -f ../../../kubernetes/deployments/

# Delete NodePools
kubectl delete -f ../../../kubernetes/karpenter/

# Wait for Karpenter to drain nodes (30-60s)
kubectl get nodes -w
```

### Destroy Infrastructure

```bash
# From terragrunt/envs/simple directory
terragrunt run-all destroy

# Confirm when prompted
```

### Verify Cleanup

```bash
# Check EKS cluster is gone
aws eks list-clusters --region us-east-1

# Check VPC is deleted
aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=simple"
```

---

## 📚 Additional Resources

### Documentation
- [Karpenter Usage Guide](../../../kubernetes/KARPENTER_USAGE.md)
- [Platform Overview](../../../docs/platform-overview.md)
- [CHANGELOG](../../../CHANGELOG.md)

### External Links
- [Karpenter Official Docs](https://karpenter.sh/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [AWS Graviton Guide](https://github.com/aws/aws-graviton-getting-started)
- [Terraform AWS EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/)

---

## ⚡ Quick Reference

### Deploy Everything
```bash
cd terragrunt/envs/simple
terragrunt run-all apply
aws eks update-kubeconfig --region us-east-1 --name simple-eks-cluster
kubectl apply -f ../../../kubernetes/karpenter/
```

### Deploy on x86
```yaml
nodeSelector:
  kubernetes.io/arch: amd64
  karpenter.sh/nodepool: x86-general-purpose
```

### Deploy on ARM64 (cheaper)
```yaml
nodeSelector:
  kubernetes.io/arch: arm64
  karpenter.sh/nodepool: arm64-graviton
```

### Check Status
```bash
kubectl get nodes
kubectl get nodepools
kubectl get pods -o wide
```

### Destroy Everything
```bash
kubectl delete -f ../../../kubernetes/deployments/
kubectl delete -f ../../../kubernetes/karpenter/
terragrunt run-all destroy
```

---

## 🎯 Success Criteria

After deployment, you should see:

✅ **Infrastructure**
- VPC with 6 subnets (3 public, 3 private)
- EKS cluster running Kubernetes 1.34
- 2-3 controller nodes (t3.medium)

✅ **Karpenter**
- Karpenter controller pods running
- 2 NodePools available (x86, arm64)
- No application nodes yet (provisioned on-demand)

✅ **Applications**
- x86 example: 3 pods on amd64 nodes
- ARM64 example: 5 pods on arm64 nodes
- Nodes automatically provisioned by Karpenter

✅ **Cost Optimization**
- Spot instances preferred (80-90%)
- Graviton saves 20-40% vs x86
- Auto-consolidation after 30s

---

## 💡 Next Steps

1. **Experiment with architectures**
   - Deploy same app on x86 and ARM64
   - Compare performance and cost

2. **Add monitoring**
   - Install Prometheus + Grafana
   - Track cost and performance metrics

3. **Scale testing**
   - Deploy high-replica workloads
   - Watch Karpenter scale nodes

4. **Production hardening**
   - Add PodDisruptionBudgets
   - Configure HorizontalPodAutoscalers
   - Set up proper RBAC

5. **Cost optimization**
   - Review which workloads can use ARM64
   - Increase spot instance usage
   - Enable more aggressive consolidation

---

**🚀 You now have a production-ready EKS cluster with Karpenter and multi-architecture support!**

For questions or issues, see the [Troubleshooting](#troubleshooting) section above.
