# ---------------------------------------------------------------------------------------------------------------------
# AWS GPU Analysis Stack — multi-region AWS EKS GPU ML platform (WS-A owns this file)
# ---------------------------------------------------------------------------------------------------------------------
# The composing stack for the greenfield AWS EKS GPU ML platform. Mirrors
# catalog/stacks/gcp-gpu-analysis. WS-A OWNS this file and scaffolds references to ALL
# planned units across WS-A..F so sibling-WS PRs add their modules/apps without ever
# editing this stack (file-disjoint, parallel-mergeable PRs).
#
# Per region (primary + secondary, ADR-0044 D5):
#   aws-eks-gpu-vpc → aws-eks-gpu → aws-eks-gpu-nodepools          (WS-A foundation/nodes)
#                                 ↘ aws-eks-gpu-operator           (WS-A, NVIDIA GPU Operator)
#                                 ↘ aws-eks-gpu-dcgm               (WS-A, DCGM telemetry)
#                                 ↘ aws-eks-gpu-scheduling         (WS-A, Volcano + DRA)
#                                 ↘ aws-eks-efa-fabric             (WS-A, EFA fabric)
#                                 ↘ aws-eks-managed-nodegroup      (WS-A, reserved EFA-DRA training)
#                                 ↘ aws-eks-inference-gateway      (WS-A, serving front + WAF)
#                                 ↘ aws-ml-artifact-store          (WS-B, S3 + ABAC)            [planned]
#
# Region-independent (deployed once):
#   aws-eks-gpu-budget    (WS-A, 80/100/120% + FORECASTED → SNS → Alertmanager — account-scoped)
#
# EVERYTHING IS DEFAULT-OFF (each unit gates on gpu_platform_config.enabled in
# account.hcl). `terragrunt stack generate` then `stack run plan` is plan/validate-only;
# apply is CI-gated from main after human review (never from an agent or a feature branch).
#
# Multi-region: regions are explicit blocks (terragrunt does not support for_each on unit
# blocks). The stack ships primary + secondary (ADR-0044 D5); the secondary runs
# scale-to-zero serving only (no hot training mirror). Add a third region by copying a
# per-region block group.
#
# NOTE on cross-WS units: the WS-B..F unit sources below are SCAFFOLDED references to the
# paths those workstreams will create (catalog/units/aws-ml-*, etc.). They are wired here,
# default-OFF, so sibling PRs never touch this stack. Until a sibling WS lands its unit,
# leave its toggle off (the default) — `stack generate` only materialises enabled units.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # AWS regions the GPU ML platform spans (>= 2, ADR-0044 D5). Single-region-first is a
  # phasing choice (plan §7 #6) — the secondary stays apply-gated until its region is brought up.
  primary_region   = "eu-west-1"
  secondary_region = "us-east-1"
}

# =====================================================================================================================
# REGION-INDEPENDENT (deployed once)
# =====================================================================================================================

# WS-A — GPU cost guardrail (reuses the budgets module). Account-scoped, filters by service.
unit "aws-eks-gpu-budget" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-budget"
  path   = "aws-eks-gpu-budget"
}

# =====================================================================================================================
# PRIMARY REGION — full GPU ML stack
# =====================================================================================================================

# --- WS-A: foundation + nodes + fabric + serving ---------------------------------------------------------------------

unit "aws-eks-gpu-vpc-primary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-vpc"
  path   = "${local.primary_region}/aws-eks-gpu-vpc"
  values = { region = local.primary_region }
}

unit "aws-eks-gpu-primary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu"
  path   = "${local.primary_region}/aws-eks-gpu"
  values = { region = local.primary_region }
}

unit "aws-eks-gpu-nodepools-primary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-nodepools"
  path   = "${local.primary_region}/aws-eks-gpu-nodepools"
  values = { region = local.primary_region }
}

unit "aws-eks-gpu-operator-primary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-operator"
  path   = "${local.primary_region}/aws-eks-gpu-operator"
  values = { region = local.primary_region }
}

unit "aws-eks-gpu-dcgm-primary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-dcgm"
  path   = "${local.primary_region}/aws-eks-gpu-dcgm"
  values = { region = local.primary_region }
}

unit "aws-eks-gpu-scheduling-primary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-scheduling"
  path   = "${local.primary_region}/aws-eks-gpu-scheduling"
  values = { region = local.primary_region }
}

unit "aws-eks-efa-fabric-primary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-efa-fabric"
  path   = "${local.primary_region}/aws-eks-efa-fabric"
  values = { region = local.primary_region }
}

# Reserved EFA-DRA training node group — OFF unless reserved_training_enabled (scarce/expensive).
unit "aws-eks-managed-nodegroup-primary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-managed-nodegroup"
  path   = "${local.primary_region}/aws-eks-managed-nodegroup"
  values = { region = local.primary_region }
}

# Serving front — Envoy Gateway + InferencePool/InferenceObjective + EPP + AWS WAF (ADR-0047).
unit "aws-eks-inference-gateway-primary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-inference-gateway"
  path   = "${local.primary_region}/aws-eks-inference-gateway"
  values = { region = local.primary_region }
}

# --- WS-B: ML CI/CD artifact store (S3 + Pod-Identity/ABAC) — SCAFFOLDED, owned by WS-B ------------------------------
# WS-B will create catalog/units/aws-ml-artifact-store. Wired here default-OFF so its PR
# does not touch this stack. (terragrunt stack generate skips unmaterialised/OFF units.)
unit "aws-ml-artifact-store-primary" {
  source = "${get_repo_root()}/catalog/units/aws-ml-artifact-store"
  path   = "${local.primary_region}/aws-ml-artifact-store"
  values = { region = local.primary_region }
}

# =====================================================================================================================
# SECONDARY REGION — scale-to-zero serving (no hot training mirror, ADR-0044 D5)
# =====================================================================================================================

unit "aws-eks-gpu-vpc-secondary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-vpc"
  path   = "${local.secondary_region}/aws-eks-gpu-vpc"
  values = { region = local.secondary_region }
}

unit "aws-eks-gpu-secondary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu"
  path   = "${local.secondary_region}/aws-eks-gpu"
  values = { region = local.secondary_region }
}

unit "aws-eks-gpu-nodepools-secondary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-nodepools"
  path   = "${local.secondary_region}/aws-eks-gpu-nodepools"
  values = { region = local.secondary_region }
}

unit "aws-eks-gpu-operator-secondary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-operator"
  path   = "${local.secondary_region}/aws-eks-gpu-operator"
  values = { region = local.secondary_region }
}

unit "aws-eks-gpu-dcgm-secondary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-dcgm"
  path   = "${local.secondary_region}/aws-eks-gpu-dcgm"
  values = { region = local.secondary_region }
}

unit "aws-eks-gpu-scheduling-secondary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-gpu-scheduling"
  path   = "${local.secondary_region}/aws-eks-gpu-scheduling"
  values = { region = local.secondary_region }
}

unit "aws-eks-efa-fabric-secondary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-efa-fabric"
  path   = "${local.secondary_region}/aws-eks-efa-fabric"
  values = { region = local.secondary_region }
}

# Secondary serving front for cross-region failover (Route 53 via failover-controller).
unit "aws-eks-inference-gateway-secondary" {
  source = "${get_repo_root()}/catalog/units/aws-eks-inference-gateway"
  path   = "${local.secondary_region}/aws-eks-inference-gateway"
  values = { region = local.secondary_region }
}
