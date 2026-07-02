# Standard Specification: Foundational AWS Security (SPEC-SECURITY-AWS)

- **ID:** `SPEC-SECURITY-AWS`
- **Name:** Foundational AWS Security
- **Status:** **Ready**
- **Dependencies:** `SPEC-IAC-SETUP`

---

## 1. Purpose

This specification describes the standard for creating a foundational security layer at the AWS Organization level. These measures are applied centrally from the organization's master account and automatically propagate to all member accounts, creating essential security guardrails.

## 2. Architecture: Centralized Security Management

All components of this standard are deployed from the `terragrunt/_org/_global/` directory into the AWS Organization's master account. They leverage the "-org" capabilities of AWS services to ensure that all existing and future accounts automatically inherit a baseline of security and monitoring.

## 3. Components

| Component | Terraform Module | Purpose |
| :--- | :--- | :--- |
| **Organization Structure** | `organization` | Manages the AWS Organization structure (OUs, accounts). |
| **Guardrail Policies** | `scps` | **Service Control Policies.** Enforce strict permissions boundaries at the OU/account level (e.g., deny users from deleting CloudTrail logs or disabling GuardDuty). |
| **Baseline IAM Roles** | `iam-baseline` | Creates a standard set of IAM roles and policies in all accounts (e.g., `TerragruntDeployRole` for CI/CD). |
| **Centralized Audit Trail**| `cloudtrail` | Enables AWS CloudTrail for the entire organization and aggregates logs into a central S3 bucket in a dedicated "log-archive" account. |
| **Threat Detection** | `guardduty-org` | Centrally enables AWS GuardDuty and designates the master account as the administrator for findings. |
| **Security Posture Mgmt** | `security-hub` | Centrally enables AWS Security Hub to aggregate and prioritize findings from GuardDuty, IAM Access Analyzer, and other services. |
| **Single Sign-On (SSO)** | `sso` | Configures AWS IAM Identity Center (formerly SSO) to manage user access to all accounts. |
| **Emergency Access** | `break-glass-user`| Creates a highly-privileged "break-glass" user for emergency situations, with access being strictly monitored and controlled. |

## 4. Deployment Sequence

Deploying foundational security is a sequential process that builds the security posture layer by layer.

```mermaid
graph TD;
    subgraph "Phase 1: Establish Structure"
        A[1. <b>Define Organization Structure</b><br/><i>(Module: organization)</i><br/>Creates OUs and member accounts]
    end

    subgraph "Phase 2: Enforce Guardrails"
        A --> B[2. <b>Apply Service Control Policies (SCPs)</b><br/><i>(Module: scps)</i><br/>The highest level of restriction];
        A --> C[3. <b>Create Baseline IAM Roles</b><br/><i>(Module: iam-baseline)</i>];
    end
    
    subgraph "Phase 3: Enable Monitoring & Audit Services"
        B --> D[4. <b>Enable Org-wide CloudTrail</b><br/><i>(Module: cloudtrail)</i>];
        B --> E[5. <b>Enable Org-wide GuardDuty</b><br/><i>(Module: guardduty-org)</i>];
        E --> F[6. <b>Enable Org-wide Security Hub</b><br/><i>(Module: security-hub)</i>];
    end

    subgraph "Phase 4: Configure Access"
        C --> G[7. <b>Configure AWS SSO</b><br/><i>(Module: sso)</i>];
        C --> H[8. <b>Create Break-Glass User</b><br/><i>(Module: break-glass-user)</i>];
    end

    subgraph "Result"
        [F, G, H, D] --> I{Secure AWS Organization Foundation};
    end
```

### Sequence Description:

1.  **Organization Structure:** First, the AWS Organization structure itself is defined, including Organizational Units (OUs) for different environment types.
2.  **Apply SCPs:** Immediately after, Service Control Policies are applied. These are the most powerful guardrails, as they cannot be overridden even by the root user of a member account.
3.  **Baseline IAM Roles:** A standard set of roles required for automation and administration is created across the organization.
4.  **Enable CloudTrail:** API activity logging is enabled for all regions in all accounts, with logs shipped to a central, secure location.
5.  **Enable GuardDuty:** The intelligent threat detection service is enabled organization-wide.
6.  **Enable Security Hub:** A central dashboard for aggregating and prioritizing all security findings is activated.
7.  **Configure SSO:** A single point of entry for human users is configured.
8.  **Create Break-Glass User:** An emergency access user is created, following security best practices.

Upon completion of these steps, the AWS environment is ready for the secure deployment of the network infrastructure (`SPEC-NETWORKING-AWS`).
