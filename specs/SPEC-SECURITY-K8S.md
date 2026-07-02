# Standard Specification: Kubernetes Security (SPEC-SECURITY-K8S)

- **ID:** `SPEC-SECURITY-K8S`
- **Name:** Kubernetes Security
- **Status:** **Ready**
- **Dependencies:** `SPEC-GITOPS-ARGOCD`

---

## 1. Purpose

This specification describes the standard for the in-cluster security components. It implements a multi-layered, defense-in-depth strategy, managed declaratively via GitOps.

## 2. Technologies

| Domain | Tool/Implementation | Purpose |
| :--- | :--- | :--- |
| **Static Analysis** | **Checkov**, **Trivy** | Scans IaC and container images for vulnerabilities and misconfigurations during the CI phase. |
| **Secret Scanning** | **Gitleaks** | Scans the Git repository for accidentally committed secrets. |
| **Network Security** | **Cilium** | Enforces Kubernetes Network Policies to implement micro-segmentation. |
| **Runtime Security** | **Falco** | Detects anomalous activity and threats at runtime by analyzing kernel-level system calls. |
| **Service Mesh** | **Istio** | Provides mTLS for traffic encryption, and fine-grained authorization policies between services. |

## 3. Key Security Layers

### 3.1. Shift-Left Security (Preventative)

Security is integrated into the earliest stages of the CI/CD pipeline.

- **IaC Scanning:**
    - **Checkov:** Scans Terraform modules (`.checkov.yml`) with a well-maintained list of skipped checks, indicating a mature security posture.
    - **Custom Policies:** The project extends standard checks with custom policies (`checkov-policies/`) aligned with the AWS Well-Architected Framework.
- **Secret Scanning:**
    - **Gitleaks:** The `.gitleaks.toml` configuration prevents secrets from being committed, with a thoughtful allowlist to reduce false positives.

### 3.2. In-Cluster Network Security

A **Zero Trust Networking** model is implemented within the cluster.

- **Default Deny:** The `network-policies/default-deny-all.yaml` policy blocks all ingress and egress traffic for all pods by default.
- **Explicit Allow Rules:** Network access is granted on a case-by-case basis through explicit `NetworkPolicy` resources (e.g., `allow-dns-egress.yaml`).
- **Micro-segmentation:** Application-specific policies (e.g., in `gpu-inference/`) are created to allow only the necessary traffic, minimizing the attack surface.
- **Service Mesh (Istio):** Provides mutual TLS (mTLS) to encrypt all east-west traffic between services automatically.

### 3.3. Runtime Threat Detection

- **Falco:** The Falco agent is deployed via GitOps as a DaemonSet. It monitors kernel-level activity and generates alerts for suspicious behavior (e.g., shell running in a container, unexpected network connections, sensitive file access).

## 4. Deployment Sequence

All in-cluster security components are deployed declaratively via the GitOps process.

```mermaid
graph TD;
    A[ArgoCD is operational<br/>(from SPEC-GITOPS-ARGOCD)] --> B[1. <b>Deploy Core Security Add-ons</b><br/>ArgoCD syncs applications for Falco, Istio, etc.];
    B --> C[2. <b>Apply Global Network Policies</b><br/>ArgoCD applies `default-deny-all.yaml` to establish a zero-trust baseline];
    C --> D[3. <b>Deploy Applications with Specific Policies</b><br/>Each application is deployed along with its own NetworkPolicy, allowing necessary traffic];
    D --> E{Secure cluster runtime};
```

### Sequence Description:

1.  **Deploy Core Add-ons:** Once ArgoCD is running, it begins deploying the core security services defined in its ApplicationSets, including the Istio service mesh and Falco agents.
2.  **Apply Global Policies:** ArgoCD applies the global `default-deny-all` NetworkPolicy, immediately locking down all pod-to-pod communication.
3.  **Deploy Applications:** As ArgoCD deploys individual business applications, it also deploys their corresponding `NetworkPolicy` resources. These policies selectively open up the required ports and communication paths for that specific application, adhering to the principle of least privilege.
