# Karpenter NodePool Templates

This directory contains Terraform-templated versions of Karpenter NodePool and EC2NodeClass manifests.

## Overview

The templates use variables that are dynamically populated from Terraform outputs, ensuring consistency between infrastructure and Kubernetes resources.

## Template Variables

The following variables are injected from Terraform outputs:

- `${node_role_name}` - IAM role name for Karpenter nodes
- `${cluster_name}` - EKS cluster name for discovery tags
- `${region}` - AWS region for availability zones
- `${cluster_endpoint}` - EKS API endpoint (if needed)
- `${vpc_id}` - VPC ID (if needed)

## Usage

### Method 1: Using Terraform templatefile()

Add this to your Terraform configuration:

```hcl
# Render x86 NodePool
resource "local_file" "x86_nodepool" {
  content = templatefile("${path.module}/kubernetes/karpenter/templates/x86-nodepool.yaml.tpl", {
    node_role_name   = module.eks.karpenter_node_iam_role_name
    cluster_name     = var.cluster_name
    region           = var.region
    cluster_endpoint = module.eks.cluster_endpoint
    vpc_id           = module.vpc.vpc_id
  })
  filename = "${path.module}/kubernetes/karpenter/x86-nodepool-rendered.yaml"
}

# Render ARM64 NodePool
resource "local_file" "arm64_nodepool" {
  content = templatefile("${path.module}/kubernetes/karpenter/templates/arm64-nodepool.yaml.tpl", {
    node_role_name   = module.eks.karpenter_node_iam_role_name
    cluster_name     = var.cluster_name
    region           = var.region
    cluster_endpoint = module.eks.cluster_endpoint
    vpc_id           = module.vpc.vpc_id
  })
  filename = "${path.module}/kubernetes/karpenter/arm64-nodepool-rendered.yaml"
}

# Apply with kubectl
resource "null_resource" "apply_nodepools" {
  depends_on = [
    module.karpenter,
    local_file.x86_nodepool,
    local_file.arm64_nodepool
  ]

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f ${path.module}/kubernetes/karpenter/x86-nodepool-rendered.yaml
      kubectl apply -f ${path.module}/kubernetes/karpenter/arm64-nodepool-rendered.yaml
    EOT
  }
}
```

### Method 2: Using Shell Script (Manual)

Use the provided `render-templates.sh` script:

```bash
cd kubernetes/karpenter/templates
./render-templates.sh
```

This will:
1. Get Terraform outputs
2. Render templates with actual values
3. Output ready-to-apply manifests

### Method 3: Using envsubst (Quick & Manual)

```bash
# Export Terraform outputs as environment variables
export node_role_name=$(terraform output -raw karpenter_node_iam_role_name)
export cluster_name=$(terraform output -raw cluster_name)
export region=$(terraform output -raw region)

# Render templates
envsubst < templates/x86-nodepool.yaml.tpl > x86-nodepool-rendered.yaml
envsubst < templates/arm64-nodepool.yaml.tpl > arm64-nodepool-rendered.yaml

# Apply to cluster
kubectl apply -f x86-nodepool-rendered.yaml
kubectl apply -f arm64-nodepool-rendered.yaml
```

### Method 4: Using Terraform kubernetes_manifest (Recommended)

The cleanest approach - Terraform manages everything:

```hcl
# Render and apply x86 NodePool
resource "kubernetes_manifest" "x86_nodeclass" {
  manifest = yamldecode(templatefile("${path.module}/kubernetes/karpenter/templates/x86-nodepool.yaml.tpl", {
    node_role_name   = module.eks.karpenter_node_iam_role_name
    cluster_name     = var.cluster_name
    region           = var.region
    cluster_endpoint = module.eks.cluster_endpoint
    vpc_id           = module.vpc.vpc_id
  }))

  depends_on = [module.karpenter]
}

# Render and apply ARM64 NodePool
resource "kubernetes_manifest" "arm64_nodeclass" {
  manifest = yamldecode(templatefile("${path.module}/kubernetes/karpenter/templates/arm64-nodepool.yaml.tpl", {
    node_role_name   = module.eks.karpenter_node_iam_role_name
    cluster_name     = var.cluster_name
    region           = var.region
    cluster_endpoint = module.eks.cluster_endpoint
    vpc_id           = module.vpc.vpc_id
  }))

  depends_on = [module.karpenter]
}
```

## Verification

After applying the NodePools:

```bash
# Verify NodeClasses
kubectl get ec2nodeclass
kubectl describe ec2nodeclass x86-general-purpose
kubectl describe ec2nodeclass arm64-graviton

# Verify NodePools
kubectl get nodepool
kubectl describe nodepool x86-general-purpose
kubectl describe nodepool arm64-graviton

# Check Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```

## Testing Autoscaling

Test x86 nodes:

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-x86
spec:
  replicas: 5
  selector:
    matchLabels:
      app: inflate-x86
  template:
    metadata:
      labels:
        app: inflate-x86
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
        karpenter.sh/nodepool: x86-general-purpose
      containers:
      - name: inflate
        image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        resources:
          requests:
            cpu: 1
            memory: 1Gi
EOF

# Watch nodes being created
kubectl get nodes -w
```

Test ARM64 nodes:

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-arm64
spec:
  replicas: 5
  selector:
    matchLabels:
      app: inflate-arm64
  template:
    metadata:
      labels:
        app: inflate-arm64
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
        karpenter.sh/nodepool: arm64-graviton
      containers:
      - name: inflate
        image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        resources:
          requests:
            cpu: 1
            memory: 1Gi
EOF
```

## Customization

To customize NodePools:

1. Copy the template file
2. Modify instance types, limits, or requirements
3. Render with your values
4. Apply to cluster

Example custom NodePool:

```yaml
# GPU NodePool template
- key: karpenter.k8s.aws/instance-family
  operator: In
  values: ["p3", "p4", "g4dn", "g5"]

# High-memory workloads
- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["r"]
```

## Troubleshooting

If nodes aren't launching:

1. Check IAM role name matches:
   ```bash
   terraform output karpenter_node_iam_role_name
   kubectl get ec2nodeclass x86-general-purpose -o yaml | grep role:
   ```

2. Verify discovery tags on subnets/SGs:
   ```bash
   aws ec2 describe-subnets \
     --filters "Name=tag:karpenter.sh/discovery,Values=$(terraform output -raw cluster_name)" \
     --query 'Subnets[*].[SubnetId,Tags]'
   ```

3. Check Karpenter controller logs:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100
   ```

## Best Practices

1. Always use templates for consistency
2. Version control rendered manifests in Git
3. Test in dev environment first
4. Monitor costs with AWS Cost Explorer
5. Use spot instances for non-critical workloads
6. Set appropriate resource limits
7. Enable consolidation for cost optimization
