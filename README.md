# Platform Design

This repository contains documentation and reference configurations for a casino platform that runs on Kubernetes across AWS and bare metal servers. The platform uses a private blockchain alongside traditional microservices. The goal is to provide a repeatable approach to building, deploying, and maintaining applications using the AWS Well-Architected Framework.

## Core Technologies

### Infrastructure & DevOps
- AWS (EKS, EC2, RDS, S3, CloudWatch)
- Bare metal servers for blockchain nodes
- Kubernetes (Helm, Kustomize)
- Terraform
- ArgoCD
- Cloudflare (DNS, CDN, WAF)
- GitHub Actions (CI/CD)

### Backend and API
- Golang (microservices and blockchain services)
- Node.js (optional frontend or tooling)
- Swagger/OpenAPI (API documentation)

### Data Stores
- PostgreSQL (relational data)
- MongoDB (document data)
- Kafka (stream processing)
- Redis (caching)

## Additional Tools
- Prometheus & Grafana for metrics
- Loki or Elasticsearch for logs
- Vault for secrets management
- Optional service mesh (Istio or Linkerd)

## Structure

- `docs/` – platform documentation
- `services/example-api/` – simple API in Go with healthcheck
- `apps/` – Helm charts for applications deployed via ArgoCD. Infrastructure
  components such as the External Secrets Operator reside under `apps/infra/`.
- `apps/` – Helm charts for applications deployed via ArgoCD
- `terraform/`, `helm/`, `kustomize/`, `argocd/` – infrastructure and deployment files
- `terragrunt/` – Terragrunt configuration linking Terraform modules
- `helm/app/` – generic Helm chart for deploying applications with ingress and external secrets
- `argocd/applicationset.yaml` – example ApplicationSet manifest for ArgoCD

## Getting Started

```bash
cd services/example-api
docker build -t example-api .
docker run -p 8080:8080 example-api
```

See `docs/platform-overview.md` for an architectural overview of the system.
See `docs/02-terragrunt-strategy.md` for the Terragrunt proposal.
