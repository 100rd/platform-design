# cert-manager - TLS Certificate Management

cert-manager automates TLS certificate management in Kubernetes, including issuing, renewing, and revoking certificates.

## Features

- **Let's Encrypt integration** - Free TLS certificates
- **Wildcard certificates** - Via DNS01 challenge with Route53
- **Auto-renewal** - Certificates renewed automatically before expiry
- **Multiple issuers** - Production, staging, and self-signed
- **Ingress integration** - Automatic certificate provisioning

## Prerequisites

1. **Domain ownership** - You must control the DNS domain
2. **IAM Role** (for DNS01) - Route53 permissions for IRSA/Pod Identity

### IAM Policy for Route53 DNS01

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/*"
    },
    {
      "Effect": "Allow",
      "Action": "route53:ListHostedZonesByName",
      "Resource": "*"
    }
  ]
}
```

## Installation

```bash
# Install with cluster issuers
helm install cert-manager . \
  -n cert-manager \
  --create-namespace \
  --set clusterIssuers.email=admin@example.com \
  --set clusterIssuers.dns01.dnsZones[0]=example.com
```

## Usage

### Request a Certificate via Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: alb
  tls:
    - hosts:
        - app.example.com
      secretName: app-tls
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

### Request a Wildcard Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-example-com
  namespace: default
spec:
  secretName: wildcard-example-com-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "*.example.com"
    - example.com
```

### Self-Signed Certificate (for internal services)

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: internal-service-tls
  namespace: default
spec:
  secretName: internal-service-tls
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
  dnsNames:
    - my-service.internal
  duration: 8760h  # 1 year
  renewBefore: 720h  # 30 days
```

## Available ClusterIssuers

| Name | Type | Use Case |
|------|------|----------|
| `letsencrypt-prod` | ACME | Production certificates |
| `letsencrypt-staging` | ACME | Testing (not trusted by browsers) |
| `selfsigned` | Self-Signed | Internal services |

## Monitoring

```bash
# List all certificates
kubectl get certificates -A

# Check certificate status
kubectl describe certificate my-cert -n my-namespace

# List certificate requests
kubectl get certificaterequests -A

# Check issuer status
kubectl get clusterissuers
```

## Troubleshooting

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager

# Check certificate request events
kubectl describe certificaterequest <name> -n <namespace>

# Check ACME challenge status
kubectl get challenges -A
kubectl describe challenge <name> -n <namespace>

# Debug DNS01 challenge
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager -c cert-manager | grep dns01
```

## Common Issues

1. **Challenge stuck in pending** - Check Route53 permissions or DNS propagation
2. **Rate limited** - Let's Encrypt has rate limits; use staging for testing
3. **Certificate not renewing** - Check logs and ensure issuer is healthy
