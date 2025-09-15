🧰 Production Bare-Metal Kubernetes + Cilium + Istio + (Optional) Autoscaling (Terragrunt) — Design Plan
Design for a highly available, secure, and scalable Kubernetes platform on bare-metal servers from various providers (e.g., OVH, Hetzner) using kubeadm for cluster bootstrapping, managed by Terragrunt for Infrastructure as Code (IaC), and integrated with Cilium, Istio, and robust secrets management.
Table of Contents
Goal
Key Differences from EKS
Architecture at a Glance
Prereqs & Versions (Workstation)
High-Level Terragrunt Design Principles
Terragrunt Directory Structure
Infrastructure Provisioning (Terraform/Terragrunt)
1. Server Provisioning Module
2. Networking Module
3. Kubeadm Bootstrap Module
Kubernetes Core Components (Terragrunt & Helm/Manifests)
1. MetalLB (for LoadBalancer Service type)
2. Cilium CNI
3. Secrets Management (Provider-Agnostic)
4. Istio (Single & Multi-Cluster)
5. Scaling
Network Policies
Pod Security Standards (PSS)
Go Application Design Principles
Traffic Management Kinds (Istio APIs / Gateway API)
Operational Considerations
Design Summary & Key Takeaways
Goal
To provide a highly available, secure, and scalable Kubernetes platform on bare-metal servers from various providers (e.g., OVH, Hetzner, etc.) using kubeadm for cluster bootstrapping, managed by Terragrunt for Infrastructure as Code (IaC), and integrated with Cilium, Istio, and robust secrets management.

Key Differences from EKS
Infrastructure Provisioning: No AWS-managed services (VPC, EC2, EKS control plane, managed node groups). All underlying infrastructure (servers, networking) must be provisioned and bootstrapped explicitly.
Networking: Provider-specific networking will be managed (e.g., private networks, firewalls). Cilium will be the primary CNI.
Control Plane Management: kubeadm will be used to initialize and join control plane nodes. High availability (HA) will be explicitly configured.
Autoscaling: Karpenter is AWS-specific. We'll explore cluster-autoscaler with provider-specific cloud providers (if available/feasible) or rely on static provisioning + KEDA/HPA for pod scaling.
Secrets: AWS-specific services like Secrets Manager/Parameter Store won't be directly used. Solutions will need to be provider-agnostic or self-hosted.
IaC Tooling: Terragrunt wraps Terraform, enabling efficient multi-environment and multi-provider configurations.
Architecture at a Glance
Kubernetes (Kubeadm): Self-managed control plane (HA with 3+ nodes).
Cilium: As the CNI, handling pod networking and network policies.
Istio 1.27.x: Service mesh for traffic management, observability, and security.
Secrets: Provider-agnostic solutions (e.g., HashiCorp Vault, External Secrets Operator with generic backends, or SOPS).
Bare-Metal Servers: Provisioned across 2-3 physical locations/regions/providers for resilience.
Load Balancing: External load balancers (e.g., MetalLB for Layer 2/BGP) for Service type LoadBalancer and ingress.
Persistent Storage: Provider-specific (e.g., Ceph, Rook, Linstor, or local PVs with topolvm).
IaC: Terragrunt orchestrating Terraform modules for server provisioning and cluster bootstrapping.
Prereqs & Versions (Workstation)
kubectl, helm
go 1.22+ (if using Go for applications, or specific tooling)
terraform, terragrunt (latest stable versions)
ansible (for post-provisioning server configuration)
sops (for secrets encryption)
High-Level Terragrunt Design Principles
DRY (Don't Repeat Yourself): Use Terragrunt's generate and include blocks to define common configurations (e.g., backend, provider) at higher levels and inherit them.
Modular Terraform: Each logical component (e.g., server provisioning for Hetzner, OVH, Kubeadm setup, Cilium install) will be a separate Terraform module.
Environment/Provider Separation: Directory structure will reflect environments (dev/prod) and providers (hetzner/ovh).
Remote State: Use a robust, shared remote state backend (e.g., S3/GCS/MinIO bucket).
Secrets Management: Integrate sops for encrypting sensitive values within Terragrunt configurations.
Terragrunt Directory Structure
code
Code
├── live
│   ├── _envcommon           # Common configurations for all environments
│   │   ├── provider.hcl     # Define common Terraform provider configs
│   │   └── backend.hcl      # Define remote state backend
│   ├── prod                 # Production environment
│   │   ├── _provider_defaults.hcl # Provider-specific default settings (e.g., region)
│   │   ├── hetzner          # Hetzner provider configuration
│   │   │   ├── servers      # Terraform module for Hetzner server provisioning
│   │   │   │   └── terragrunt.hcl
│   │   │   ├── network      # Terraform module for Hetzner private network setup
│   │   │   │   └── terragrunt.hcl
│   │   │   └── kubeconfig   # Terraform module for fetching/managing kubeconfig
│   │   │       └── terragrunt.hcl
│   │   ├── ovh              # OVH provider configuration (similar structure to hetzner)
│   │   │   ├── servers
│   │   │   ├── network
│   │   │   └── kubeconfig
│   │   └── cluster          # Kubernetes cluster bootstrapping (kubeadm, shared)
│   │       ├── terragrunt.hcl
│   │       ├── manifests    # Kubernetes manifests applied after cluster init
│   │       │   ├── cilium
│   │       │   │   └── terragrunt.hcl
│   │       │   ├── metallb
│   │       │   │   └── terragrunt.hcl
│   │       │   ├── istio
│   │       │   │   └── terragrunt.hcl
│   │       │   ├── secrets
│   │       │   │   └── terragrunt.hcl
│   │       │   └── cluster-autoscaler # If used
│   │       │       └── terragrunt.hcl
│   └── dev                  # Development environment (similar structure to prod)
└── modules
    ├── hetzner-servers      # Terraform module to provision Hetzner servers
    ├── ovh-servers          # Terraform module to provision OVH servers
    ├── kubeadm-bootstrap    # Terraform module to run kubeadm on provisioned servers (via Ansible/remote-exec)
    ├── cilium-helm          # Terraform module to install Cilium via Helm
    ├── istio-helm           # Terraform module to install Istio via Helm
    ├── metallb-helm         # Terraform module to install MetalLB
    ├── secrets-operator-helm # Terraform module to install ESO/Vault agent
    ├── cluster-autoscaler-helm # Terraform module to install CA
    └── common-tools-ansible # Ansible playbook module for common server configs
Infrastructure Provisioning (Terraform/Terragrunt)
1. Server Provisioning Module (modules/<provider>-servers)
Takes desired instance types, counts, and OS images.
Provisions bare-metal servers using provider-specific Terraform providers (e.g., hetznercloud/hcloud, ovh/ovh).
Outputs server IPs (public/private), IDs.
Improvement: Use cloud-init or similar mechanisms for initial server setup (SSH keys, basic users) or rely on Ansible for comprehensive post-provisioning.
2. Networking Module (modules/<provider>-network)
Creates private networks, attaches servers to them.
Configures firewall rules (e.g., allowing specific ports for Kubernetes, SSH).
Outputs network IDs, private IP ranges.
3. Kubeadm Bootstrap Module (modules/kubeadm-bootstrap)
Terraform + Ansible: This module will use null_resource with remote-exec or integrate with local ansible-playbook calls.
Steps:
Install Docker/containerd and Kubernetes components (kubeadm, kubelet, kubectl).
Initialize the Kubernetes control plane (kubeadm init) on the first control plane node.
Join additional control plane nodes.
Join worker nodes.
Configure HAProxy or an external Load Balancer (e.g., from provider) as the API server endpoint for HA control plane.
Copy kubeconfig to a secure location (e.g., a dedicated S3/MinIO bucket).
Improvement: Use a dedicated Ansible role for all Kubeadm-related tasks for better maintainability and reusability.
Kubernetes Core Components (Terragrunt & Helm/Manifests)
This section uses Terraform modules that call Helm charts or apply raw Kubernetes manifests.

1. MetalLB (for LoadBalancer Service type)
Terragrunt Module: live/prod/cluster/manifests/metallb/terragrunt.hcl points to modules/metallb-helm.
Installs MetalLB (either Layer 2 or BGP mode, depending on provider network capabilities).
Configures an IP address pool for LoadBalancer services, using a dedicated range from your private network.
Improvement: For BGP mode, ensure network devices support it and are configured correctly.
2. Cilium CNI
Terragrunt Module: live/prod/cluster/manifests/cilium/terragrunt.hcl points to modules/cilium-helm.
Installs Cilium via Helm.
IPAM Mode:
cluster-pool: Generally preferred for bare-metal to manage pod IPs separately from host IPs, conserving provider-assigned IPs. Specify a dedicated clusterPoolIpv4PodCidrList.
host-scope: Each node manages its own pod IP range. Simpler but less flexible for large clusters.
kubeProxyReplacement=true, hubble.enabled=true for observability.
Improvement: Ensure tunnel=vxlan or geneve for multi-node connectivity, especially if nodes span different provider private networks.
3. Secrets Management (Provider-Agnostic)
Option A: HashiCorp Vault (Self-hosted):
Terragrunt Module: Provision Vault servers (e.g., on dedicated bare-metal instances), then install Vault with a proper storage backend (e.g., Consul, Raft).
Kubernetes integration: Use Vault Agent Injector or External Secrets Operator with a Vault backend to inject/sync secrets.
Option B: External Secrets Operator (ESO) with Generic Backends:
Terragrunt Module: live/prod/cluster/manifests/secrets/terragrunt.hcl points to modules/secrets-operator-helm.
Install ESO.
Configure ClusterSecretStore to retrieve secrets from a provider-agnostic store like a secure Git repository encrypted with SOPS.
Option C: SOPS (Mozilla Secrets Operator):
Directly encrypt .yaml files with sensitive data using SOPS.
Terragrunt/Ansible can decrypt these files during deployment. Less dynamic for application secrets.
Recommendation: ESO with SOPS-encrypted files in a Git repository offers a good balance of security and operational simplicity for bare-metal.
Improvement: Vault provides more advanced features (dynamic secrets, strong authentication), but adds operational overhead.
4. Istio (Single & Multi-Cluster)
Terragrunt Module: live/prod/cluster/manifests/istio/terragrunt.hcl points to modules/istio-helm.
Installation: Similar to EKS, use istioctl install or a Helm chart (wrapped in Terraform).
Multi-Cluster: The conceptual architecture remains similar (multi-primary, multi-network with east-west gateways). The challenge is ensuring network reachability between clusters across different providers' private networks (e.g., VPN tunnels, or public endpoints with strict firewalls).
Improvement: Explicitly outline how cross-provider network connectivity (e.g., VPN tunnels between Hetzner and OVH private networks) would be established for multi-cluster Istio.
5. Scaling
Horizontal Pod Autoscaler (HPA) & Vertical Pod Autoscaler (VPA): Remain the same; they operate at the Kubernetes layer.
KEDA: Also functions identically, as it scales deployments based on external events.
Cluster Autoscaler (CA):
Karpenter Alternative: Bare-metal environments typically lack a "cloud provider" integration for CA.
Options:
Manual Scaling: Provision more bare-metal servers via Terragrunt/provider APIs when needed.
Custom Cluster Autoscaler: Write a custom CA implementation for your specific bare-metal providers (complex).
Static Pools: Pre-provision capacity and rely on HPA/KEDA for pod-level scaling.
Recommendation: Start with static capacity and rely on HPA/KEDA. If demand truly fluctuates for node capacity, investigate provider APIs for VM/server creation and integrate into a custom CA, or implement a reactive provisioning flow.
Network Policies
The CiliumNetworkPolicy and Kubernetes NetworkPolicy examples from the EKS manual remain identical as they are Kubernetes-native APIs enforced by Cilium. The same principle of denying app=default can be applied.

Pod Security Standards (PSS)
PSS is a Kubernetes-native feature and is identical to the EKS setup. The Namespace labels for enforce: "restricted" apply directly.

Go Application Design Principles
The Go application design principles (distroless, non-root, graceful shutdown, metrics, tracing) are entirely portable to bare-metal Kubernetes, as they are best practices for containerized applications regardless of the underlying infrastructure.

Traffic Management Kinds (Istio APIs / Gateway API)
The Istio Gateway, VirtualService, DestinationRule and Kubernetes Gateway API (HTTPRoute, GRPCRoute) concepts and examples are identical as they are service mesh APIs operating at the Kubernetes layer.

Operational Considerations
Monitoring & Logging: Self-host Prometheus/Grafana and Loki/Fluentd. Terragrunt can deploy these via Helm.
Backup & Restore: Implement Velero for Kubernetes resource backups, and a strategy for etcd backups.
OS Patching/Upgrades: A separate process (e.g., Ansible playbook, unattended upgrades) for OS and Kubernetes component patching/upgrades on bare-metal nodes.
HA Proxy/Keepalived: For control plane HA, ensure a stable virtual IP for the API server endpoint.
Design Summary & Key Takeaways
The core challenge for bare-metal Kubernetes is provisioning and managing the underlying infrastructure and the Kubernetes control plane itself, which is abstracted away by EKS. Terragrunt's multi-level configuration and module-based approach are well-suited for handling the provider-specific differences in server and network provisioning, while also managing the common Kubernetes components (Cilium, Istio, secrets).

The critical areas for focus will be:

Robust Kubeadm Bootstrapping: Automating the setup of a highly available control plane.
Provider-Agnostic Secrets: Implementing a secure and manageable secrets solution for applications.
Bare-Metal Load Balancing: Effectively exposing services using solutions like MetalLB.
Network Connectivity for Multi-Cluster: Designing and implementing secure cross-provider network links if using multi-cluster Istio.
This design provides a solid blueprint. The next step would be to start implementing the Terraform modules and Terragrunt configurations, testing each layer incrementally.
