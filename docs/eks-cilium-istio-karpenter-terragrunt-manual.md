# 🧰 Production Bare‑Metal Kubernetes + Cilium + Istio + (Optional) Autoscaling (Terragrunt) — **Design Plan**

> Design for a highly available, secure, and scalable Kubernetes platform on **bare‑metal servers** from various providers (e.g., **OVH**, **Hetzner**) using **kubeadm** for cluster bootstrapping, managed by **Terragrunt** for Infrastructure as Code (IaC), and integrated with **Cilium**, **Istio**, and robust **secrets management**.

---

## Table of Contents

- [Goal](#goal)
- [Key Differences from EKS](#key-differences-from-eks)
- [Architecture at a Glance](#architecture-at-a-glance)
- [Prereqs & Versions (Workstation)](#prereqs--versions-workstation)
- [High‑Level Terragrunt Design Principles](#high-level-terragrunt-design-principles)
- [Terragrunt Directory Structure](#terragrunt-directory-structure)
- [Infrastructure Provisioning (Terraform/Terragrunt)](#infrastructure-provisioning-terraforterragrunt)
  - [1. Server Provisioning Module](#1-server-provisioning-module)
  - [2. Networking Module](#2-networking-module)
  - [3. Kubeadm Bootstrap Module](#3-kubeadm-bootstrap-module)
- [Kubernetes Core Components (Terragrunt & Helm/Manifests)](#kubernetes-core-components-terragrunt--helmmanifests)
  - [1. MetalLB (for LoadBalancer Service type)](#1-metallb-for-loadbalancer-service-type)
  - [2. Cilium CNI](#2-cilium-cni)
  - [3. Secrets Management (Provider‑Agnostic)](#3-secrets-management-provider-agnostic)
  - [4. Istio (Single & Multi‑Cluster)](#4-istio-single--multi-cluster)
  - [5. Scaling](#5-scaling)
- [Network Policies](#network-policies)
- [Pod Security Standards (PSS)](#pod-security-standards-pss)
- [Go Application Design Principles](#go-application-design-principles)
- [Traffic Management Kinds (Istio APIs / Gateway API)](#traffic-management-kinds-istio-apis--gateway-api)
- [Operational Considerations](#operational-considerations)
- [Design Summary & Key Takeaways](#design-summary--key-takeaways)

---

## Goal

Provide a highly available, secure, and scalable **Kubernetes** platform on **bare‑metal servers** from various providers (OVH, Hetzner, etc.) using **kubeadm** for cluster bootstrapping, managed by **Terragrunt** for IaC, and integrated with **Cilium**, **Istio**, and robust **secrets management**.

---

## Key Differences from EKS

- **Infrastructure Provisioning:** No AWS‑managed services (VPC, EC2, EKS control plane, managed node groups). All underlying infrastructure (servers, networking) must be provisioned and bootstrapped explicitly.
- **Networking:** Provider‑specific networking will be managed (e.g., private networks, firewalls). **Cilium** will be the primary CNI.
- **Control Plane Management:** `kubeadm` will initialize and join control plane nodes. **High availability (HA)** will be explicitly configured.
- **Autoscaling:** **Karpenter** is AWS‑specific. Explore **cluster‑autoscaler** with provider‑specific cloud providers (if feasible) or rely on static provisioning + **KEDA/HPA** for pod scaling.
- **Secrets:** AWS‑specific services like Secrets Manager/Parameter Store won’t be used directly. Solutions must be **provider‑agnostic** or **self‑hosted**.
- **IaC Tooling:** **Terragrunt** wraps **Terraform**, enabling efficient multi‑environment and multi‑provider configurations.

---

## Architecture at a Glance

- **Kubernetes (kubeadm):** Self‑managed control plane (**HA with 3+ nodes**).
- **Cilium:** CNI handling pod networking and network policies.
- **Istio 1.27.x:** Service mesh for traffic management, observability, and security.
- **Secrets:** Provider‑agnostic solutions (e.g., **HashiCorp Vault**, **External Secrets Operator** with generic backends, or **SOPS**).
- **Bare‑Metal Servers:** Provisioned across **2–3 physical locations/regions/providers** for resilience.
- **Load Balancing:** External load balancers (e.g., **MetalLB** for Layer 2/BGP) for `Service` type **LoadBalancer** and ingress.
- **Persistent Storage:** Provider‑specific (e.g., **Ceph/Rook**, **Linstor**, or local PVs with **topolvm**).
- **IaC:** **Terragrunt** orchestrating Terraform modules for server provisioning and cluster bootstrapping.

---

## Prereqs & Versions (Workstation)

- `kubectl`, `helm`
- `go` **1.22+** (if using Go for apps or tooling)
- `terraform`, `terragrunt` (latest stable)
- `ansible` (for post‑provisioning server configuration)
- `sops` (for secrets encryption)

---

## High‑Level Terragrunt Design Principles

- **DRY:** Use Terragrunt’s `generate` and `include` blocks to define common configs (e.g., backend, provider) at higher levels and inherit them.
- **Modular Terraform:** Each logical component (e.g., **Hetzner** servers, **OVH** servers, **kubeadm** setup, **Cilium** install) is a **separate module**.
- **Environment/Provider Separation:** Directory structure reflects **environments** (dev/prod) and **providers** (hetzner/ovh).
- **Remote State:** Use a robust, shared remote state backend (e.g., **S3/GCS/MinIO bucket**).
- **Secrets Management:** Integrate **SOPS** for encrypting sensitive values within Terragrunt configurations.

---

## Terragrunt Directory Structure

```text
code/
├── live
│   ├── _envcommon               # Common configs for all environments
│   │   ├── provider.hcl         # Common Terraform provider configs
│   │   └── backend.hcl          # Remote state backend
│   ├── prod                     # Production environment
│   │   ├── _provider_defaults.hcl
│   │   ├── hetzner              # Hetzner provider configuration
│   │   │   ├── servers          # Hetzner server provisioning
│   │   │   │   └── terragrunt.hcl
│   │   │   ├── network          # Hetzner private network setup
│   │   │   │   └── terragrunt.hcl
│   │   │   └── kubeconfig       # Fetch/manage kubeconfig
│   │   │       └── terragrunt.hcl
│   │   ├── ovh                  # OVH provider configuration
│   │   │   ├── servers
│   │   │   ├── network
│   │   │   └── kubeconfig
│   │   └── cluster              # Kubernetes cluster bootstrap (kubeadm)
│   │       ├── terragrunt.hcl
│   │       ├── manifests        # Manifests applied after cluster init
│   │       │   ├── cilium
│   │       │   │   └── terragrunt.hcl
│   │       │   ├── metallb
│   │       │   │   └── terragrunt.hcl
│   │       │   ├── istio
│   │       │   │   └── terragrunt.hcl
│   │       │   ├── secrets
│   │       │   │   └── terragrunt.hcl
│   │       │   └── cluster-autoscaler
│   │       │       └── terragrunt.hcl
│   └── dev                      # Development environment (mirrors prod)
└── modules
    ├── hetzner-servers          # Terraform: provision Hetzner servers
    ├── ovh-servers              # Terraform: provision OVH servers
    ├── kubeadm-bootstrap        # Terraform+Ansible: run kubeadm on nodes
    ├── cilium-helm              # Terraform: install Cilium via Helm
    ├── istio-helm               # Terraform: install Istio via Helm
    ├── metallb-helm             # Terraform: install MetalLB
    ├── secrets-operator-helm    # Terraform: install ESO/Vault agent
    ├── cluster-autoscaler-helm  # Terraform: install Cluster Autoscaler
    └── common-tools-ansible     # Ansible: common server configs
```

---

## Infrastructure Provisioning (Terraform/Terragrunt)

### 1. Server Provisioning Module

- Inputs: desired instance types, counts, OS images.
- Provisions bare‑metal servers using provider‑specific Terraform providers (e.g., `hcloud`, `ovh`).
- Outputs: server IDs, public/private IPs.
- **Improvement:** Use **cloud‑init** for initial setup (SSH keys, users) or rely on **Ansible** for comprehensive post‑provisioning.

### 2. Networking Module

- Creates **private networks** and attaches servers.
- Configures **firewall rules** (Kubernetes ports, SSH).
- Outputs: network IDs, private IP ranges.

### 3. Kubeadm Bootstrap Module

- **Terraform + Ansible**: `null_resource` with `remote-exec` or invoke `ansible-playbook` locally.
- Steps:
  1. Install **container runtime** (containerd) and Kubernetes components (`kubeadm`, `kubelet`, `kubectl`).
  2. **Initialize** control plane (`kubeadm init`) on the first control plane node.
  3. **Join** additional control plane nodes.
  4. **Join** worker nodes.
  5. Configure **HAProxy/Keepalived** or external LB as the **API server endpoint** for HA.
  6. Copy **kubeconfig** to a secure location (e.g., **S3/MinIO** bucket).
- **Improvement:** Create a dedicated **Ansible role** for all kubeadm tasks to improve maintainability.

---

## Kubernetes Core Components (Terragrunt & Helm/Manifests)

> These modules deploy via Terraform (Helm provider) or `kubectl` manifests driven by Terragrunt.

### 1. MetalLB (for LoadBalancer Service type)

- Module: `live/prod/cluster/manifests/metallb/terragrunt.hcl` → `modules/metallb-helm`
- Installs **MetalLB** in **Layer 2** or **BGP** mode (provider‑dependent).
- Configures an **address pool** for `LoadBalancer` Services using a dedicated range from your private network.
- **Improvement:** For **BGP** mode, ensure upstream network devices support BGP and are configured correctly.

### 2. Cilium CNI

- Module: `live/prod/cluster/manifests/cilium/terragrunt.hcl` → `modules/cilium-helm`
- Installs **Cilium** via Helm.
- **IPAM Mode:**
  - `cluster-pool`: preferred on bare‑metal to manage pod IPs separately from host IPs; set `clusterPoolIpv4PodCidrList`.
  - `host-scope`: each node manages its own pod IP range (simpler, less flexible).
- Recommended flags: `kubeProxyReplacement=true`, `hubble.enabled=true`.
- **Improvement:** Use `tunnel=vxlan` or `geneve` for multi‑node connectivity, especially across provider private networks.

### 3. Secrets Management (Provider‑Agnostic)

- **Option A: HashiCorp Vault (Self‑hosted)**
  - Provision Vault servers (dedicated nodes), configure storage backend (**Consul/Raft**).
  - Integrate with Kubernetes via **Vault Agent Injector** or **External Secrets Operator** (Vault backend).
- **Option B: External Secrets Operator (ESO) with Generic Backends**
  - Module: `live/prod/cluster/manifests/secrets/terragrunt.hcl` → `modules/secrets-operator-helm`
  - Install ESO; configure `ClusterSecretStore` to retrieve secrets from a **SOPS‑encrypted** Git repo or other provider‑agnostic store.
- **Option C: SOPS (Mozilla Secrets Operator)**
  - Encrypt YAML files with SOPS; Terragrunt/Ansible decrypts during deployment.
  - Less dynamic for app secrets.

> **Recommendation:** ESO + SOPS‑encrypted Git repo offers a solid balance of security and simplicity. **Vault** adds powerful features (dynamic creds, auth) but increases operational overhead.

### 4. Istio (Single & Multi‑Cluster)

- Module: `live/prod/cluster/manifests/istio/terragrunt.hcl` → `modules/istio-helm`
- Install via `istioctl` or Helm.
- **Multi‑Cluster:** Use **multi‑primary, multi‑network** with **east‑west gateways**. The main challenge is **cross‑provider network reachability** (e.g., **VPN tunnels** between Hetzner/OVH private networks, or public endpoints with strict firewalls).
- **Improvement:** Explicitly design and automate **cross‑provider VPNs** or secure overlays to enable east‑west traffic.

### 5. Scaling

- **HPA & VPA:** Same behavior (Kubernetes‑native).
- **KEDA:** Scales workloads based on **external events** (SQS/Kafka/Prometheus, etc.).
- **Cluster Autoscaler (CA):**
  - **Karpenter alternative** (AWS‑specific) is **not available**.
  - **Options:**
    - **Manual Scaling:** Provision more bare‑metal servers via Terragrunt/provider APIs when needed.
    - **Custom Cluster Autoscaler:** Implement for your provider (complex).
    - **Static Pools:** Pre‑provision capacity; rely on **HPA/KEDA** for pod‑level scaling.
  - **Recommendation:** Start with **static capacity** + **HPA/KEDA**. If node demand fluctuates heavily, integrate provider APIs to provision servers reactively and join them to the cluster.

---

## Network Policies

The **CiliumNetworkPolicy** and **Kubernetes NetworkPolicy** examples from the EKS manual remain valid—they are **Kubernetes‑native APIs** enforced by **Cilium**. The same deny pattern for `app=default` applies unchanged.

---

## Pod Security Standards (PSS)

**PSS** is **Kubernetes‑native** and identical to EKS usage. Apply namespace labels to **enforce** the `restricted` profile:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: workloads
  labels:
    pod-security.kubernetes.io/enforce: "restricted"
    pod-security.kubernetes.io/enforce-version: "latest"
    pod-security.kubernetes.io/audit: "restricted"
    pod-security.kubernetes.io/warn: "restricted"
```

---

## Go Application Design Principles

- **Containers & Security:** Distroless/minimal base; run as **non‑root**; read‑only root FS.
- **Health & Lifecycle:** **Liveness** (`/livez`), **readiness** (`/readyz`), graceful shutdown on `SIGTERM` (30s timeout).
- **Observability:** Expose **Prometheus** metrics (`/metrics`), **OpenTelemetry** traces.
- **Networking:** Favor **HTTP/2** for gRPC; configure sane **timeouts/retries**; let **Istio** handle advanced routing/failover.

---

## Traffic Management Kinds (Istio APIs / Gateway API)

- **Istio APIs (mature):** `Gateway`, `VirtualService`, `DestinationRule` for HTTP/HTTPS/gRPC routing, subsets, mTLS, outlier detection, locality.
- **Kubernetes Gateway API (future‑leaning):** `GatewayClass/Gateway` + `HTTPRoute` for HTTP/HTTPS and `GRPCRoute` for gRPC; cleaner, native CRDs.

> Concepts and examples are the **same** on bare‑metal since they operate purely at the Kubernetes/mesh layer.

---

## Operational Considerations

- **Monitoring & Logging:** Self‑host **Prometheus/Grafana** and **Loki/Fluentd**. Deploy via Terragrunt + Helm.
- **Backup & Restore:** Use **Velero** for Kubernetes resource backups; establish **etcd backup** strategy.
- **OS Patching/Upgrades:** Manage via **Ansible** (or similar) for OS and Kubernetes component updates on nodes.
- **Control Plane HA:** Use **HAProxy/Keepalived** (VIP) for the API server endpoint.
- **Security Baselines:** CIS hardening for nodes, RBAC least‑privilege, image signing (Cosign/Sigstore), and regular CVE scanning.

---

## Design Summary & Key Takeaways

The core challenge for **bare‑metal Kubernetes** is provisioning and managing the **underlying infrastructure** and the **control plane**—tasks abstracted away by EKS. **Terragrunt’s** multi‑level configuration and **module‑based** approach are well‑suited to handle provider‑specific differences (servers, networking) while managing common Kubernetes components (**Cilium**, **Istio**, **secrets**).

**Focus Areas:**
- **Robust Kubeadm Bootstrapping:** Automate HA control plane setup.
- **Provider‑Agnostic Secrets:** Implement secure, maintainable secrets workflows.
- **Bare‑Metal Load Balancing:** Expose services effectively with **MetalLB**.
- **Multi‑Cluster Connectivity:** Engineer secure cross‑provider links (VPN/overlay) for **Istio** multi‑cluster.

This design is a solid blueprint. Next, implement the **Terraform modules** and **Terragrunt** configurations, testing each layer incrementally.
