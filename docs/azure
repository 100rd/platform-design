AKS Cilium Istio Karpenter Terragrunt Manual
This manual describes the steps to set up a robust, scalable, and secure Kubernetes platform on Azure using Azure Kubernetes Service (AKS), managed by Terragrunt, with networking provided by Cilium, service mesh capabilities from Istio, and autoscaling handled by Karpenter.

Table of Contents
Introduction
Prerequisites
Infrastructure Setup with Terragrunt
Azure Resource Group and Network
Azure Kubernetes Service (AKS) Cluster
Managed Identities and Role Assignments
Core Services Deployment
Cilium CNI Installation
Istio Service Mesh Installation
Karpenter Installation
Platform Configuration
DNS and Ingress Configuration
Observability (Monitoring & Logging)
Security Best Practices
Application Deployment Example
Maintenance and Operations
Troubleshooting
1. Introduction
This document outlines the architecture and deployment steps for a cloud-native platform on Azure, leveraging AKS as the managed Kubernetes service. The platform is designed for high availability, scalability, and enhanced security, utilizing a modern technology stack:

Azure Kubernetes Service (AKS): Managed Kubernetes for container orchestration.
Terragrunt: A thin wrapper for Terraform to manage DRY configurations and maintain state.
Cilium: High-performance networking and network policy enforcement.
Istio: A powerful service mesh for traffic management, security, and observability.
Karpenter: Intelligent, high-performance Kubernetes cluster autoscaler.
This setup enables efficient resource management, robust application connectivity, and streamlined operations for microservices-based applications.

2. Prerequisites
Before starting, ensure you have the following installed and configured:

Azure CLI: Authenticated to your Azure subscription.
Terraform & Terragrunt: Latest versions installed.
Kubectl: Configured to interact with Kubernetes clusters.
Helm: Package manager for Kubernetes.
Istioctl: Istio command-line utility.
Git: For cloning this repository.
Azure Subscription: With sufficient quotas and permissions to create resources.
3. Infrastructure Setup with Terragrunt
This section details the Azure infrastructure setup using Terragrunt, which manages Terraform configurations for modularity and reusability.

3.1 Azure Resource Group and Network
First, define the core networking components that will host your AKS cluster.

Terragrunt Structure Example:

code
Code
live/
└── prod/
    └── region-eastus/
        ├── networking/
        │   └── terragrunt.hcl  (defines VNet, Subnets, Network Security Groups)
        └── aks/
            └── terragrunt.hcl (defines AKS cluster)
networking/terragrunt.hcl (Conceptual):

code
Hcl
include {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/networking" # Path to your networking Terraform module
}

inputs = {
  resource_group_name = "rg-aks-platform-prod-eastus"
  location            = "eastus"
  vnet_name           = "vnet-aks-platform-prod-eastus"
  address_space       = ["10.0.0.0/16"]
  subnets = {
    aks_subnet = {
      name             = "aks-subnet"
      address_prefixes = ["10.0.0.0/22"]
      # Consider adding Service Endpoints or Private Endpoints here if needed
    }
    app_gateway_subnet = {
      name             = "app-gateway-subnet"
      address_prefixes = ["10.0.4.0/24"] # For Azure Application Gateway if used for ingress
    }
    # Add other subnets as needed (e.g., database, jumpbox)
  }
}
Deployment Steps:

Navigate to live/prod/region-eastus/networking.
Run terragrunt plan.
Run terragrunt apply.
3.2 Azure Kubernetes Service (AKS) Cluster
Configure the AKS cluster, including node pools, network profile, and integration with Azure services. For Cilium, it's recommended to deploy AKS with Azure CNI Powered by Cilium for a managed experience, or BYO CNI (Bring Your Own CNI) and install Cilium manually. This guide assumes a manual Cilium installation on an AKS cluster provisioned with a basic network plugin (like kubenet for simpler cases or Azure CNI without Cilium for more advanced setups where you then install Cilium). For best results, plan for Azure CNI with network policies disabled by default if you want Cilium to handle all network policies.

aks/terragrunt.hcl (Conceptual):

code
Hcl
include {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/aks" # Path to your AKS Terraform module
}

inputs = {
  resource_group_name = "rg-aks-platform-prod-eastus"
  location            = "eastus"
  cluster_name        = "aks-platform-prod-eastus"
  kubernetes_version  = "1.28.3" # Specify your desired K8s version
  vnet_name           = "vnet-aks-platform-prod-eastus"
  aks_subnet_id       = "..." # Reference output from networking module
  
  # Agent pool configuration (initial default pool, Karpenter will manage others)
  default_node_pool = {
    name                 = "systempool"
    vm_size              = "Standard_DS2_v2"
    node_count           = 3
    os_disk_size_gb      = 128
    mode                 = "System"
    enable_auto_scaling  = false # Karpenter will handle autoscaling
    # Add node labels for system components if needed
  }

  # Network profile: Important for Cilium setup
  network_plugin = "azure" # or "kubenet" if you prefer
  # network_policy = "calico" # Set to "none" if Cilium will manage network policies entirely
  
  # Enable Azure RBAC for Kubernetes authorization
  enable_azure_rbac = true
  
  # Managed Identity for AKS
  identity_type = "SystemAssigned" # Or UserAssigned for more control
  
  # Other AKS features
  private_cluster_enabled = true # Recommended for production
  
  # Integrate with Azure Monitor
  oms_agent_enabled = true
  log_analytics_workspace_id = "..." # Reference output from a monitoring module
}
Deployment Steps:

Ensure the networking components are deployed.
Navigate to live/prod/region-eastus/aks.
Run terragrunt plan.
Run terragrunt apply.
3.3 Managed Identities and Role Assignments
Create Azure Managed Identities for various platform components (e.g., Karpenter, CSI drivers) and assign necessary Azure RBAC roles.

Terragrunt Example (identity/terragrunt.hcl):

code
Hcl
include {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/identity" # Path to your identity Terraform module
}

inputs = {
  resource_group_name = "rg-aks-platform-prod-eastus"
  location            = "eastus"
  
  managed_identities = {
    karpenter_identity = {
      name = "mi-karpenter-aks-prod"
    }
    # Add identities for Azure CSI Driver, External DNS, etc.
  }

  role_assignments = [
    {
      principal_id               = "..." # Output from karpenter_identity
      role_definition_name       = "Contributor" # Or more granular roles for Karpenter
      scope                      = "..." # Scope to the resource group or subscription
      description                = "Allows Karpenter to create and manage VMs"
    }
    # Add other role assignments (e.g., for Azure Container Registry pull, Storage Account access)
  ]
}
Key Roles for Karpenter:

Contributor on the resource group containing the AKS cluster and VMSS.
Managed Identity Operator on its own Managed Identity (if User-Assigned).
Virtual Machine Contributor on the Subscription or Resource Group.
Deployment Steps:

Navigate to live/prod/region-eastus/identity.
Run terragrunt plan.
Run terragrunt apply.
4. Core Services Deployment
Once the AKS cluster is up, deploy the essential platform services.

4.1 Cilium CNI Installation
Cilium provides advanced networking capabilities, including eBPF-based data plane, network policy enforcement, and load balancing.

Deployment Steps:

Get Kubeconfig:
code
Bash
az aks get-credentials --resource-group rg-aks-platform-prod-eastus --name aks-platform-prod-eastus
Install Cilium using Helm:
Decide on your Cilium configuration. For example, to enable Hubble (observability) and L7 policies:
code
Bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium --version 1.14.5 \
    --namespace kube-system \
    --set azure.enabled=true \
    --set azure.resourceGroup=rg-aks-platform-prod-eastus \
    --set azure.vnetName=vnet-aks-platform-prod-eastus \
    --set azure.subnetName=aks-subnet \
    --set ipam.mode=azure-eni \
    --set bpf.masquerade=true \
    --set egressMasqueradeInterfaces="eth0" \
    --set hubble.enabled=true \
    --set hubble.ui.enabled=true \
    --set hubble.relay.enabled=true \
    --set loadBalancer.enableExternalIPs=true \
    --set k8sServiceHost=aks-platform-prod-eastus-dns-.... # Find this from `az aks show` output
    --set k8sServicePort=443
Note: The ipam.mode=azure-eni is crucial for Azure CNI integration. Adjust other settings based on your specific requirements. If your AKS was provisioned with kubenet, adjust ipam.mode accordingly. You might need to helm upgrade or re-install if changing network plugin settings post-deployment.
Verify Cilium Status:
code
Bash
kubectl -n kube-system get pods -l k8s-app=cilium
cilium status
Ensure all Cilium pods are running and healthy.
4.2 Istio Service Mesh Installation
Istio provides a programmable layer for managing, connecting, and securing microservices.

Deployment Steps:

Download and Install Istioctl:
Follow the official Istio documentation to download and add istioctl to your PATH.
Install Istio with IstioOperator:
Create an IstioOperator custom resource to define your Istio configuration.
code
Yaml
# istio-operator-config.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
  name: example-istio-config
spec:
  profile: default # or "demo", "production"
  meshConfig:
    accessLogFile: /dev/stdout
  components:
    ingressGateways:
      - name: istio-ingressgateway
        enabled: true
        k8s:
          service:
            type: LoadBalancer # Expose ingress gateway via Azure Load Balancer
            # annotations: # Add Azure-specific LB annotations if needed
            #   service.beta.kubernetes.io/azure-load-balancer-resource-group: "rg-public-lbs"
  values:
    global:
      proxy:
        privileged: true # Required if using Cilium CNI and sidecar injection
      proxy_init:
        privileged: true
      # For mutual TLS with Cilium and Istio, ensure that the proxy and CNI are configured to work together.
      # For example, ensure that Cilium allows traffic on the required ports (15001, 15006) for Istio sidecar.
code
Bash
kubectl create namespace istio-system
istioctl install -f istio-operator-config.yaml --set hub=gcr.io/istio-release
Verify Istio Installation:
code
Bash
kubectl get pods -n istio-system
Ensure all Istio control plane pods are running.
Enable Namespace for Istio Injection:
code
Bash
kubectl label namespace default istio-injection=enabled --overwrite
# Or for a specific application namespace:
# kubectl label namespace myapp-namespace istio-injection=enabled --overwrite
4.3 Karpenter Installation
Karpenter is an open-source, high-performance Kubernetes cluster autoscaler that quickly launches right-sized compute resources in response to changing application load.

Deployment Steps:

Create Karpenter Service Account and Role Bindings:
This typically involves creating a Kubernetes Service Account and binding it to the Azure Managed Identity created in Section 3.3.
code
Yaml
# karpenter-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: karpenter
  namespace: kube-system
  annotations:
    # Link to the Azure Managed Identity for Karpenter
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    service.beta.kubernetes.io/azure-load-balancer-resource-group: "rg-aks-platform-prod-eastus"
    # OIDC Federation setup or AAD Pod Identity for UserAssigned Managed Identity
    # This is where you connect the ServiceAccount to the Managed Identity
    # If using AAD Pod Identity (Legacy):
    # aadpodidentity.k8s.io/is-managed-identity: "true"
    # aadpodidentity.k8s.io/managed-identity-name: "mi-karpenter-aks-prod"
    # If using Azure AD Workload Identity (Recommended):
    # azure.workload.identity/client-id: "<client-id-of-your-user-assigned-mi>"
---
# karpenter-rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: karpenter
rules:
  # ... (Karpenter required RBAC rules) ...
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: karpenter
subjects:
  - kind: ServiceAccount
    name: karpenter
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: karpenter
  apiGroup: rbac.authorization.k8s.io
code
Bash
kubectl apply -f karpenter-sa.yaml
kubectl apply -f karpenter-rbac.yaml
Note: For Azure AD Workload Identity, ensure you follow the official AKS documentation for setting up OIDC issuer and federated credentials between your Kubernetes Service Account and the Azure Managed Identity.
Install Karpenter using Helm:
code
Bash
helm repo add karpenter https://charts.karpenter.sh/
helm repo update

helm install karpenter karpenter/karpenter \
    --namespace kube-system \
    --set serviceAccount.create=false \
    --set serviceAccount.name=karpenter \
    --set clusterName=aks-platform-prod-eastus \
    --set clusterEndpoint=$(az aks show --resource-group rg-aks-platform-prod-eastus --name aks-platform-prod-eastus --query fqdn -o tsv) \
    --set defaultProvisioner.spec.providerRef.name=default \
    --set defaultProvisioner.spec.provider.azure.resourceGroup=rg-aks-platform-prod-eastus \
    --set defaultProvisioner.spec.provider.azure.subnetName=aks-subnet \
    --set defaultProvisioner.spec.provider.azure.instanceProfile=Standard_DS2_v2 # Example instance profile
    # Configure other settings like ttlSecondsAfterEmpty, etc.
The clusterEndpoint is the FQDN of your AKS API server.
Define Karpenter Provisioners:
Karpenter uses Provisioners to define how nodes should be provisioned.
code
Yaml
# default-provisioner.yaml
apiVersion: karpenter.sh/v1beta1
kind: Provisioner
metadata:
  name: default
spec:
  providerRef:
    name: default-azure-provider # This can reference a pre-defined Azure resource
  requirements:
    - key: kubernetes.io/arch
      operator: In
      values: ["amd64"]
    - key: kubernetes.io/os
      operator: In
      values: ["linux"]
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["on-demand"] # or ["spot"] for cost savings
    - key: topology.kubernetes.io/zone
      operator: In
      values: ["eastus-1", "eastus-2", "eastus-3"] # Adjust to your region's zones
  limits:
    resources:
      cpu: 1000 # Max CPU for the cluster from Karpenter
  consolidation:
    enabled: true
  ttlSecondsAfterEmpty: 30 # Nodes deprovision after 30 seconds of being empty
  # Example taint to prevent general pods on system nodes
  # taints:
  #   - key: karpenter.sh/provisioner-name
  #     value: default
  #     effect: NoSchedule
---
# default-azure-provider.yaml (Referenced by the Provisioner)
apiVersion: karpenter.azure.com/v1alpha2
kind: AzureProvider
metadata:
  name: default-azure-provider
spec:
  resourceGroup: rg-aks-platform-prod-eastus
  subnetName: aks-subnet
  clusterName: aks-platform-prod-eastus
  vmImage:
    offer: UbuntuServer
    publisher: Canonical
    sku: 18.04-LTS
    version: latest
  instanceTypes:
    - Standard_DS2_v2
    - Standard_DS3_v2
    # Add other suitable VM sizes
code
Bash
kubectl apply -f default-provisioner.yaml
kubectl apply -f default-azure-provider.yaml
Note: The AzureProvider is a custom resource provided by Karpenter's Azure provider. Ensure you have the correct CRDs installed with Karpenter.
5. Platform Configuration
Configure essential platform services for robust operations.

5.1 DNS and Ingress Configuration
Configure DNS resolution and set up an ingress controller for external access to applications.

Azure DNS Zone: Create a public or private DNS zone in Azure for your cluster domain.
ExternalDNS (Optional, but recommended):
Install ExternalDNS to automatically manage DNS records in Azure DNS based on Kubernetes Ingresses or Services.
code
Bash
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm install external-dns external-dns/external-dns \
    --namespace kube-system \
    --set provider=azure \
    --set azure.resourceGroup=rg-aks-platform-prod-eastus \
    --set azure.tenantId=$(az account show --query tenantId -o tsv) \
    --set azure.subscriptionId=$(az account show --query id -o tsv) \
    --set azure.aadClientId=<sp-client-id-or-mi-client-id> \
    --set azure.aadClientSecret=<sp-client-secret-if-using-sp> \
    --set azure.useManagedIdentityExtension=true # If using Managed Identity
    --set azure.zoneName=<your-domain.com> # Your Azure DNS Zone
Ensure the Managed Identity used by ExternalDNS has DNS Zone Contributor permissions on the Azure DNS Zone.
Istio Ingress Gateway:
The Istio Ingress Gateway (deployed in Section 4.2) acts as your entry point. Configure Gateway and VirtualService resources to expose applications.
code
Yaml
# example-gateway.yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: my-app-gateway
  namespace: default
spec:
  selector:
    istio: ingressgateway # The Istio ingress gateway pod label
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "myapp.your-domain.com"
    - port:
        number: 443
        name: https
        protocol: HTTPS
      hosts:
        - "myapp.your-domain.com"
      tls:
        mode: SIMPLE
        credentialName: my-app-tls-secret # Kubernetes Secret containing TLS cert/key
code
Yaml
# example-virtualservice.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app-vs
  namespace: default
spec:
  hosts:
    - "myapp.your-domain.com"
  gateways:
    - my-app-gateway
  http:
    - route:
        - destination:
            host: my-app-service # Kubernetes Service name
            port:
              number: 80
code
Bash
kubectl apply -f example-gateway.yaml
kubectl apply -f example-virtualservice.yaml
Note: For TLS, ensure you have a Kubernetes Secret (my-app-tls-secret) containing your certificate and key. Consider using Azure Key Vault integration with AKS (via CSI driver) for managing secrets.
5.2 Observability (Monitoring & Logging)
Leverage Azure Monitor and other tools for comprehensive observability.

Azure Monitor for Containers: Enabled by default with oms_agent_enabled=true in Terragrunt for AKS. Provides metrics, logs, and health status for your cluster.
Prometheus & Grafana:
Deploy Prometheus for metrics collection and Grafana for visualization.
code
Bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace
Note: Ensure Prometheus can scrape Istio and Cilium metrics.
Hubble (Cilium Observability):
If enabled during Cilium installation, Hubble provides deep visibility into network traffic and security policies.
code
Bash
cilium hubble enable --ui # if not enabled during install
# Access Hubble UI
cilium hubble ui
Azure Log Analytics Workspace: Centralized logging for AKS and other Azure resources. Configure applications to send logs to stdout/stderr, which AKS forwards to Log Analytics.
5.3 Security Best Practices
Implement security measures across the platform.

Azure RBAC for AKS: Use Azure AD integration for user authentication and authorization to the Kubernetes API server.
Network Policies (Cilium): Define granular network policies using Cilium to control inter-pod communication and egress traffic.
Istio Mutual TLS: Leverage Istio's mTLS for secure communication between services.
Pod Security Standards (or OPA Gatekeeper): Enforce security policies at the pod level.
Azure Policy for AKS: Use Azure Policy to enforce security and compliance rules on your AKS clusters (e.g., forbidding privileged containers).
Azure Key Vault CSI Driver: Integrate Azure Key Vault to securely manage secrets, certificates, and keys for applications.
Container Image Security: Use Azure Container Registry (ACR) with vulnerability scanning.
6. Application Deployment Example
Deploy a sample application to demonstrate the platform's capabilities.

Create a Namespace with Istio Injection:
code
Bash
kubectl create namespace my-app
kubectl label namespace my-app istio-injection=enabled --overwrite
Deploy a Sample Microservice:
code
Yaml
# my-app-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: nginx:latest # Replace with your application image
          ports:
            - containerPort: 80
          # Add resource requests/limits for Karpenter to scale correctly
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
---
# my-app-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-service
  namespace: my-app
spec:
  selector:
    app: my-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
code
Bash
kubectl apply -f my-app-deployment.yaml -n my-app
Observe Karpenter scaling up a new node if needed.
Configure Istio Gateway and Virtual Service (similar to 5.1):
Expose your application via the Istio Ingress Gateway.
7. Maintenance and Operations
AKS Upgrades: Regularly update AKS cluster Kubernetes versions using Azure CLI or Terragrunt.
Component Upgrades: Keep Cilium, Istio, Karpenter, and other Helm charts updated.
Monitoring & Alerting: Set up Azure Monitor alerts for critical metrics and logs.
Backup & Restore: Implement a disaster recovery plan for Kubernetes resources (e.g., using Velero for volume snapshots and resource backups) and Azure resources.
Cost Management: Monitor Azure costs using Cost Management + Billing and optimize Karpenter Provisioner settings.
8. Troubleshooting
Kubeconfig Issues: Ensure az aks get-credentials is run and your KUBECONFIG environment variable is set correctly.
Terragrunt/Terraform Errors: Check state files, syntax, and apply in the correct order. Use terragrunt validate and terragrunt fmt.
Cilium Issues:
Check cilium status.
Inspect Cilium agent logs: kubectl logs -n kube-system -l k8s-app=cilium --tail=100.
Use cilium connectivity test for network debugging.
Istio Issues:
Check Istio control plane pods: kubectl get pods -n istio-system.
Use istioctl analyze to check for configuration issues.
Inspect sidecar logs for application pods.
Karpenter Issues:
Check Karpenter controller logs: kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100.
Examine events on Provisioner and NodePool resources.
Check for relevant Azure service principal/managed identity permissions.
Azure Resource Issues: Use Azure Activity Log, Resource Health, and Azure Monitor logs for insights into underlying Azure resources.
`
