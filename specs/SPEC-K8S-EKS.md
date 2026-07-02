# Standard Specification: EKS Cluster (SPEC-K8S-EKS)

- **ID:** `SPEC-K8S-EKS`
- **Name:** EKS Cluster Standard
- **Status:** **Ready**
- **Dependencies:** `SPEC-NETWORKING-AWS`

---

## 1. Purpose

This specification describes the standard for deploying, configuring, and componentizing a Kubernetes cluster based on Amazon EKS. This cluster serves as the foundational runtime for the entire application platform.

## 2. Components & Versions

| Component | Tool/Implementation | Version | Description |
| :--- | :--- | :--- | :--- |
| **Orchestrator** | **Amazon EKS** | `1.34` | The managed Kubernetes service from AWS. |
| **EKS IaC Module**| `terraform-aws-modules/eks/aws`| `21.15.1` | The public Terraform module used to manage the EKS cluster. |
| **Network Plugin (CNI)**| **Cilium** | `1.16.5` (Helm) | Provides networking, security (NetworkPolicy), observability, and service mesh capabilities. |
| **Node Autoscaling**| **Karpenter** | `1.8.1` (Helm) | Provides just-in-time, right-sized node autoscaling. |
| **Node OS** | Bottlerocket | - | A minimal, container-optimized OS from AWS for hosting nodes. |
| **Authentication**| IAM Access Entries | - | The native EKS mechanism for mapping IAM principals to Kubernetes groups. |

## 3. Architecture & Configuration

### 3.1. Deployment via IaC

The cluster and all its core components are deployed via Terraform and Terragrunt.

- **Root Module:** `terraform/modules/eks-cluster`, which acts as a wrapper around the public `terraform-aws-modules/eks/aws` module.
- **Configuration:** Shared configuration for all environments is centralized in `terragrunt/_envcommon/eks.hcl`. This file defines the Kubernetes version, logging settings, and other common parameters.

### 3.2. Key Configuration Aspects

- **API Security:** The cluster API server is private by default (`endpoint_private_access = true`), with no public ingress.
- **Secret Encryption:** Kubernetes secrets are encrypted at rest using a dedicated AWS KMS key.
- **Control Plane Logging:** All control plane log types (`api`, `audit`, `authenticator`, etc.) are enabled for a complete audit trail.
- **Scaling with Karpenter:** Instead of traditional EKS Managed Node Groups for workloads, Karpenter is used to dynamically provision nodes of the appropriate size on demand.

## 4. Deployment Sequence (Block Level)

The cluster deployment is a multi-step process managed by Terragrunt dependencies.

```mermaid
graph TD;
    subgraph "Prerequisite (SPEC-NETWORKING-AWS)"
        A[1. VPC Created] --> B[2. Subnets Created];
    end

    subgraph "Cluster Deployment (SPEC-K8S-EKS)"
        B --> C[3. <b>Deploy EKS Control Plane</b><br/><i>(Module: eks-cluster)</i>];
        C --> D[4. <b>Install Cilium CNI</b><br/><i>(Module: cilium)</i><br/>As a critical add-on];
        C --> E[5. <b>Install Karpenter Controller</b><br/><i>(Module: karpenter)</i>];
        E --> F[6. <b>Configure NodePools & Provisioners</b><br/><i>(Module: karpenter-nodepools)</i><br/>Defines what node types Karpenter can create];
    end

    subgraph "Result"
        F --> G{Ready-to-use EKS Cluster};
    end
```

### Sequence Description:

1.  **VPC & Subnets:** First, as part of `SPEC-NETWORKING-AWS`, the required network infrastructure is created. The EKS module has a `dependency "vpc"` block that consumes the outputs (VPC ID, Subnet IDs) from this stage.
2.  **EKS Control Plane:** The "brain" of the cluster is deployed. At this stage, no worker nodes for user workloads exist yet.
3.  **Cilium (CNI):** Immediately after the control plane is up, the Cilium network plugin is installed. Without it, nodes cannot join the cluster, and pods cannot communicate.
4.  **Karpenter:** The Karpenter controller is installed. It will be responsible for creating and managing all future worker nodes.
5.  **Karpenter NodePools:** Finally, Karpenter's Custom Resource Definitions (CRDs) are applied, which define the instance types, architectures, and purchasing options it can use to provision nodes for various workloads.

Upon completion of these steps, the cluster is fully prepared to accept applications deployed via the GitOps process (`SPEC-GITOPS-ARGOCD`).
