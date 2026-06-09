# Platform Security: Tag & Label-Based Access Control Strategy

This document outlines the architectural strategy and technical implementation details for enforcing security boundaries and access control using metadata (tags and labels) across the primary environments: **AWS, GCP, Kubernetes, and GitHub**.

Using metadata-driven policies—often called **Attribute-Based Access Control (ABAC)**—decouples permission definitions from specific resource IDs or roles. This prevents role explosion, simplifies onboarding, and dynamically secures resources as they are provisioned.

---

## 1. AWS: Attribute-Based Access Control (ABAC) & Pod Identity

AWS supports native ABAC by evaluating resource tags, request tags, and principal tags in IAM policies.

### A. Core Mechanisms
In AWS IAM JSON policies, access control is governed by three primary condition keys:

1. **`aws:ResourceTag/key-name`**: Inspects tags attached to the target resource (e.g., S3 buckets, EC2 instances, KMS keys).
2. **`aws:PrincipalTag/key-name`**: Inspects tags attached to the caller (IAM User or IAM Role).
3. **`aws:RequestTag/key-name`**: Inspects tags passed in the API request during resource creation or tagging.
4. **`aws:TagKeys`**: Controls which tag keys can be modified or created.

### B. Technical Examples

#### 1. Dynamic Principal-to-Resource Matching (The ABAC Core)
This policy allows developers to start, stop, or modify EC2 instances **only** if the developer's `platform:owner` tag matches the EC2 instance's `platform:owner` tag, and both share the same environment:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TagBasedEC2Operations",
      "Effect": "Allow",
      "Action": [
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:RebootInstances"
      ],
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/platform:owner": "${aws:principal-tag/platform:owner}",
          "aws:ResourceTag/platform:env": "${aws:principal-tag/platform:env}"
        }
      }
    }
  ]
}
```

#### 2. Guardrails: Prevent Untagged Resource Creation
To prevent bypassing security controls, this policy blocks creating resources (e.g., EBS Volumes) unless the mandatory tagging keys defined in [ADR-0028](file:///Users/lo/Develop/multi-team-agentic/project/platform-design/docs/adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md) are supplied:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnforceMandatoryTagsOnCreation",
      "Effect": "Deny",
      "Action": "ec2:CreateVolume",
      "Resource": "*",
      "Condition": {
        "Null": {
          "aws:RequestTag/platform:system": "true",
          "aws:RequestTag/platform:owner": "true",
          "aws:RequestTag/platform:env": "true"
        }
      }
    }
  ]
}
```

### C. Kubernetes Pod Identity Session Integration (ADR-0018)
Under [ADR-0018](file:///Users/lo/Develop/multi-team-agentic/project/platform-design/docs/adrs/0018-eks-pod-identity-as-default-workload-identity.md), workloads use EKS Pod Identity. When a pod requests credentials, the EKS Pod Identity Agent automatically injects six **session tags** as principal tags:

* `eks-cluster-arn`
* `eks-cluster-name`
* `kubernetes-namespace`
* `kubernetes-service-account`
* `kubernetes-pod-name`
* `kubernetes-pod-uid`

This allows AWS IAM roles to dynamically grant access to AWS resources (like Secrets Manager or S3) based on the requesting pod's Kubernetes namespace. For instance, the **External Secrets Operator (ESO)** role can read secrets *only* if the secret path or secret tag matches the session tag:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManagerNamespaceIsolation",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/kubernetes-namespace": "${aws:principal-tag/kubernetes-namespace}"
        }
      }
    }
  ]
}
```

---

## 2. GCP: Labels vs Resource Manager Tags

GCP implements a strict architectural separation between **Labels** and **Tags**. Understanding this difference is critical for security posture.

| Feature | GCP Labels | GCP Resource Manager Tags |
|---|---|---|
| **Primary Purpose** | Querying, grouping, cost allocation, and billing. | Access control (IAM), Network firewalls, Org Policies. |
| **IAM Condition Support** | **No** (Cannot be used in IAM Policies). | **Yes** (Evaluated in IAM Conditions). |
| **Structure** | Unvalidated simple key-value string pairs. | Strongly typed, namespaced resources managed in Resource Manager. |
| **Inheritance** | Does not inherit down the resource hierarchy. | Inherited down the Resource Hierarchy (Org -> Folder -> Project -> Resource). |

### A. Core Mechanisms
GCP Resource Manager Tags are defined centrally at the Organization or Folder level:
1. A **Tag Key** is created (e.g., `1234567890/environment` where `1234567890` is the Org ID).
2. **Tag Values** are defined under the key (e.g., `production`, `development`).
3. These tags are attached to projects, folders, or individual supported resources (Compute Engine VMs, Cloud Storage buckets).
4. IAM Policies use the `resource.matchTag()` helper function in their CEL (Common Expression Language) conditions to grant access.

### B. Technical Example

#### 1. Conditional IAM Policy Binding (CEL)
This terraform snippet binds the role `roles/compute.instanceAdmin.v1` to a developer group, but restricts it *only* to resources tagged with `environment = development`:

```hcl
resource "google_project_iam_member" "developer_compute_admin" {
  project = "my-gcp-project"
  role    = "roles/compute.instanceAdmin.v1"
  member  = "group:developers@mycompany.com"

  condition {
    title       = "Only Development VM Admin"
    description = "Grants instance admin rights only to VMs tagged as development environment"
    expression  = "resource.matchTag('1234567890/environment', 'development')"
  }
}
```

#### 2. GCP Organization Policy Enforcement
You can enforce data perimeters using Org Policies that restrict operations based on tags. For example, blocking public IP creation on VMs unless tagged with `network-zone = public`:

```yaml
# GCP Org Policy snippet (YAML representation)
constraint: constraints/compute.RestrictPublicIp
spec:
  rules:
    - condition:
        expression: "!resource.matchTag('1234567890/network-zone', 'public')"
      denyAll: true
```

---

## 3. Kubernetes: RBAC Restrictions & Workarounds

Kubernetes RBAC (Roles and ClusterRoles) **does not support label selectors**. An RBAC rule allows access to an API resource type (e.g., `pods`) within a namespace or cluster, but cannot grant access only to `pods` matching a specific label. 

To achieve label-based access control, the platform uses three architectural workarounds:

### A. Native Validating Admission Policies (VAP)
Available as GA in Kubernetes 1.30+, VAPs use CEL to validate API requests at admission time. This can block unauthorized users from mutating resources marked with specific labels:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: protect-system-critical-workloads
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["UPDATE", "DELETE"]
        resources: ["deployments", "statefulsets"]
  variables:
    - name: isSystemSec
      expression: "request.userInfo.groups.exists(g, g == 'system:serviceaccounts:team-sec')"
  validations:
    - expression: "!(object.metadata.labels['platform.system'] == 'auth') || variables.isSystemSec"
      message: "Only the Security Team (team-sec) can modify the core auth deployments."
```

### B. Kyverno / OPA Gatekeeper Policy Engines
For complex, multi-tenant environments, policy engines enforce compliance at the api-server boundary. The following Kyverno policy prevents any ServiceAccount other than `team-sec` from deploying a pod labeled with `platform.system: auth`:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: enforce-system-label-ownership
spec:
  validationFailureAction: Enforce
  background: false
  rules:
    - name: restrict-auth-system-labels
      match:
        any:
          - resources:
              kinds:
                - Pod
      preconditions:
        any:
          - key: "{{ request.object.metadata.labels.\"platform.system\" }}"
            operator: Equals
            value: auth
  validate:
        message: "You are not authorized to deploy workloads labeled with platform.system: auth."
        deny:
          conditions:
            all:
              - key: "{{ request.userInfo.username }}"
                operator: NotEquals
                value: "system:serviceaccount:team-sec:auth-deployer"
```

### C. eBPF Network Micro-segmentation (Cilium)
While RBAC governs control plane access, network access is governed via pod labels. Under [ADR-0013](file:///Users/lo/Develop/multi-team-agentic/project/platform-design/docs/adrs/0013-inter-vpc-access-security-model.md) and [ADR-0028](file:///Users/lo/Develop/multi-team-agentic/project/platform-design/docs/adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md), pods use Cilium Network Policies to restrict network flows.

This policy permits pods labeled `platform.component: compute` under system `payment` to communicate **only** with services or databases sharing the `platform.system: payment` label:

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: payment-isolation
  namespace: core-apps
spec:
  endpointSelector:
    matchLabels:
      platform.system: payment
      platform.component: compute
  egress:
    - toEndpoints:
        - matchLabels:
            platform.system: payment
            platform.component: database
```

### D. Legacy Kubernetes ABAC Mode
Kubernetes does natively include an ABAC authorizer (enabled via the API server flag `--authorization-mode=ABAC` and configured via `--authorization-policy-file=policy.jsonl`). 

However, this legacy mechanism is **unsuitable for modern metadata-based access control**:
1. **No Label Support:** K8s legacy ABAC policies can only match basic request attributes: `user`, `group`, `readonly` (boolean matching read actions), `resource` (resource type, e.g., `pods`), `namespace`, and `apiGroup`. It **cannot inspect the labels** on the resources being requested or created.
2. **Static Configuration:** Modifying policies requires SSH access to the Kubernetes control plane nodes to edit the raw policy JSONL file and restart the API server.
3. **No API Representation:** It has no CRD or Kubernetes API representation, preventing GitOps automation.

> [!IMPORTANT]
> Because of these limitations, legacy ABAC is deprecated in practice. Modern Kubernetes deployments use **RBAC** for role boundaries, and delegating attribute-based/label-based access to **Validating Admission Policies (VAP)** or **Webhook admission controllers** (Kyverno, OPA Gatekeeper).

---

## 4. GitHub: Custom Properties, Rulesets & CODEOWNERS

GitHub doesn't use metadata tags to manage which developers can write to a repository. Instead, it uses **Custom Properties** to direct repository configurations at scale, and **Runner Labels** to govern workflow routing.

### A. Repository Custom Properties for Scale Rulesets
Organization Owners define Custom Properties (e.g., `environment`, `compliance-level`, `team-owner`). 

1. **Definition**: Define properties globally in the Org Settings.
2. **Assignment**: Assign properties to repositories (e.g., `my-auth-service` has `environment = production`, `compliance-level = pci-dss`).
3. **Targeting Rulesets**: Create Repository Rulesets (governing branch protection, signed commits, bypass rules) that apply dynamically based on these properties:

```json
{
  "name": "Production Guardrails",
  "target": "repository",
  "conditions": {
    "repository_properties": {
      "include": [
        {
          "property": "environment",
          "operator": "equals",
          "value": "production"
        }
      ]
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 2,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true
      }
    },
    {
      "type": "required_signatures"
    }
  ]
}
```

This enforces strict branch protection policies across hundreds of repositories automatically, without requiring manual individual repository configurations.

### B. GitHub Actions Runner Labels & Isolation
Self-hosted GitHub Actions runners are registered with custom labels (e.g., `pci-runner`, `gpu`, `trusted-vpc`).

1. **Workflow Selection**: Jobs target runners using labels under the `runs-on` property:
   ```yaml
   jobs:
     deploy:
       runs-on: [self-hosted, trusted-vpc]
   ```
2. **Access Control (Runner Groups)**: To prevent untrusted repositories from targetting secure/trusted runners by simply copying the label into their workflow files, GitHub uses **Runner Groups**:
   * Create a runner group (e.g., `Secure-Deployment-Group`).
   * Put the labeled runners inside the group.
   * Configure the group to only accept jobs from specific **explicitly allowed repositories** or **selected workflows**.
   * This prevents unauthorized repositories from executing code on secure runners.

### C. Repository Rulesets vs. CODEOWNERS
 A common question in platform design is whether **Repository Rulesets** can replace the traditional **`CODEOWNERS`** file. 

The short answer is **no, they do not replace CODEOWNERS entirely, but they act as the mandatory enforcement engine for it and can replace path-based write restrictions.**

#### Comparison Matrix

| Feature | `CODEOWNERS` File | Repository Rulesets |
|---|---|---|
| **Primary Focus** | Defining file/path ownership to automatically assign reviewers. | Enforcing branch/tag guardrails (merge blocks, signed commits, bypass rules). |
| **Granularity (Files to Teams)** | **Excellent:** Maps complex file paths (e.g., `/infra/*.tf`) to specific users/teams (`@devops`). | **Limited:** Can block path changes, but cannot assign specific reviewers dynamically based on the path. |
| **Blocking Capability** | **Passive/Soft:** Requests a review. Needs branch protection enabled to make approvals mandatory. | **Active/Hard:** Blocks pushes or merges directly at the GitHub API gateway level. |
| **Management Scale** | **Per-Repository:** Stored inside each repo (`.github/CODEOWNERS`). Hard to enforce uniformly across an org. | **Org-Wide:** Managed at the Organization level and applied automatically to target repositories via Custom Properties. |

#### How They Integrate
Rulesets and `CODEOWNERS` are designed to work together. Under a Ruleset's **"Require a pull request before merging"** rule, you enable **"Require review from Code Owners"**. 

This couples the ruleset's enforcement power with the granular path-to-team mapping defined in the repo's `CODEOWNERS` file. Without the ruleset, the `CODEOWNERS` file simply acts as an advisory reviewer-assignment tool.

#### When Rulesets CAN Replace CODEOWNERS
If your organization uses `CODEOWNERS` solely to **restrict write access** to critical files (e.g., preventing developers from editing GitHub workflows or Terraform configs without security approval), **Repository Rulesets can completely replace `CODEOWNERS` for this use case**.

Rulesets feature a native rule: **"Restrict path additions, modifications, or deletions"**:
1. Define a Ruleset targeting your repositories.
2. Add a path restriction rule for `.github/workflows/*` or `terraform/production/*`.
3. Define a **Bypass List** containing only the `@security-team` or `@devops-team`.
4. Anyone else who attempts to modify these files will have their commit rejected by the GitHub API immediately upon pushing—regardless of whether they have write permissions to the repository.

This is cleaner, more secure, and managed globally (Org-wide) rather than copy-pasting `.github/CODEOWNERS` files into every repository.

### D. Detailed Ruleset Configuration Examples

These configurations represent JSON payloads used in GitHub's REST/GraphQL API or when defining Rulesets via Terraform (`github_organization_ruleset` or `github_repository_ruleset` resources).

#### Example 1: Organization-Wide Production branch protection (Custom Property Driven)
This ruleset automatically binds to all repositories in the organization where the custom property `environment` equals `production`. It protects the `main` or `master` branches from force-pushes, requires two reviews, mandates `CODEOWNERS` approval if the file exists, and requires signed commits.

```json
{
  "name": "Production Branch Guardrails",
  "target": "branch",
  "source_type": "Organization",
  "enforcement": "active",
  "conditions": {
    "repository_properties": {
      "include": [
        {
          "property": "environment",
          "operator": "equals",
          "value": "production"
        }
      ]
    },
    "ref_name": {
      "include": [
        "refs/heads/main",
        "refs/heads/master"
      ],
      "exclude": []
    }
  },
  "bypass_actors": [
    {
      "actor_id": 1,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always",
      "note": "Allows repository administrators to bypass if necessary"
    },
    {
      "actor_id": 54321,
      "actor_type": "Integration",
      "bypass_mode": "always",
      "note": "Allows the central CI/CD deploy bot / GitHub App to bypass"
    }
  ],
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 2,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true
      }
    },
    {
      "type": "required_signatures"
    },
    {
      "type": "deletion"
    },
    {
      "type": "non_fast_forward",
      "note": "Blocks force-pushes"
    }
  ]
}
```

#### Example 2: Hard File-Path Write Protection (Protecting CI/CD and IaC paths)
This ruleset targets all repositories that have security compliance needs (`compliance` equals `pci-dss`). It completely blocks *any* developer from making commits that modify GitHub workflows or central Terraform directories directly, bypassing the need for advisory reviews and enforcing it directly at the push level.

```json
{
  "name": "IaC & Workflow Integrity Protection",
  "target": "branch",
  "source_type": "Organization",
  "enforcement": "active",
  "conditions": {
    "repository_properties": {
      "include": [
        {
          "property": "compliance",
          "operator": "equals",
          "value": "pci-dss"
        }
      ]
    },
    "ref_name": {
      "include": [
        "~ALL"
      ],
      "exclude": []
    }
  },
  "bypass_actors": [
    {
      "actor_id": 9988,
      "actor_type": "Team",
      "bypass_mode": "always",
      "note": "Only the Platform Architect / DevOps Admin team can bypass"
    }
  ],
  "rules": [
    {
      "type": "file_path_restriction",
      "parameters": {
        "restricted_file_paths": [
          ".github/workflows/**/*",
          "infra/terraform/**/*"
        ]
      }
    }
  ]
}
```

---

## Summary Matrix

| Platform | Metadata Type | Access Control Mechanism | Configuration Point | Primary Guardrail |
|---|---|---|---|---|
| **AWS** | Tags | IAM Policy Conditions (`aws:ResourceTag`, `aws:PrincipalTag`) | Root `terragrunt.hcl` & IAM | `aws:RequestTag` & `aws:TagKeys` enforcement |
| **GCP** | Tags (Resource Manager) | IAM Policy Conditions (`resource.matchTag()`) | Resource Manager & IAM | Organization Policy constraints |
| **Kubernetes** | Labels | Validating Admission Policies (VAP), Kyverno policies, Network Policies | K8s API Admission & eBPF | VAP CEL expressions & Cilium policies (Legacy ABAC is deprecated/unusable) |
| **GitHub** | Custom Properties | Repository Rulesets (Branch protections, path restrictions) | Org Settings & Rulesets | Repo metadata lockouts & path-based bypass lists |

