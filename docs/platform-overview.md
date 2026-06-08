# Platform Overview

This document provides a high-level design for the casino platform, covering build, deployment, and maintenance practices. The architecture combines AWS cloud resources with dedicated bare metal servers for blockchain nodes. Kubernetes serves as the uniform runtime across environments.

## Architecture Highlights

1. **Multi-Environment Setup**
   - AWS hosts the majority of application workloads using EKS.
   - Bare metal servers run critical blockchain components and latency-sensitive services.

2. **Containerized Services**
   - All applications are built as Docker images.
   - Helm charts define service deployments while Kustomize supplies environment-specific overlays.

3. **GitOps Pipeline**
   - Infrastructure defined in Terraform and stored in Git.
   - ArgoCD watches the repository and applies Kubernetes manifests automatically.
   - GitHub Actions manage the CI pipeline, running tests and building container images.

4. **Observability and Security**
   - Metrics gathered via Prometheus with dashboards in Grafana.
   - Logs centralized through Grafana Loki.
   - External Secrets Operator (ESO) handles secrets management and Cloudflare protects external endpoints.

5. **Blockchain Integration**
   - Internal crypto nodes run on dedicated hardware for performance.
   - Services interact with the blockchain via gRPC APIs written in Go.

## AWS Well-Architected Considerations

The design aligns with the [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/). Each pillar—operational excellence, security, reliability, performance efficiency, and cost optimization—is used to review the platform regularly.

## Maintenance

- Use Terraform state locking and versioned modules for infrastructure consistency.
- Employ rolling updates and health checks within Kubernetes to ensure minimal downtime.
- Monitor cloud costs and optimize resource usage as part of the Well-Architected reviews.

This overview serves as a starting point for implementing a resilient casino platform with integrated blockchain technology.
