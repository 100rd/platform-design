# ---------------------------------------------------------------------------------------------------------------------
# GCP GPU Video Analysis Stack Template (WS-A — ml-infra)
# ---------------------------------------------------------------------------------------------------------------------
# Composable, multi-region stack that deploys the GCP GPU ML analysis platform.
#
# Per region:
#   gcp-gpu-vpc → gcp-gpu-gke → gcp-gpu-nodepools
#                            ↘ gke-gpu-operator      (NVIDIA GPU Operator)
#                            ↘ gke-gpu-dcgm          (DCGM metrics → VictoriaMetrics)
#                            ↘ gke-gpu-scheduling    (Volcano batch scheduler, ADR-0036)
#
# Region-independent (deployed once):
#   gcp-billing-budget        (80/100/120% budget → Pub/Sub → Alertmanager)
#
# Multi-region: region names are parameterised via locals. Each per-region unit is
# placed under <region>/<unit> and receives a `values.region`. The stack ships two
# regions (primary + secondary); add a third region by copying the per-region unit
# block group and pointing it at local.tertiary_region. terragrunt v0.99.5 does not
# support for_each on unit blocks, so regions are expressed as explicit blocks.
#
# Usage (from live tree):
#   cd terragrunt/gcp-staging/gpu-analysis
#   terragrunt stack generate
#   terragrunt stack run plan
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Regions the GPU analysis platform spans (≥2). Adjust to taste.
  primary_region   = "europe-west9"
  secondary_region = "us-central1"
}

# ---------------------------------------------------------------------------------------------------------------------
# Region-independent: a single billing budget covering the GPU project(s).
# ---------------------------------------------------------------------------------------------------------------------

unit "gcp-billing-budget" {
  source = "${get_repo_root()}/catalog/units/gcp-billing-budget"
  path   = "gcp-billing-budget"
}

# ---------------------------------------------------------------------------------------------------------------------
# Primary region — full GPU analysis stack.
# ---------------------------------------------------------------------------------------------------------------------

unit "gcp-gpu-vpc-primary" {
  source = "${get_repo_root()}/catalog/units/gcp-gpu-vpc"
  path   = "${local.primary_region}/gcp-gpu-vpc"
  values = {
    region = local.primary_region
  }
}

unit "gcp-gpu-gke-primary" {
  source = "${get_repo_root()}/catalog/units/gcp-gpu-gke"
  path   = "${local.primary_region}/gcp-gpu-gke"
  values = {
    region = local.primary_region
  }
}

unit "gcp-gpu-nodepools-primary" {
  source = "${get_repo_root()}/catalog/units/gcp-gpu-nodepools"
  path   = "${local.primary_region}/gcp-gpu-nodepools"
  values = {
    region = local.primary_region
  }
}

unit "gke-gpu-operator-primary" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-operator"
  path   = "${local.primary_region}/gke-gpu-operator"
  values = {
    region = local.primary_region
  }
}

unit "gke-gpu-dcgm-primary" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-dcgm"
  path   = "${local.primary_region}/gke-gpu-dcgm"
  values = {
    region = local.primary_region
  }
}

unit "gke-gpu-scheduling-primary" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-scheduling"
  path   = "${local.primary_region}/gke-gpu-scheduling"
  values = {
    region = local.primary_region
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Secondary region — full GPU analysis stack.
# ---------------------------------------------------------------------------------------------------------------------

unit "gcp-gpu-vpc-secondary" {
  source = "${get_repo_root()}/catalog/units/gcp-gpu-vpc"
  path   = "${local.secondary_region}/gcp-gpu-vpc"
  values = {
    region = local.secondary_region
  }
}

unit "gcp-gpu-gke-secondary" {
  source = "${get_repo_root()}/catalog/units/gcp-gpu-gke"
  path   = "${local.secondary_region}/gcp-gpu-gke"
  values = {
    region = local.secondary_region
  }
}

unit "gcp-gpu-nodepools-secondary" {
  source = "${get_repo_root()}/catalog/units/gcp-gpu-nodepools"
  path   = "${local.secondary_region}/gcp-gpu-nodepools"
  values = {
    region = local.secondary_region
  }
}

unit "gke-gpu-operator-secondary" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-operator"
  path   = "${local.secondary_region}/gke-gpu-operator"
  values = {
    region = local.secondary_region
  }
}

unit "gke-gpu-dcgm-secondary" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-dcgm"
  path   = "${local.secondary_region}/gke-gpu-dcgm"
  values = {
    region = local.secondary_region
  }
}

unit "gke-gpu-scheduling-secondary" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-scheduling"
  path   = "${local.secondary_region}/gke-gpu-scheduling"
  values = {
    region = local.secondary_region
  }
}
