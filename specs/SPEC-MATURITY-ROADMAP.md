# Standard Specification: Platform Maturity Roadmap (SPEC-MATURITY-ROADMAP)

- **ID:** `SPEC-MATURITY-ROADMAP`
- **Name:** Platform Maturity Roadmap
- **Status:** **Proposed**
- **Dependencies:** All foundational specs (`SPEC-K8S-EKS`, `SPEC-GITOPS-ARGOCD`, etc.)

---

## 1. Purpose

This document outlines a series of proposed enhancements to evolve the current powerful platform into a truly self-service, secure, and easily adoptable internal product. The goal is to improve developer experience (DevEx), strengthen governance, and increase operational excellence, making it easier to roll out the platform to new projects.

## 2. Proposed Enhancements by Theme

### 2.1. Developer Experience (DevEx)

*Reduce cognitive load and accelerate developer onboarding.*

| Proposal | Problem Statement | Proposed Solution |
| :--- | :--- | :--- |
| **Developer Portal** | Developers lack a central entry point to view their services, documentation, and operational status. Information is scattered across ArgoCD, Grafana, and GitHub. | Implement **Backstage.io** as the platform's "single pane of glass" for developers. Key features: <br>- **Software Catalog:** A central registry for all microservices, showing owners, CI/CD status, and links. <br>- **TechDocs:** Automatically render documentation from Markdown files in Git repos. |
| **Service Scaffolding** | Onboarding a new service requires significant manual effort: creating repos, CI files, and Helm charts, which is slow and error-prone. | Implement **Backstage Software Templates**. This will allow developers to scaffold a new, production-ready service with one click, generating: <br>- A standardized repository structure. <br>- A pre-configured `Dockerfile`. <br>- A reusable Helm chart. <br>- A complete CI/CD pipeline. |
| **Standardized Local Dev**| Local development environments are inconsistent across developers, leading to "it works on my machine" issues and slowing down onboarding. | Introduce **Dev Containers** (`devcontainer.json`). This allows developers to open the project in a containerized environment with all necessary tools (kubectl, helm, terraform) pre-installed and configured, ensuring consistency with CI and production. |

### 2.2. Governance & FinOps

*Make the platform not just powerful, but also secure and cost-transparent by default.*

| Proposal | Problem Statement | Proposed Solution |
| :--- | :--- | :--- |
| **Proactive Policy Enforcement** | Security is checked in CI (`checkov`), but nothing prevents a non-compliant or misconfigured resource from being deployed directly to the cluster. | Implement **Kyverno** as an admission controller in all EKS clusters. This enables proactive policy enforcement, such as: <br>- *Denying* pods running as root. <br>- *Requiring* all Deployments to have `owner` and `cost-center` labels. <br>- *Preventing* the creation of public `LoadBalancer` services in non-approved namespaces. |
| **Automated Cost Anomaly Detection** | Cost analysis is done at PR time (`infracost`), but there is no continuous monitoring for cost spikes in the running infrastructure. | Integrate **OpenCost** (a CNCF project) with the existing Prometheus stack. Create alerts in Grafana that trigger on sudden cost increases for a specific namespace or application, enabling proactive FinOps. |

### 2.3. Supply Chain Security

*Guarantee that only trusted and verified artifacts run in production.*

| Proposal | Problem Statement | Proposed Solution |
| :--- | :--- | :--- |
| **Image Signature Enforcement**| The CI pipeline signs container images (`cosign-sign`), but nothing in the cluster *enforces* that only signed images are allowed to run. | Use **Kyverno** to create an admission policy that verifies the Cosign signature of every image before a pod is scheduled. If the signature is missing or invalid, the pod is rejected. This closes the loop on supply chain security. |

### 2.4. Operational Excellence

*Simplify the bootstrap process and increase confidence in the platform's resilience.*

| Proposal | Problem Statement | Proposed Solution |
| :--- | :--- | :--- |
| **Platform Bootstrap CLI**| The initial setup (creating state buckets, applying `_org` and `network` stacks) requires several manual Terragrunt commands and variable passing. | Create a simple CLI wrapper (e.g., a `bash` or `Go` tool called `platform-cli`) to encapsulate this logic. A single command like `platform-cli bootstrap --project-name new-proj` would execute all necessary steps in the correct order. |
| **Automated DR Drills**| The DR plan is well-documented but is not tested automatically, leading to potential configuration drift and failed recoveries. | Integrate **LitmusChaos** into the staging environment. Create a recurring Chaos Experiment that automatically simulates failures (e.g., deletes a Loki pod, drops network traffic to Prometheus) and validates that the system recovers and alerts as expected. |

## 4. Phased Rollout Plan

```mermaid
graph TD;
    A(Start);

    subgraph Phase 1 - Foundational Governance & Visibility
        B[<b>Developer Portal</b><br/>(Backstage Catalog & TechDocs)];
        C[<b>Proactive Policies</b><br/>(Kyverno Installation & Basic Policies)];
    end

    subgraph Phase 2 - Developer Enablement & Hardening
        D[<b>Service Scaffolding</b><br/>(Backstage Software Templates)];
        E[<b>Image Signature Enforcement</b><br/>(Kyverno Cosign Policy)];
        F[<b>Standardized Local Dev</b><br/>(Dev Containers)];
    end

    subgraph Phase 3 - Advanced Automation & FinOps
        G[<b>Cost Anomaly Detection</b><br/>(OpenCost Integration)];
        H[<b>Automated DR Drills</b><br/>(LitmusChaos)];
        I[<b>Bootstrap CLI</b><br/>(platform-cli)];
    end

    A --> B;
    A --> C;
    B --> D;
    C --> E;
    D --> F;
    E --> G;
    F --> I;
    G --> H;
```
