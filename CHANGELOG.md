# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- **Karpenter Integration**: Full implementation using EKS module v21 built-in submodule
  - Karpenter submodule configuration in EKS module
  - Pod Identity integration (replaces IRSA in v21)
  - Automatic IAM role creation for controller and nodes
  - SQS queue and EventBridge rules for spot termination handling
  - Security group and subnet discovery tags

- **Multi-Architecture Node Pools**:
  - x86/amd64 NodePool with Intel/AMD instance families (m6i, m7i, c6i, c7i, r6i, r7i)
  - ARM64/Graviton NodePool with cost-optimized Graviton instances (m7g, c7g, r7g, m6g, c6g, r6g)
  - Spot + On-Demand capacity mix (80/20 for x86, 90/10 for ARM64)
  - Automated consolidation policies

- **Example Kubernetes Deployments**:
  - x86 example: nginx deployment with HPA and architecture-specific scheduling
  - ARM64 Graviton example: cost-optimized nginx with 20-40% savings potential
  - Both examples include custom HTML pages showing architecture details
  - PodDisruptionBudgets and anti-affinity rules

- **Karpenter Helm Installation**:
  - Terraform example for Helm chart deployment (`terraform/karpenter-helm.tf`)
  - Complete Helm values configuration
  - CRD installation examples

- **Documentation**:
  - Comprehensive README with platform explanation and component status
  - TODO.md with detailed adaptation roadmap
  - CHANGELOG.md to track version updates

### Changed
- **BREAKING**: Updated Terraform AWS EKS module from v19.15.3 to v21.8.0
  - This is a **TWO major version update** (v19 → v20 → v21) that contains breaking changes
  - Review [EKS module changelog](https://github.com/terraform-aws-modules/terraform-aws-eks/releases) before deployment
  - Requires Terraform >= 1.3
  - Output names and structure may have changed significantly
  - IAM policies have been updated
  - Node group configuration syntax updated

- **BREAKING**: Updated Terraform AWS VPC module from v5.1.1 to v6.5.0
  - Major version update (v5 → v6), breaking changes possible
  - Includes significant improvements and refactoring
  - Review [VPC module changelog](https://github.com/terraform-aws-modules/terraform-aws-vpc/releases) before deployment

- **CRITICAL FIX**: Corrected EKS cluster version from "1.33" (invalid) to "1.34"
  - Previous default version 1.33 does not exist in AWS EKS
  - Version 1.34 is the latest stable EKS version as of November 2025
  - Prevents deployment failures

### Migration Notes

#### For Existing Deployments

If you have existing infrastructure deployed with the old module versions:

1. **Backup your state file** before upgrading:
   ```bash
   terraform state pull > backup-state-$(date +%Y%m%d-%H%M%S).json
   ```

2. **Review the EKS module v20 migration guide**:
   - Check for breaking changes in outputs
   - Verify IAM role configurations
   - Test in non-production environment first

3. **Update Terraform modules**:
   ```bash
   terraform init -upgrade
   terraform plan
   ```

4. **Review the plan carefully** before applying:
   - Check for any resource replacements
   - Verify no unexpected changes
   - Ensure node groups won't be destroyed/recreated

#### For New Deployments

Simply use the updated modules:
```bash
cd terraform/modules
terraform init
terraform plan
terraform apply
```

### Compatibility

- **Terraform**: >= 1.3.0 (required by EKS module v21)
- **AWS Provider**: >= 5.70 (recommended for EKS v21)
- **Kubernetes**: 1.34 (default cluster version)

---

## [2025-11-02 Phase 2] - Karpenter Implementation

### Summary
Phase 2 of platform adaptation completed. Implemented Karpenter autoscaling with multi-architecture support (x86 and ARM64/Graviton) using the built-in EKS module v21 Karpenter submodule.

### Added

**Terraform Modules:**
- `terraform/modules/eks/main.tf`: Karpenter submodule integration
  - Pod Identity configuration (EKS v21+ feature)
  - Dedicated Karpenter controller node group
  - Cluster addons: vpc-cni, coredns, kube-proxy, eks-pod-identity-agent
  - Security group tags for Karpenter discovery

- `terraform/modules/vpc/main.tf`: Karpenter subnet discovery tags
  - Private subnets tagged with `karpenter.sh/discovery`
  - Public subnets tagged for ELB integration

- `terraform/karpenter-helm.tf`: Helm chart installation example
  - Complete Helm values configuration
  - ECR Public authentication
  - Controller resource limits and replicas
  - Webhook and PDB configuration

**Kubernetes Manifests:**
- `kubernetes/karpenter/x86-nodepool.yaml`:
  - EC2NodeClass for x86 architecture
  - NodePool with Intel/AMD instance families (m6i, m6a, m7i, m7a, c6i, c6a, c7i, c7a, r6i, r6a, r7i, r7a)
  - 80% spot, 20% on-demand capacity mix
  - Consolidation after 30s
  - CPU limits: up to 1000 cores

- `kubernetes/karpenter/arm64-nodepool.yaml`:
  - EC2NodeClass for ARM64 Graviton
  - NodePool with Graviton instance families (m7g, c7g, r7g, m6g, c6g, r6g, t4g)
  - 90% spot, 10% on-demand for maximum cost savings
  - Graviton2 and Graviton3 support
  - 20-40% cost savings vs x86

**Example Deployments:**
- `kubernetes/deployments/x86-example.yaml`:
  - Nginx deployment with x86 node selector
  - HorizontalPodAutoscaler (3-10 replicas)
  - Custom HTML showing x86 architecture details
  - PodAntiAffinity for multi-AZ distribution

- `kubernetes/deployments/arm64-graviton-example.yaml`:
  - Nginx deployment with ARM64 node selector
  - HorizontalPodAutoscaler (5-20 replicas)
  - PodDisruptionBudget for availability
  - Cost savings information in HTML

### Changed

**EKS Module:**
- Replaced traditional managed node groups with Karpenter-managed infrastructure
- Single "karpenter" node group for controller pods only (tainted with `CriticalAddonsOnly`)
- All application workloads now managed by Karpenter
- Added authentication_mode = "API_AND_CONFIG_MAP" for v21

**VPC Module:**
- Added `cluster_name` variable for Karpenter discovery
- Added `private_subnet_tags` and `public_subnet_tags` variables
- Automatic tagging of subnets for Karpenter and ELB

**Variables:**
- Removed `ondemand_*` and `spot_*` node group variables
- Added `karpenter_controller_*` variables
- Added `karpenter_node_iam_role_additional_policies` map

**Outputs:**
- Added `oidc_provider_arn` for IRSA compatibility
- Added `node_security_group_id` for Karpenter
- Added `karpenter_queue_name` for interruption handling
- Added `karpenter_node_iam_role_name` and `karpenter_node_iam_role_arn`
- Added `karpenter_instance_profile_name`

### Features

**Karpenter Benefits:**
- Sub-minute node provisioning
- Automatic bin-packing and consolidation
- Native spot termination handling
- Multi-architecture support (x86 + ARM64)
- 30%+ cost savings with consolidation
- 20-40% additional savings with Graviton

**Architecture Support:**
- **x86/amd64**: Intel and AMD processors across c, m, r families
- **ARM64**: AWS Graviton2 and Graviton3 processors
- **Multi-arch images**: Automatic architecture selection

**Capacity Management:**
- Mixed spot and on-demand instances
- Configurable spot/on-demand ratios
- Automated node consolidation
- Disruption budgets

### Files Modified
- `terraform/modules/eks/main.tf` - Complete rewrite for Karpenter
- `terraform/modules/eks/variables.tf` - New Karpenter variables
- `terraform/modules/eks/outputs.tf` - Added Karpenter outputs
- `terraform/modules/vpc/main.tf` - Added subnet tags
- `terraform/modules/vpc/variables.tf` - Added tag variables

### Files Created
- `terraform/karpenter-helm.tf` - Helm installation example
- `kubernetes/karpenter/x86-nodepool.yaml` - x86 NodePool
- `kubernetes/karpenter/arm64-nodepool.yaml` - ARM64 NodePool
- `kubernetes/deployments/x86-example.yaml` - x86 deployment example
- `kubernetes/deployments/arm64-graviton-example.yaml` - ARM64 deployment example

### Testing Required
- [ ] Deploy VPC with cluster_name parameter
- [ ] Deploy EKS with Karpenter submodule
- [ ] Install Karpenter Helm chart
- [ ] Apply x86 NodePool manifest
- [ ] Apply ARM64 NodePool manifest
- [ ] Deploy x86 example application
- [ ] Deploy ARM64 example application
- [ ] Verify pods schedule on correct architecture
- [ ] Test node consolidation
- [ ] Verify spot termination handling

### Documentation Updated
- README.md - Updated with Karpenter implementation status
- TODO.md - Phase 2 marked complete
- CHANGELOG.md - This entry

---

## [2025-11-02 Phase 1] - Foundation Updates

### Summary
Phase 1 of the platform adaptation completed. Updated core Terraform modules to latest stable versions and fixed invalid EKS cluster version.

### Changed
- Updated VPC module: 5.1.1 → 6.5.0 (major version v5 → v6)
- Updated EKS module: 19.15.3 → 21.8.0 (two major versions v19 → v21)
- Fixed EKS cluster version: 1.33 (invalid) → 1.34 (latest)

### Files Modified
- `terraform/modules/vpc/main.tf` (line 3)
- `terraform/modules/eks/main.tf` (line 3)
- `terraform/modules/eks/variables.tf` (line 9)

### Testing Required
- [ ] Run `terraform init -upgrade` in module directories
- [ ] Execute `terraform plan` and review output
- [ ] Verify no unexpected resource changes
- [ ] Test in development environment before production
- [ ] Validate IRSA (IAM Roles for Service Accounts) still works
- [ ] Confirm node groups provision correctly

### Known Issues
None at this time. Module updates are code-only changes; actual infrastructure testing pending.

---

## [Initial] - Casino Platform Reference Architecture

### Added
- Complete casino gaming platform with blockchain integration
- AWS EKS cluster infrastructure with Terraform
- VPC with multi-AZ public/private subnets
- Managed node groups (on-demand and spot)
- ArgoCD GitOps deployment pipeline
- Helm charts for multi-team applications
- Kubernetes network policies (Cilium)
- Example Go microservices
- GitHub Actions CI/CD workflows
- Security scanning (Checkov, Trivy)
- External Secrets Operator integration
- Hetzner bare metal node integration
- Comprehensive documentation:
  - Platform overview
  - Tech stack rationale
  - Terragrunt strategy
  - Scale patterns (1k-5k nodes)

### Infrastructure Components
- VPC Module (Terraform AWS v5.1.1) ⬆️ now v5.16.0
- EKS Module (Terraform AWS v19.15.3) ⬆️ now v20.31.0
- Hetzner Nodes Module (custom)

### Application Components
- ArgoCD ApplicationSet for GitOps
- External Secrets Operator
- Generic Helm chart template
- Network policies (default-deny, DNS, same-namespace)
- Example services (example-api, hello-world)

### Documentation
- Platform overview and architecture
- Technology stack documentation
- Terragrunt multi-environment strategy
- Scale patterns for 1,000-5,000 nodes

---

## Upcoming Changes

### Phase 2: Karpenter Implementation (CRITICAL - In Planning)
- [ ] Create Karpenter Terraform module
- [ ] Configure IAM roles and IRSA for Karpenter
- [ ] Create x86 NodePool configuration
- [ ] Create ARM64/Graviton NodePool configuration
- [ ] Integrate with EKS module
- [ ] Add consolidation policies

### Phase 3: Multi-Architecture Examples (CRITICAL - In Planning)
- [ ] Create `kubernetes/deployments/` directory
- [ ] Add x86 example deployment manifest
- [ ] Add Graviton example deployment manifest
- [ ] Document architecture selection patterns
- [ ] Update Helm charts with nodeSelector support

### Phase 4: Documentation & Testing (In Planning)
- [ ] Write comprehensive usage README
- [ ] Create developer guide for multi-arch deployments
- [ ] Add troubleshooting documentation
- [ ] Perform end-to-end deployment testing
- [ ] Run security scans (Checkov, tfsec)
- [ ] Generate cost estimates (Infracost)

---

## Version History

- **[2025-11-02]**: Phase 1 Complete - Updated VPC and EKS modules to latest versions
- **[Initial]**: Casino platform reference architecture with EKS, managed node groups, and GitOps

---

## Breaking Changes

### v21.8.0 EKS Module (2025-11-02)

The EKS module update from v19.15.3 to v21.8.0 is a **TWO major version** change (v19 → v20 → v21) and includes significant breaking changes:

**Potential Breaking Changes:**
1. **Output Names**: Some output names may have changed
   - Check `outputs.tf` if you reference module outputs
   - Common: `cluster_security_group_id`, `node_security_group_id`

2. **IAM Policies**: IAM role policies have been updated
   - IRSA (IAM Roles for Service Accounts) configuration may need adjustment
   - Review IAM permissions after upgrade

3. **Node Group Configuration**: Managed node group syntax may have changed
   - Current config should work but review for deprecations
   - New options may be available

4. **Terraform Version**: Now requires Terraform >= 1.3
   - Upgrade Terraform if using older version

**Recommended Actions:**
- Test in non-production environment first
- Review EKS module changelog thoroughly
- Back up Terraform state before applying
- Plan carefully and review all changes

### v6.5.0 VPC Module (2025-11-02)

The VPC module update from v5.1.1 to v6.5.0 is a **major version** change:

**Expected Impact:** Medium to High
- Major version change (v5 → v6) may include breaking changes
- Review [VPC module v6 migration guide](https://github.com/terraform-aws-modules/terraform-aws-vpc/releases/tag/v6.0.0)
- Variable names or output formats may have changed
- Test thoroughly before production deployment

---

**For questions or issues, please refer to:**
- [TODO.md](TODO.md) - Detailed implementation roadmap
- [README.md](README.md) - Platform overview and getting started
- [Terraform AWS EKS Module](https://github.com/terraform-aws-modules/terraform-aws-eks)
- [Terraform AWS VPC Module](https://github.com/terraform-aws-modules/terraform-aws-vpc)
