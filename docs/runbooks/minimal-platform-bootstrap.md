# minimal-platform Bootstrap Runbook

## Why this stack exists
A minimal 4-unit (vpc/kms/eks/cilium) test stack for validating the EKS+Cilium CNI deployment pattern in staging/eu-central-1. Does not include Karpenter, RDS, monitoring, or other production components.

## Known operational items

### Cluster admin backdoor (HIGH-3 from security review, accepted)
The catalog unit sets `enable_cluster_creator_admin_permissions = true`. This grants permanent cluster-admin access entry to the IAM principal that runs `terragrunt apply` (typically the CI/CD role). Required for first-apply bootstrap because access entries cannot be created without an admin caller.

**Post-deploy cleanup task (MUST be tracked as a follow-up issue):**
1. Confirm SSO-backed access entries (PlatformEngineer, ReadOnlyAccess, DeveloperAccess) work for actual users.
2. Set `enable_cluster_creator_admin_permissions = false` in `catalog/units/minimal-platform-eks/terragrunt.hcl`.
3. Re-apply via CI/CD.
4. Verify the CI/CD role's access entry has been removed by AWS automatically.
5. The cluster will then have only the 3 SSO entries — no permanent admin backdoor.

### KMS allow_destroy = true on minimal-platform-kms
This stack disables IaC-layer KMS deletion protection (variable `allow_destroy = true` in the kms catalog unit). AWS-native protection (deletion_window_in_days = 30) and IAM still apply. This is intentional for a test stack that will be torn down after validation. **Do NOT propagate this setting to platform/ or blockchain/ stacks.**

### Single NAT gateway
`single_nat_gateway = true` for cost optimization. Egress goes via a single AZ; AZ outage causes total egress loss. Acceptable for non-production. See cost analysis in PR description for breakdown.

### VPC flow logs disabled
`enable_flow_log = false` for cost. Test stack only — PCI-DSS retention requirements do not apply. Production stacks (platform/, blockchain/) keep flow logs enabled.

### SSO access entry ARN format
The standard EKS catalog unit uses wildcard ARN suffixes for SSO roles (e.g., `AWSReservedSSO_PlatformEngineer_*`). EKS `CreateAccessEntry` API does not support wildcards. Pre-existing issue across all EKS units in the repo — tracked separately. The first apply will likely fail on the access entries; manual ARN substitution may be required for first-apply bootstrap.
