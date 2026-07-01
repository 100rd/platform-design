# Platform Onboarding Manual for Engineers and AI Agents

**Version:** 1.1
**Objective:** This document is the single source of truth for any engineer or AI agent working with this platform. It describes the key subsystems and provides step-by-step instructions ("skills") for executing standard tasks.

**The Golden Rule:** **Don't write code until you've confirmed it hasn't been written already.** First explore, then integrate.

---

## Table of Contents

1.  [Skill: Infrastructure Management (Terraform & Terragrunt)](#skill-1-infrastructure)
2.  [Skill: Application Management (ArgoCD & Kargo)](#skill-2-applications)
3.  [Skill: Security and Compliance](#skill-3-security)
4.  [Skill: Tagging and Labeling Strategy](#skill-4-tagging)

---

<a name="skill-1-infrastructure"></a>
## 1. Skill: Infrastructure Management (Terraform & Terragrunt)

**Objective:** To create, modify, or delete cloud resources (VPCs, EKS clusters, databases, etc.).

### ► Principles

*   **Modules are the Library:** `terraform/modules/` is the canonical library of "building blocks." These modules are wrappers around public modules and enforce our standards. Do not modify them without a compelling reason.
*   **Terragrunt is the Orchestrator:** `terragrunt/` is the "live" configuration that invokes modules with specific parameters. There should be no `resource` blocks here.
*   **Hierarchy is Law:** `Account -> Region -> Stack`. Always follow this structure.

### ► Step-by-Step Workflow: Creating a New Stack

1.  **VERIFY:** Ensure that `terraform/modules/` contains the modules you need. In 99% of cases, it will. Read their `variables.tf` files to understand what parameters they accept.
2.  **CREATE DIRECTORY:** Choose the correct account and region, then create a new directory for your stack.
    *   *Example:* `terragrunt/dev/us-east-1/my-new-service/`
3.  **CREATE CONFIGURATION FILES:** Inside the new directory, create `region.hcl` and `env.hcl` to hold region- and environment-specific variables.
4.  **DEFINE THE STACK MANIFEST:** Create a *single* `terragrunt.stack.hcl` file. This file is the complete manifest for your entire stack. It should be structured as follows:
    *   **a) Include Root:** Start by including the `root.hcl` to configure the backend.
    *   **b) Define Global `inputs`:** Create a top-level `inputs = {}` block. It should read common variables (like `cluster_name`, `tags`) from your `region.hcl` and `env.hcl` files. These inputs will be available to all components in the stack.
    *   **c) Declare `unit` blocks:** For each component (VPC, EKS, etc.), declare a `unit "..." {}` block. Inside each block, specify:
        *   `source`: The path to the component's module in `terraform/modules/`.
        *   `dependencies`: (Optional) A list of other `unit` names in this file that must be deployed first.
        *   `inputs`: (Optional) A block for parameters that are *specific* to this unit and are not in the global `inputs` block.

**Example `terragrunt.stack.hcl`:**
```hcl
# Include the root configuration for backend setup.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Common inputs merged into every module in the stack.
inputs = {
  aws_region      = read_terragrunt_config("region.hcl").locals.aws_region
  cluster_name    = read_terragrunt_config("env.hcl").locals.cluster_name
  tags            = read_terragrunt_config("env.hcl").locals.tags
}

# --- Stack Components ---

# Deploys the VPC network.
unit "vpc" {
  source = "../../../../terraform/modules/vpc"

  # Inputs specific to the VPC module.
  inputs = {
    name = "my-service-${read_terragrunt_config("env.hcl").locals.environment}"
    cidr = read_terragrunt_config("env.hcl").locals.vpc_cidr
    azs  = read_terragrunt_config("env.hcl").locals.azs
  }
}

# Deploys the EKS control plane.
unit "eks" {
  source = "../../../../terraform/modules/eks-agent-cluster"
  dependencies = ["vpc"] # Depends on the 'vpc' unit above.

  # Inputs specific to the EKS module, using outputs from the VPC.
  inputs = {
    vpc_id     = dependency.vpc.outputs.vpc_id
    subnet_ids = dependency.vpc.outputs.private_subnets
  }
}
```

---

<a name="skill-2-applications"></a>
## 2. Skill: Application Management (ArgoCD & Kargo)

**Objective:** To deploy and manage Kubernetes applications.

### ► Principles

*   **Git is the Single Source of Truth:** The ArgoCD UI is for observation only. All changes must be made through this Git repository.
*   **Kustomize is our Configurator:** `overlays/` and `cluster-envs/` are used to apply patches over the base configuration for different environments.
*   **Kargo is our Promoter:** The rollout of new versions for `workloads` is managed by Kargo, not by directly changing an image tag in Git.

### ► Step-by-Step Workflow: Adding a New Application

**Scenario A: A Shared Infrastructure Component (for ALL clusters)**

1.  **ACTION:** Create a Helm chart in `apps/infra/<component-name>/`.
2.  **ACTION:** (Optional) Add environment-specific `values.yaml` files in `envs/<env>/values/infra/`.
3.  **RESULT:** An existing `ApplicationSet` will automatically discover and deploy your application.

**Scenario B: A Business Team's Application**

1.  **ACTION:** Create a `kustomization.yaml` and its manifests in `workloads/<team>/<service-name>/`.
2.  **ACTION:** If you need changes for `prod` (e.g., a different image), create a patch in `cluster-envs/prod/` and reference it in that overlay's `kustomization.yaml`.
3.  **ACTION:** Register the new application by adding it to your team's `apps.yaml` file.
4.  **ACTION (CI/CD):** Configure your CI pipeline to create a `Freight` in Kargo with the new image tag after a successful build.
5.  **RESULT:** Kargo will automatically promote the new version to `dev`/`stage`. A manual approval in the Kargo UI will be required to promote to `prod`.

---

<a name="skill-3-security"></a>
## 3. Skill: Security and Compliance

**Objective:** To pass all automated security checks when contributing new code or infrastructure.

### ► Principles

*   **Security is a Process, Not a Stage:** Checks are embedded in the CI pipeline and should be run locally before every commit.
*   **Least Privilege is Mandatory:** Never use `*` in IAM policies. Use specialized modules like `pod-identity-*` to create granular, purpose-built roles.

### ► Step-by-Step Workflow: Validating a New Service

1.  **CHECK (Secrets):** Before committing, run `gitleaks detect --source . -v` to ensure you have not accidentally committed any secrets.
2.  **CHECK (IaC):** If you changed Terraform code, run `checkov -d .` from the directory of your change to scan it against security policies.
3.  **CHECK (Containers):** If you built a new Docker image, run `trivy image my-new-app:1.2.3` to scan it for known vulnerabilities.
4.  **CHECK (IAM):** Instead of creating IAM roles manually, use an existing `pod-identity-*` module (e.g., `pod-identity-ebs-csi`). It will correctly create a ServiceAccount and bind it to a least-privilege IAM role.

---

<a name="skill-4-tagging"></a>
## 4. Skill: Tagging and Labeling Strategy

**Objective:** To correctly classify resources for automation, access control, and cost allocation.

### ► Principles

*   **Single Source of Truth:** `docs/tagging-label-access-control-strategy.md`. Always refer to this document.
*   **Labels are the Glue:** They connect resources in AWS (managed by Terraform) to configurations in Kubernetes (used by ArgoCD, Karpenter).

### ► Step-by-Step Workflow: Adding a New Resource

1.  **ACTION (Terraform):**
    *   Always pass the standard set of tags to your modules: `tags = read_terragrunt_config("env.hcl").locals.tags`.
    *   Add functional tags where required. *Example:* `private_subnet_tags = { "karpenter.sh/discovery" = "my-cluster" }`.
2.  **ACTION (ArgoCD):**
    *   When registering a new cluster, ensure its `Secret` in ArgoCD has the correct labels: `cluster-role`, `env`, `region`. Without them, `ApplicationSet`s will not find your cluster.
3.  **ACTION (Kubernetes):**
    *   Apply standard Kubernetes labels to your `Deployment` and `Pod` resources so they are correctly discovered by `Service`s and `NetworkPolicy`s.
