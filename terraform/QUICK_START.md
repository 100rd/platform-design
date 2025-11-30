# Karpenter Quick Start Guide

## Prerequisites

- EKS cluster deployed with Karpenter submodule
- Terraform >= 1.3
- kubectl configured
- AWS CLI configured

## Step 1: Deploy Karpenter (Choose One Method)

### Method A: Using Karpenter Module (Recommended)

Add to your `main.tf`:

```hcl
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name                      = module.eks.cluster_name
  cluster_endpoint                  = module.eks.cluster_endpoint
  karpenter_controller_role_arn     = module.eks.karpenter_controller_role_arn
  karpenter_interruption_queue_name = module.eks.karpenter_queue_name
  karpenter_node_iam_role_name      = module.eks.karpenter_node_iam_role_name
}
```

Apply:
```bash
terraform init
terraform apply
```

### Method B: Using Standalone karpenter-helm.tf

The `karpenter-helm.tf` file is already configured. Just run:

```bash
terraform init
terraform apply -target=helm_release.karpenter
```

## Step 2: Render NodePool Templates

```bash
cd kubernetes/karpenter/templates
./render-templates.sh
```

This creates:
- `../x86-nodepool-rendered.yaml`
- `../arm64-nodepool-rendered.yaml`

## Step 3: Apply NodePools

```bash
kubectl apply -f ../x86-nodepool-rendered.yaml
kubectl apply -f ../arm64-nodepool-rendered.yaml
```

## Step 4: Verify Installation

```bash
# Check Karpenter pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter

# Check NodePools
kubectl get nodepool
kubectl get ec2nodeclass

# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```

## Step 5: Test Autoscaling

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
spec:
  replicas: 5
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      nodeSelector:
        karpenter.sh/nodepool: x86-general-purpose
      containers:
      - name: pause
        image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        resources:
          requests:
            cpu: 1
            memory: 1Gi
EOF

# Watch nodes
kubectl get nodes -w
```

## Common Commands

```bash
# Get Terraform outputs
terraform output karpenter_node_iam_role_name
terraform output cluster_name

# Render templates manually
export node_role_name=$(terraform output -raw karpenter_node_iam_role_name)
export cluster_name=$(terraform output -raw cluster_name)
export region=$(terraform output -raw region)
envsubst < templates/x86-nodepool.yaml.tpl > x86-nodepool-rendered.yaml

# Check Karpenter status
kubectl get deployment karpenter -n kube-system
kubectl describe deployment karpenter -n kube-system

# View NodePool details
kubectl describe nodepool x86-general-purpose
kubectl describe ec2nodeclass x86-general-purpose

# Debug node provisioning
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100
```

## Troubleshooting

### Pods not scheduling?

```bash
# Check Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter

# Verify IAM role matches
kubectl get ec2nodeclass x86-general-purpose -o yaml | grep role:
terraform output karpenter_node_iam_role_name
```

### No nodes launching?

```bash
# Verify discovery tags
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=$(terraform output -raw cluster_name)"
```

### Template variables not replaced?

```bash
# Re-render templates
cd kubernetes/karpenter/templates
./render-templates.sh
```

## File Locations

- Terraform module: `terraform/modules/karpenter/`
- NodePool templates: `kubernetes/karpenter/templates/`
- Rendered manifests: `kubernetes/karpenter/*-rendered.yaml`
- Documentation: `KARPENTER_IMPLEMENTATION.md`

## Next Steps

1. Customize NodePools for your workloads
2. Set up monitoring and alerts
3. Configure cost allocation tags
4. Implement backup/restore procedures
5. Document runbooks for your team

For detailed documentation, see `KARPENTER_IMPLEMENTATION.md`.
