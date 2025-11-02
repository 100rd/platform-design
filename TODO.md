# Platform Design Adaptation TODO

**Goal**: Adapt existing platform to focus on EKS + Karpenter with multi-architecture support

---

## 📊 Component Version Status

### Infrastructure Components

| Component | Current | Latest | Status | Priority |
|-----------|---------|--------|--------|----------|
| Terraform AWS VPC Module | 6.5.0 ✅ | 6.5.0 | ✅ **UPDATED** | - |
| Terraform AWS EKS Module | 21.8.0 ✅ | 21.8.0 | ✅ **UPDATED** | - |
| EKS Cluster Version | 1.34 ✅ | 1.34 | ✅ **FIXED** | - |
| Karpenter Module | Not implemented | v1.1.1 | ❌ MISSING | Critical |
| Karpenter NodePools | Not implemented | v1 | ❌ MISSING | Critical |
| VPC Module | ✅ Implemented | - | ✅ WORKING | - |
| Hetzner Nodes Module | ✅ Implemented | - | ✅ WORKING | - |

### Application Components

| Component | Status | Priority |
|-----------|--------|----------|
| ArgoCD ApplicationSet | ✅ WORKING | - |
| External Secrets Operator | ✅ WORKING | - |
| Generic App Helm Chart | ✅ WORKING | - |
| Network Policies | ✅ WORKING | - |
| Example Services (Go) | ✅ WORKING | - |

### Documentation

| Component | Status | Priority |
|-----------|--------|----------|
| Platform Overview | ✅ Complete | - |
| Tech Stack | ✅ Complete | - |
| Scale Patterns | ✅ Complete | - |
| Terragrunt Strategy | ✅ Complete | - |
| Usage README | ⚠️ BASIC | High |
| Multi-arch Examples | ❌ MISSING | Critical |

---

## Phase 1: Foundation Updates ✅ COMPLETED

### 1.1 Terraform Module Updates

- [x] **Update VPC module** (5.1.1 → 6.5.0) ✅ **COMPLETED 2025-11-02**
  - File: `terraform/modules/vpc/main.tf` line 3
  - Action: Updated version in source declaration
  - Status: Version updated from 5.1.1 to 6.5.0 (latest)
  - Note: Major version update (v5 → v6), breaking changes possible
  - Next: Run `terraform init -upgrade` to download new version

- [x] **Update EKS module** (19.15.3 → 21.8.0) ✅ **COMPLETED 2025-11-02**
  - File: `terraform/modules/eks/main.tf` line 3
  - Action: Major version update completed
  - Status: Version updated from 19.15.3 to 21.8.0 (latest)
  - Note: Two major version jumps (v19 → v20 → v21), review breaking changes
  - Review: [EKS module changelog](https://github.com/terraform-aws-modules/terraform-aws-eks/releases)

- [x] **Fix EKS cluster version** (1.33 → 1.34) ✅ **COMPLETED 2025-11-02**
  - File: `terraform/modules/eks/variables.tf` line 9
  - Previous: `default = "1.33"` (invalid)
  - Updated: `default = "1.34"` (current AWS EKS version)
  - Verified: Version 1.34 is the latest supported by AWS

### 1.2 AWS Provider Audit

- [ ] **Check AWS provider version compatibility** ⏭️ **NEXT STEP**
  - Verify provider version in all modules
  - Ensure compatibility with EKS module v20.31.0
  - Update if needed
  - Recommended: AWS provider >= 5.0

- [ ] **Test IAM role configurations** ⏭️ **RECOMMENDED**
  - Verify IRSA still works with updated modules
  - Test service account creation after deployment
  - Validate IAM policies
  - Note: Test during actual deployment

---

## Phase 2: Karpenter Implementation ❌ MISSING (CRITICAL)

### 2.1 Create Karpenter Terraform Module

- [ ] **Create module directory structure**
  ```
  terraform/modules/karpenter/
  ├── main.tf
  ├── variables.tf
  ├── outputs.tf
  └── README.md
  ```

- [ ] **Implement Karpenter controller installation**
  - Helm provider for Karpenter chart
  - Reference: [Karpenter Getting Started](https://karpenter.sh/docs/getting-started/)
  - Version: v1.1.1 (latest stable)

- [ ] **Configure IAM roles and IRSA**
  - Karpenter controller IAM role
  - Node IAM role with Karpenter policies
  - Trust relationship for OIDC provider
  - EC2 instance profile

- [ ] **Set up service account**
  - Kubernetes service account
  - Annotate with IAM role ARN
  - Namespace: karpenter

- [ ] **Install Karpenter CRDs**
  - NodePool CRD
  - EC2NodeClass CRD
  - NodeClaim CRD

### 2.2 Create Karpenter NodePool Configurations

- [ ] **Create x86 NodePool configuration**
  - File: `terraform/modules/karpenter/nodepools/x86.yaml`
  - Instance families: m6i, c6i, r6i, m7i, c7i
  - Capacity types: spot (80%), on-demand (20%)
  - AMI family: AL2023
  - Consolidation policy: WhenEmptyOrUnderutilized

- [ ] **Create ARM64/Graviton NodePool configuration**
  - File: `terraform/modules/karpenter/nodepools/arm64.yaml`
  - Instance families: m7g, c7g, r7g, m6g, c6g
  - Capacity types: spot (80%), on-demand (20%)
  - AMI family: AL2023
  - Architecture: arm64

- [ ] **Configure NodePool requirements**
  - Resource limits (CPU, memory)
  - Disruption budgets
  - TTL after empty
  - Consolidation settings

- [ ] **Create EC2NodeClass**
  - Security groups
  - Subnet selectors (private subnets)
  - User data for node bootstrap
  - Tags for cost allocation

### 2.3 Integration with Existing Modules

- [ ] **Update EKS module to support Karpenter**
  - Create Karpenter-compatible node role
  - Set up OIDC provider outputs
  - Export cluster details for Karpenter

- [ ] **Remove/deprecate managed node groups**
  - Keep minimal on-demand node group for system pods
  - Let Karpenter handle all application workloads

---

## Phase 3: Multi-Architecture Examples ❌ MISSING (CRITICAL)

### 3.1 Create Directory Structure

- [ ] **Create kubernetes directory**
  ```
  mkdir -p kubernetes/deployments
  mkdir -p kubernetes/docs
  ```

### 3.2 x86 Example Deployment

- [ ] **Create x86-example.yaml**
  - File: `kubernetes/deployments/x86-example.yaml`
  - Include:
    - Deployment with nodeSelector for amd64
    - Service
    - Resource requests/limits
    - Health checks
  - Example workload: nginx or example-api

```yaml
# Preview of what to create:
apiVersion: apps/v1
kind: Deployment
metadata:
  name: x86-example-app
  labels:
    app: x86-example
    architecture: amd64
spec:
  replicas: 3
  selector:
    matchLabels:
      app: x86-example
  template:
    metadata:
      labels:
        app: x86-example
        architecture: amd64
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
        karpenter.sh/capacity-type: spot  # Optional: prefer spot
      containers:
      - name: app
        image: nginx:latest
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

### 3.3 ARM64/Graviton Example Deployment

- [ ] **Create graviton-example.yaml**
  - File: `kubernetes/deployments/graviton-example.yaml`
  - Include:
    - Deployment with nodeSelector for arm64
    - Service
    - Resource requests/limits
    - Health checks
  - Use ARM64-compatible image

```yaml
# Preview of what to create:
apiVersion: apps/v1
kind: Deployment
metadata:
  name: graviton-example-app
  labels:
    app: graviton-example
    architecture: arm64
spec:
  replicas: 3
  selector:
    matchLabels:
      app: graviton-example
  template:
    metadata:
      labels:
        app: graviton-example
        architecture: arm64
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
        karpenter.sh/capacity-type: spot  # Optional: prefer spot
      containers:
      - name: app
        image: nginx:latest  # Automatically pulls ARM64 variant
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

### 3.4 Multi-Architecture Documentation

- [ ] **Create architecture-selection.md**
  - File: `kubernetes/docs/architecture-selection.md`
  - Explain nodeSelector usage
  - Document affinity/anti-affinity patterns
  - Cost comparison (x86 vs Graviton)
  - Performance considerations

- [ ] **Create developer-guide.md**
  - How to choose architecture
  - Building multi-arch images
  - Testing on different architectures
  - Troubleshooting

### 3.5 Update Helm Chart Templates

- [ ] **Add nodeSelector support to generic Helm chart**
  - File: `helm/app/templates/deployment.yaml`
  - Add values.yaml parameter for architecture
  - Document usage in README

```yaml
# Add to helm/app/values.yaml:
nodeSelector:
  kubernetes.io/arch: amd64  # or arm64

# Add to helm/app/templates/deployment.yaml:
{{- if .Values.nodeSelector }}
nodeSelector:
  {{- toYaml .Values.nodeSelector | nindent 8 }}
{{- end }}
```

- [ ] **Add affinity support**
  - Allow advanced scheduling preferences
  - Document in Helm chart README

---

## Phase 4: Documentation & Testing 📝 PLANNED

### 4.1 Comprehensive Usage README

- [ ] **Create detailed deployment guide**
  - Prerequisites checklist
  - Step-by-step setup
  - Variable configuration examples
  - Post-deployment verification

- [ ] **Add developer workflow examples**
  - How to deploy x86 workload
  - How to deploy Graviton workload
  - How to migrate existing workloads
  - Troubleshooting common issues

- [ ] **Document Karpenter usage**
  - How NodePools work
  - How to customize NodePools
  - Monitoring Karpenter
  - Cost optimization tips

- [ ] **Add troubleshooting section**
  - Common deployment issues
  - Karpenter debugging
  - Node provisioning problems
  - Architecture mismatch errors

### 4.2 Testing & Validation

- [ ] **Terraform validation**
  - Run `terraform init` for all modules
  - Run `terraform validate`
  - Run `terraform plan` and review output
  - No errors or warnings

- [ ] **Security scanning**
  - Run Checkov: `checkov -d terraform/`
  - Run tfsec: `tfsec terraform/`
  - Address HIGH/CRITICAL findings
  - Document accepted risks

- [ ] **Cost estimation**
  - Install Infracost
  - Run cost estimation: `infracost breakdown --path terraform/`
  - Compare x86 vs Graviton costs
  - Document savings potential

- [ ] **End-to-end deployment test**
  - Deploy VPC module
  - Deploy EKS cluster
  - Deploy Karpenter
  - Deploy example x86 workload
  - Deploy example Graviton workload
  - Verify both workloads running
  - Clean up resources

---

## Priority Matrix

### Critical (Do First)
1. Fix EKS cluster version (1.33 → 1.31)
2. Create Karpenter Terraform module
3. Create Karpenter NodePool configs (x86 + ARM64)
4. Create example Kubernetes deployments

### High (Do Next)
1. Update EKS module (19.15.3 → 20.31.0)
2. Write comprehensive README
3. Add developer guide documentation
4. End-to-end deployment testing

### Medium (Nice to Have)
1. Update VPC module (5.1.1 → 5.16.0)
2. Update Helm chart with nodeSelector
3. Cost estimation analysis
4. Performance benchmarking

---

## Success Criteria

**When is this adaptation complete?**

- [ ] Terraform deploys working EKS cluster (version 1.31)
- [ ] Karpenter successfully provisions nodes
- [ ] x86 NodePool creates m6i/c6i/r6i instances
- [ ] ARM64 NodePool creates m7g/c7g/r7g instances
- [ ] Example x86 deployment runs on x86 nodes
- [ ] Example Graviton deployment runs on ARM64 nodes
- [ ] README clearly explains how to use the repo
- [ ] Developer guide shows how to select architecture
- [ ] All security scans pass (or risks documented)
- [ ] Cost estimation shows Graviton savings

---

## Quick Start Commands

```bash
# 1. Check current state
cd /Users/lo/Develop/multi-agent-squad/project/platform-design
git status

# 2. Update EKS version
vim terraform/modules/eks/variables.tf
# Change line 9: default = "1.31"

# 3. Create Karpenter module
mkdir -p terraform/modules/karpenter
cd terraform/modules/karpenter
# Create main.tf, variables.tf, outputs.tf

# 4. Create example deployments
mkdir -p kubernetes/deployments
cd kubernetes/deployments
# Create x86-example.yaml
# Create graviton-example.yaml

# 5. Test
cd terraform/
terraform init
terraform validate
terraform plan
```

---

**Last Updated**: 2025-11-02
**Status**: Planning complete, ready for implementation
