# AWS Load Balancer Controller

AWS Load Balancer Controller manages AWS Elastic Load Balancers (ALB/NLB) for Kubernetes clusters.

## Features

- **Application Load Balancer (ALB)** for HTTP/HTTPS ingress
- **Network Load Balancer (NLB)** for TCP/UDP services
- **WAF and Shield integration** for DDoS protection
- **Target Group binding** for direct pod targeting
- **TLS termination** at the load balancer

## Prerequisites

1. **EKS Cluster** with OIDC provider enabled
2. **IAM Role** with AWS Load Balancer Controller policy
3. **Pod Identity** or IRSA configured

### IAM Policy

Create IAM policy using the official policy document:

```bash
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json
```

## Installation

```bash
# Add Helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install with required values
helm install aws-load-balancer-controller . \
  -n kube-system \
  --set clusterName=your-cluster-name \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::ACCOUNT:role/AmazonEKSLoadBalancerControllerRole
```

## Usage

### ALB Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
spec:
  ingressClassName: alb
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

### NLB Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
spec:
  type: LoadBalancer
  ports:
    - port: 443
      targetPort: 8443
  selector:
    app: my-app
```

## Monitoring

ServiceMonitor is enabled by default for Prometheus scraping.

Metrics available at `/metrics` endpoint:
- `aws_alb_controller_*` - Controller metrics
- `aws_alb_*` - Load balancer metrics

## Troubleshooting

```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check target group binding status
kubectl get targetgroupbindings -A

# Describe ingress for events
kubectl describe ingress my-app
```
