# Karpenter Terraform Module

This module deploys Karpenter to an existing EKS cluster using Helm. It provides a reusable, configurable way to install Karpenter across different environments.

## Features

- Installs Karpenter via Helm chart from OCI registry
- Automatically manages CRDs via Helm
- Supports EKS Pod Identity (v21+)
- Configurable high availability (default 2 replicas)
- Pod Disruption Budget support
- Flexible resource configuration
- Customizable tolerations and node selectors

## Prerequisites

1. EKS cluster deployed with:
   - EKS v1.29+ recommended
   - Pod Identity Agent addon enabled
   - Karpenter submodule from terraform-aws-modules/eks/aws
2. VPC subnets tagged with `karpenter.sh/discovery: <cluster-name>`
3. Security groups tagged with `karpenter.sh/discovery: <cluster-name>`
4. Helm and Kubernetes providers configured

## Usage

### Basic Usage

```hcl
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name                        = module.eks.cluster_name
  cluster_endpoint                    = module.eks.cluster_endpoint
  karpenter_version                   = "1.1.1"
  karpenter_controller_role_arn       = module.eks.karpenter_controller_role_arn
  karpenter_interruption_queue_name   = module.eks.karpenter_queue_name
  karpenter_node_iam_role_name        = module.eks.karpenter_node_iam_role_name
}
```

### Advanced Usage with Custom Configuration

```hcl
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name                        = module.eks.cluster_name
  cluster_endpoint                    = module.eks.cluster_endpoint
  karpenter_version                   = "1.1.1"
  karpenter_controller_role_arn       = module.eks.karpenter_controller_role_arn
  karpenter_interruption_queue_name   = module.eks.karpenter_queue_name
  karpenter_node_iam_role_name        = module.eks.karpenter_node_iam_role_name

  # High availability configuration
  controller_replicas = 3
  pdb_min_available   = 2

  # Custom resource allocation
  controller_resources = {
    requests = {
      cpu    = "1000m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2000m"
      memory = "2Gi"
    }
  }

  # Debug logging
  log_level = "debug"

  # Custom tolerations
  tolerations = [
    {
      key      = "CriticalAddonsOnly"
      operator = "Exists"
      effect   = "NoSchedule"
      value    = null
    },
    {
      key      = "dedicated"
      operator = "Equal"
      effect   = "NoSchedule"
      value    = "karpenter"
    }
  ]

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

### Complete Example with EKS Integration

```hcl
# Deploy EKS cluster with Karpenter submodule
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.8.0"

  cluster_name    = "my-cluster"
  cluster_version = "1.32"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  # Managed node group for Karpenter controller
  eks_managed_node_groups = {
    karpenter = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      labels = {
        "karpenter.sh/controller" = "true"
      }

      taints = [{
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }
}

# Karpenter submodule (creates IAM roles and SQS queue)
module "karpenter_infra" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.8.0"

  cluster_name = module.eks.cluster_name

  enable_pod_identity             = true
  create_pod_identity_association = true
  create_node_iam_role            = true
  enable_spot_termination         = true
}

# Karpenter Helm installation
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name                        = module.eks.cluster_name
  cluster_endpoint                    = module.eks.cluster_endpoint
  karpenter_controller_role_arn       = module.karpenter_infra.controller_role_arn
  karpenter_interruption_queue_name   = module.karpenter_infra.queue_name
  karpenter_node_iam_role_name        = module.karpenter_infra.node_iam_role_name

  depends_on = [module.eks]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | EKS cluster name | `string` | n/a | yes |
| cluster_endpoint | EKS cluster API endpoint | `string` | n/a | yes |
| karpenter_controller_role_arn | IAM role ARN for Karpenter controller | `string` | n/a | yes |
| karpenter_interruption_queue_name | SQS queue name for interruption handling | `string` | n/a | yes |
| karpenter_node_iam_role_name | IAM role name for Karpenter nodes | `string` | n/a | yes |
| karpenter_version | Karpenter Helm chart version | `string` | `"1.1.1"` | no |
| namespace | Kubernetes namespace | `string` | `"kube-system"` | no |
| controller_replicas | Number of replicas | `number` | `2` | no |
| controller_resources | Resource requests/limits | `object` | See variables.tf | no |
| log_level | Log level (debug, info, warn, error) | `string` | `"info"` | no |
| enable_pod_disruption_budget | Enable PDB | `bool` | `true` | no |
| pdb_min_available | Minimum available pods | `number` | `1` | no |
| node_selector | Node selector for controller | `map(string)` | See variables.tf | no |
| tolerations | Tolerations for controller | `list(object)` | See variables.tf | no |

## Outputs

| Name | Description |
|------|-------------|
| release_name | Helm release name |
| release_version | Installed chart version |
| namespace | Installation namespace |
| status | Helm release status |
| node_iam_role_name | IAM role name for nodes |
| controller_role_arn | Controller IAM role ARN |
| interruption_queue_name | SQS queue name |
| cluster_name | EKS cluster name |

## Post-Installation Steps

1. **Verify Installation**
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
   kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
   ```

2. **Create NodePools**

   Apply NodePool and EC2NodeClass manifests:
   ```bash
   # Use templated versions with Terraform outputs
   terraform output -json > outputs.json

   # Apply NodePools
   kubectl apply -f kubernetes/karpenter/
   ```

3. **Test Autoscaling**
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: inflate
   spec:
     replicas: 0
     selector:
       matchLabels:
         app: inflate
     template:
       metadata:
         labels:
           app: inflate
       spec:
         nodeSelector:
           karpenter.sh/nodepool: x86-general-purpose
         containers:
         - name: inflate
           image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
           resources:
             requests:
               cpu: 1
   EOF

   # Scale up
   kubectl scale deployment inflate --replicas=10

   # Watch nodes
   kubectl get nodes -w
   ```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    EKS Cluster                      │
│                                                     │
│  ┌───────────────────────────────────────────┐    │
│  │         Karpenter Controller              │    │
│  │  (2 replicas on dedicated node group)     │    │
│  │                                            │    │
│  │  - Watches for unschedulable pods          │    │
│  │  - Provisions nodes via EC2 API            │    │
│  │  - Handles spot interruptions              │    │
│  │  - Consolidates underutilized nodes        │    │
│  └───────────────────────────────────────────┘    │
│                        │                            │
│                        ▼                            │
│  ┌───────────────────────────────────────────┐    │
│  │          NodePools & NodeClasses          │    │
│  │                                            │    │
│  │  - x86 General Purpose                     │    │
│  │  - ARM64 Graviton (cost-optimized)         │    │
│  │  - GPU instances (if needed)               │    │
│  └───────────────────────────────────────────┘    │
│                        │                            │
│                        ▼                            │
│  ┌───────────────────────────────────────────┐    │
│  │      Application Workloads                │    │
│  │  (Auto-scaled by Karpenter)               │    │
│  └───────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

## Troubleshooting

### Pods Not Scheduling

1. Check Karpenter logs:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter
   ```

2. Verify NodePool and EC2NodeClass:
   ```bash
   kubectl get nodepool
   kubectl get ec2nodeclass
   kubectl describe nodepool <name>
   ```

3. Check IAM permissions:
   ```bash
   kubectl get sa karpenter -n kube-system -o yaml
   ```

### Nodes Not Launching

1. Verify subnet/SG tags:
   ```bash
   aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=<cluster-name>"
   aws ec2 describe-security-groups --filters "Name=tag:karpenter.sh/discovery,Values=<cluster-name>"
   ```

2. Check instance profile:
   ```bash
   aws iam get-instance-profile --instance-profile-name <role-name>
   ```

## Contributing

For issues or improvements, please submit a PR or issue in the repository.

## License

This module follows the same license as the parent project.
