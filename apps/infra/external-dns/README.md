# ExternalDNS

Automatically synchronize Kubernetes Ingress/Service resources with DNS providers.

## Overview

ExternalDNS watches Kubernetes resources (Services, Ingresses, etc.) and automatically creates/updates/deletes DNS records in your DNS provider (Route53, CloudFlare, etc.).

## Status

**Disabled by default.** Enable by setting `external-dns.enabled: true` in values.yaml.

## Prerequisites

1. **DNS Hosted Zone**: A hosted zone in Route53 (or other provider)
2. **IAM Permissions**: IAM role with Route53 access (via IRSA or Pod Identity)
3. **Domain Filters**: Configure which domains ExternalDNS should manage

## Quick Start

### 1. Create IAM Role (Terraform)

```hcl
module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-external-dns"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/Z1234567890ABC"]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-dns:external-dns"]
    }
  }
}
```

### 2. Enable and Configure

```yaml
# values.yaml
external-dns:
  enabled: true

  domainFilters:
    - example.com
    - api.example.com

  aws:
    region: eu-central-1

  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-cluster-external-dns
```

### 3. Annotate Your Services/Ingresses

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    external-dns.alpha.kubernetes.io/hostname: app.example.com
    external-dns.alpha.kubernetes.io/ttl: "300"
spec:
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

## How It Works

```
+-------------+     +---------------+     +-----------+
|  Ingress/   | --> | ExternalDNS   | --> |  Route53  |
|  Service    |     | Controller    |     |  (DNS)    |
+-------------+     +---------------+     +-----------+
      |                    |
      |  Watches for       |  Creates/updates
      |  annotations       |  DNS records
      v                    v
  hostname: app.example.com  ->  A/ALIAS record
```

## Supported Sources

| Source | Description |
|--------|-------------|
| `service` | LoadBalancer services |
| `ingress` | Ingress resources |
| `istio-gateway` | Istio Gateway resources |
| `contour-httpproxy` | Contour HTTPProxy |
| `crd` | Custom DNSEndpoint resources |

## Common Annotations

| Annotation | Description |
|------------|-------------|
| `external-dns.alpha.kubernetes.io/hostname` | DNS hostname to create |
| `external-dns.alpha.kubernetes.io/ttl` | TTL in seconds |
| `external-dns.alpha.kubernetes.io/target` | Override target (IP or hostname) |
| `external-dns.alpha.kubernetes.io/alias` | Create ALIAS record (AWS only) |

## Sync Policies

| Policy | Behavior |
|--------|----------|
| `sync` | Full sync - creates, updates, and deletes records |
| `upsert-only` | Only creates and updates, never deletes (safer) |

**Default: `upsert-only`** - safer for initial deployment.

## Ownership & TXT Records

ExternalDNS uses TXT records to track ownership:
- Prefix: `_externaldns.` (configurable)
- Owner ID: Identifies which cluster owns the record

This prevents conflicts when multiple clusters manage the same zone.

## Monitoring

ExternalDNS exposes Prometheus metrics:

- `external_dns_source_endpoints` - Number of endpoints from sources
- `external_dns_registry_endpoints` - Number of endpoints in registry
- `external_dns_controller_last_sync_timestamp` - Last successful sync

## Troubleshooting

```bash
# Check logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Check current endpoints
kubectl get endpoints -A

# Verify DNS records in Route53
aws route53 list-resource-record-sets --hosted-zone-id Z1234567890ABC
```

## Resources

- [Documentation](https://kubernetes-sigs.github.io/external-dns/)
- [Helm Chart](https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns)
- [Tutorials](https://kubernetes-sigs.github.io/external-dns/latest/tutorials/)
