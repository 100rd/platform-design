# Standard Specification: GitOps Platform (SPEC-GITOPS-ARGOCD)

- **ID:** `SPEC-GITOPS-ARGOCD`
- **Name:** GitOps Platform
- **Status:** **Ready**
- **Dependencies:** `SPEC-K8S-EKS`

---

## 1. Purpose

This specification describes the standard for the GitOps & Continuous Delivery (CD) platform component. It defines the fully automated, declarative process for deploying and managing the lifecycle of applications and platform services within Kubernetes, based on the state of a Git repository.

## 2. Technologies

| Technology | Purpose |
| :--- | :--- |
| **ArgoCD** | The core of the GitOps process. It continuously monitors the Git repository and reconciles the live state of the cluster to match the desired state. |
| **ArgoCD ApplicationSet**| The primary tool for managing applications at scale in a multi-cluster, multi-environment setup. |
| **Kustomize**| Used for templating, customizing, and patching Kubernetes manifests for different environments. |
| **Helm** | Used for packaging and deploying applications. |
| **Kargo** | Used for progressive delivery and orchestrating release promotions between environments. |

## 3. Architecture: App of Apps with ApplicationSets

The process is built around ArgoCD and its ApplicationSet controller, which automates the management of hundreds of applications.

### 3.1. Directory Structure

- `argocd/`: The root directory for all GitOps-related configurations.
    - `argocd/bootstrap/`: Contains the configuration to bootstrap ArgoCD itself and its core components. The **`root-app.yaml`** file implements the "App of Apps" pattern, triggering the installation of the entire in-cluster platform.
    - `argocd/applicationset-*.yaml`: Defines the rules for deploying various application groups (shared infrastructure, multi-cluster workloads, etc.).
    - `argocd/cluster-envs/`: Kustomize configurations for different cluster types (`prod`, `dev`, etc.).
    - `argocd/bootstrap/cluster-secrets/`: Templates for creating the secrets required to connect to target Kubernetes clusters.
- `helm/`: Contains reusable Helm charts.
- `envs/`: Contains environment-specific `values.yaml` files, which provide the configuration for Helm charts.

### 3.2. Key Patterns

- **App of Apps:** The platform is bootstrapped via a single root ArgoCD application (`root-app.yaml`). This app, in turn, deploys the `ApplicationSet` resources, which then manage the final applications.
- **ApplicationSet Matrix Generator:** This is the heart of the automation. As seen in `applicationset-multicluster.yaml`, a `matrix` generator is used to create applications at the intersection of two dimensions:
    1.  A list of applications/teams (e.g., `mono`, `chains`).
    2.  A list of target clusters, selected by labels (e.g., `env: staging`).
- **Controlled Rollout (`RollingSync`):** For multi-cluster `ApplicationSet`s, a `RollingSync` strategy is used to deploy changes sequentially across regions (e.g., `eu-west-1` first, then `eu-central-1`), reducing the blast radius of a failed deployment.
- **Kargo Integration:** Applications include the `kargo.akuity.io/authorized-stage` annotation, linking them to a Kargo "Stage". This enables Kargo to manage the promotion of new application versions (e.g., from `staging` to `prod`).

## 4. Deployment Sequence

ArgoCD is deployed into a management cluster after the EKS cluster itself is ready.

```mermaid
graph TD;
    A[EKS Cluster Ready<br/>(from SPEC-K8S-EKS)] --> B[1. <b>Deploy ArgoCD Controller</b><br/>Apply Terraform module for ArgoCD];
    B --> C[2. <b>Deploy Root Application</b><br/>Apply `argocd/bootstrap/root-app.yaml`];
    C --> D[3. <b>Root App Deploys ApplicationSets</b><br/>ArgoCD reconciles its own configuration];
    D --> E[4. <b>ApplicationSets Deploy All Other Apps</b><br/>Observability, Security, and Business applications are deployed];
    E --> F{Fully configured cluster};
```

### Sequence Description:

1.  **Deploy ArgoCD Controller:** Once the EKS cluster is operational, the ArgoCD controller is installed into it, typically via a dedicated Terraform or Helm module.
2.  **Deploy Root Application:** The single `root-app.yaml` manifest is applied to the cluster. This application points to the `argocd/bootstrap` directory in the Git repository.
3.  **Bootstrap Reconciliation:** ArgoCD syncs the `root-app`, which deploys all the `ApplicationSet` resources.
4.  **Platform Reconciliation:** The `ApplicationSet` controllers take over, generating and deploying all other platform services (monitoring, security) and business applications according to their definitions. This brings the cluster to its fully-desired state.
