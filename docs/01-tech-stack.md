# Tech Stack

This document outlines the technologies used for the casino platform. The solution blends AWS services with bare metal nodes to host blockchain components and provides a Kubernetes-based runtime for workloads written primarily in Go.

## Infrastructure & DevOps

- **AWS** – EKS for Kubernetes clusters, EC2 for compute, RDS for managed PostgreSQL, S3 for object storage, and CloudWatch for logging and metrics.
- **Bare Metal Servers** – dedicated nodes for running internal blockchain and high-performance workloads.
- **Kubernetes** – cluster orchestration using Helm charts and Kustomize overlays.
- **Terraform** – IaC for provisioning cloud and on-prem resources.
- **ArgoCD** – GitOps deployment management for Kubernetes manifests.
- **Cloudflare** – DNS management, CDN, and edge security.
- **GitHub Actions** – CI/CD pipelines.
- **Docker** – container packaging for services.
- **Helm** – package manager for Kubernetes applications.
- **Kustomize** – configuration overlays for various environments.

Additional tools include Prometheus and Grafana for observability, Loki for log aggregation, External Secrets Operator (ESO) for secrets management, and ingress/gateway management via Cilium Gateway API / Envoy Gateway.

## Data Stores

- **PostgreSQL** – primary relational store.
- **MongoDB** – document database for flexible schemas.
- **Kafka** – message streaming and event distribution.
- **Redis** – in-memory caching and ephemeral data.

## Languages & Frameworks

- **Golang** – main language for backend services and blockchain modules.
- **Node.js** – used for supporting tooling or lightweight web frontends.
- **Swagger/OpenAPI** – API documentation and client generation.

This stack is designed to support a modern cloud-native casino platform with the scalability and reliability required for gaming workloads while integrating a private blockchain for internal transactions.
