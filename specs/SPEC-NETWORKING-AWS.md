# Standard Specification: AWS Network Infrastructure (SPEC-NETWORKING-AWS)

- **ID:** `SPEC-NETWORKING-AWS`
- **Name:** AWS Network Infrastructure
- **Status:** **Ready**
- **Dependencies:** `SPEC-IAC-SETUP`

---

## 1. Purpose

This specification describes the standard for deploying a centralized, scalable, and secure network infrastructure in AWS. This infrastructure serves as the transport backbone for all environments and services.

## 2. Architecture: Hub-and-Spoke with Transit Gateway

The platform uses a **Hub-and-Spoke** architecture.

- **Hub:** An **AWS Transit Gateway (TGW)** serves as the central hub. It is deployed in a dedicated "network" AWS account, ensuring centralized management and security.
- **Spokes:** Each environment-specific AWS account (`dev`, `staging`, `prod`) contains its own VPC. These VPCs (the spokes) connect to the central TGW via **TGW attachments**.

This approach provides several benefits:
- **Traffic Segmentation:** Control which VPCs can communicate with each other via TGW route tables.
- **Simplified Connectivity:** Avoids a complex and fragile mesh of VPC peerings.
- **Centralized Services:** Allows for shared services (e.g., VPN access, traffic inspection) to be placed in a single, secure location.

## 3. Components & Versions

| Component | Tool/Implementation | Version | Description |
| :--- | :--- | :--- | :--- |
| **VPC** | `terraform-aws-modules/vpc/aws` | `6.6.0` | Public Terraform module for creating VPCs and subnets. |
| **Central Hub**| `terraform/modules/transit-gateway` | local | Local module for deploying the AWS Transit Gateway. |
| **Connectivity** | `terraform/modules/tgw-attachment`| local | Local module for attaching a VPC to the TGW. |
| **Resource Sharing**| `terraform/modules/ram-share` | local | Module for sharing the TGW via AWS RAM so other accounts can attach to it. |
| **DNS Resolution** | `terraform/modules/route53-resolver`| local | Module for configuring Route53 Resolver rules to enable cross-VPC DNS resolution. |

## 4. Deployment Sequence

The network deployment is a multi-stage process managed by Terragrunt dependencies.

```mermaid
graph TD;
    subgraph "Phase 1: Central Hub (in Network Account)"
        A[1. <b>Deploy Transit Gateway (TGW)</b><br/><i>(Module: transit-gateway)</i>] --> B[2. <b>Create TGW Route Tables</b><br/><i>(Module: tgw-route-tables)</i>];
        B --> C[3. <b>Share TGW via RAM</b><br/><i>(Module: ram-share)</i><br/>Allows other accounts to see it];
    end

    subgraph "Phase 2: Environment Spokes (in Dev, Prod accounts)"
        D[4. <b>Create Environment VPC</b><br/><i>(Module: vpc)</i>] --> E[5. <b>Accept RAM Share & Attach to TGW</b><br/><i>(Module: tgw-attachment)</i>];
    end
    
    C --> D;

    subgraph "Phase 3: Routing & DNS"
        E --> F[6. <b>Configure Routes in TGW & VPCs</b><br/><i>(Modules: tgw-route-tables, vpc)</i>];
        F --> G[7. <b>Configure Route53 Resolver Rules</b><br/><i>(Module: route53-resolver)</i><br/>For cross-VPC DNS];
    end

    subgraph "Result"
        G --> H{Connected & Segmented Network Environment};
    end
```

### Sequence Description:

1.  **Deploy Transit Gateway:** First, the TGW itself is created within the dedicated network account.
2.  **Create TGW Route Tables:** TGW route tables are established to define the routing policies between different environment types (e.g., `dev` can talk to `dev`, but not to `prod`).
3.  **Share TGW via RAM:** The TGW is shared using AWS Resource Access Manager (RAM), making it visible and available for attachment from other accounts in the organization.
4.  **Create Environment VPCs:** In each environment account (`dev`, `prod`, etc.), an isolated VPC is provisioned.
5.  **Attach to TGW:** Each environment's VPC accepts the RAM share and creates an attachment to the central TGW.
6.  **Configure Routing:** Route tables in both the TGW and the individual VPCs are updated to direct traffic through the TGW.
7.  **Configure DNS:** Route53 Resolver rules are configured to allow hosts in different VPCs to resolve each other's DNS names.

Upon completion, this process yields a ready network environment upon which EKS clusters (`SPEC-K8S-EKS`) can be securely deployed.
