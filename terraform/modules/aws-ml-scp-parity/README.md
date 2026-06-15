# Module: `aws-ml-scp-parity`

> **ADRs:** [0044](../../../docs/adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md)
> (greenfield AWS EKS GPU ML foundation), [0048](../../../docs/adrs/0048-aws-ml-cicd-registry-drift.md)
> (AWS-native ML backends). Mirrors the GCP org-policy deny-list plane in
> [0040](../../../docs/adrs/0040-soc-posture-and-oncall.md) D1 onto AWS Service Control
> Policies, scoped to the GPU/ML OU. Taxonomy per
> [0028](../../../docs/adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md).

WS-E SCP-parity plane for the **greenfield AWS GPU/ML account**. The org-wide
`terraform/modules/scps` already enforces broad root-level controls (deny public S3,
require EBS encryption, restrict regions, deny CloudTrail/GuardDuty changes). This
module **narrows further for the net-new ML estate**, attaching ML-OU-scoped SCPs that
the broad module does not cover, so the greenfield `aws-eks-gpu-*` / `aws-ml-*` workloads
inherit the same preventive guardrails as the rest of the org.

## Apply-gated / default-OFF

**With default inputs, `terraform plan` creates ZERO resources.** Every SCP and every
attachment is gated by `var.enabled` (master, default `false`) **and** a per-policy
toggle. SCPs are organization-wide and high-blast-radius; enabling requires an explicit
human apply + blast-radius review (project `critical-decisions` / `terraform` rules).
Attachments target `var.ml_target_ou_ids` (the GPU/ML OU) **only** — never the org root.

## SCPs (each AWS analog of a GCP org-policy constraint, ADR-0040 D1)

| SCP | AWS deny | GCP analog (ADR-0040) | SOC2 | Toggle |
|---|---|---|---|---|
| `require_imdsv2` | `ec2:RunInstances` unless IMDSv2 (`HttpTokens=required`) | (GPU-node SSRF hardening) | CC6.1 | `require_imdsv2` |
| `require_ebs_encryption` | `ec2:CreateVolume` with `Encrypted=false` | `gcp.restrictNonCmekServices` | CC6.1 | `require_ebs_encryption` |
| `deny_access_keys` | `iam:CreateAccessKey` (force Pod Identity / STS) | `iam.disableServiceAccountKeyCreation` | CC6.1 / CC6.3 | `deny_long_lived_access_keys` |
| `restrict_regions` | resource creation outside `allowed_gpu_regions` (Terraform role exempt) | `gcp.resourceLocations` | C1.1 | `restrict_gpu_regions` |

## ABAC / least-privilege note

The region-restriction SCP exempts the Terraform execution role
(`var.terraform_role_name_pattern`) via an `ArnNotLike` condition so it can reach global
services (IAM/STS/Route53) during ML-stack provisioning — the same exemption philosophy
as `terraform/modules/scps`. Workload-level least-privilege + the ABAC
`aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system` condition live in
the companion `aws-ml-abac-iam` module.

## ADR-0028 taxonomy

`aws_organizations_policy` is taggable; every SCP carries `var.tags` (defaults
`platform:system=security`, `platform:component=scp-parity`, `platform:owner=team-sec`,
`platform:managed-by=terragrunt`). The `platform_tags` output surfaces them for
provenance and the SOC2 evidence matrix.

## Validation (plan/validate-only)

`terraform fmt`, `terraform init -backend=false`, `terraform validate`, and
`terraform test` (mocked `aws` provider, **4/4 pass**). **No `terraform apply`, no SCP
created or attached** at plan/validate time. `terraform plan` against real AWS needs org
credentials and is run only from CI on `main` after merge, behind the apply gate.
