# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal GPU Analysis Stack Template (WS-A — ml-infra) — ADR-0049..0054
# ---------------------------------------------------------------------------------------------------------------------
# The bare-metal analogue of gcp-gpu-analysis: composes the owned Talos GPU ML platform
# across TWO UK datacenters (primary + standby), placed under the live tree at
# terragrunt/uk/{primary,standby}/platform/ (the path docs/transaction-analytics/
# 06-uk-datacenters.md already names).
#
# WS-A OWNS THIS FILE. It scaffolds references to ALL planned units across WS-A..F so
# sibling-workstream PRs (WS-B..F) never edit this stack — they only ship their unit/module
# and flip its default-OFF toggle in the live tree's baremetal_config. WS-B/E units are
# scaffolded as commented blocks below (their catalog units don't exist yet; uncomment the
# block AND add the unit dir in that WS's PR). Everything is APPLY-GATED / default-OFF: each
# unit's `enabled` resolves from baremetal_config and defaults false, so `stack generate` +
# `run plan` create nothing real.
#
# Internal WS-A order is load-bearing (unlike the GCP plan where the cluster pre-existed):
#   talos-machineconfig → talos-cluster        (control plane + etcd; gates everything)
#     → baremetal-cilium-lb                     (CNI before workloads)
#     → baremetal-rook-ceph                     (storage before stateful ML; rbd+ceph prereq)
#     → talos-gpu-nodepool                      (fixed GPU pool)
#     → baremetal-gpu-operator → -dcgm → -scheduling → -fabric   (GPU stack)
#     → baremetal-ingress-waf                   (serving front)
# Cross-unit data flows through `dependency` blocks with mock_outputs (kubeconfig/endpoint
# from talos-cluster; ceph kernel modules from talos-machineconfig).
#
# Usage (from the live tree):
#   cd terragrunt/uk/primary/platform   # (or standby)
#   terragrunt stack generate
#   terragrunt run --all plan           # plan only — apply is CI/CD from main, never here
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # The two UK datacenters the platform spans (primary-active + standby-hot-standby).
  primary_dc = "primary"
  standby_dc = "standby"
}

# =====================================================================================================================
# PRIMARY DC — full WS-A Talos GPU stack (sized for 100% steady state).
# =====================================================================================================================

unit "talos-machineconfig-primary" {
  source = "${get_repo_root()}/catalog/units/talos-machineconfig"
  path   = "${local.primary_dc}/talos-machineconfig"
  values = { dc = local.primary_dc }
}

unit "talos-cluster-primary" {
  source = "${get_repo_root()}/catalog/units/talos-cluster"
  path   = "${local.primary_dc}/talos-cluster"
  values = { dc = local.primary_dc }
}

unit "baremetal-cilium-lb-primary" {
  source = "${get_repo_root()}/catalog/units/baremetal-cilium-lb"
  path   = "${local.primary_dc}/baremetal-cilium-lb"
  values = { dc = local.primary_dc }
}

unit "baremetal-rook-ceph-primary" {
  source = "${get_repo_root()}/catalog/units/baremetal-rook-ceph"
  path   = "${local.primary_dc}/baremetal-rook-ceph"
  values = { dc = local.primary_dc }
}

unit "talos-gpu-nodepool-primary" {
  source = "${get_repo_root()}/catalog/units/talos-gpu-nodepool"
  path   = "${local.primary_dc}/talos-gpu-nodepool"
  values = { dc = local.primary_dc }
}

unit "baremetal-gpu-operator-primary" {
  source = "${get_repo_root()}/catalog/units/baremetal-gpu-operator"
  path   = "${local.primary_dc}/baremetal-gpu-operator"
  values = { dc = local.primary_dc }
}

unit "baremetal-gpu-dcgm-primary" {
  source = "${get_repo_root()}/catalog/units/baremetal-gpu-dcgm"
  path   = "${local.primary_dc}/baremetal-gpu-dcgm"
  values = { dc = local.primary_dc }
}

unit "baremetal-gpu-scheduling-primary" {
  source = "${get_repo_root()}/catalog/units/baremetal-gpu-scheduling"
  path   = "${local.primary_dc}/baremetal-gpu-scheduling"
  values = { dc = local.primary_dc }
}

unit "baremetal-gpu-fabric-primary" {
  source = "${get_repo_root()}/catalog/units/baremetal-gpu-fabric"
  path   = "${local.primary_dc}/baremetal-gpu-fabric"
  values = { dc = local.primary_dc }
}

unit "baremetal-ingress-waf-primary" {
  source = "${get_repo_root()}/catalog/units/baremetal-ingress-waf"
  path   = "${local.primary_dc}/baremetal-ingress-waf"
  values = { dc = local.primary_dc }
}

# =====================================================================================================================
# STANDBY DC — full WS-A Talos GPU stack (~40% capacity; sized to absorb failover serving).
# =====================================================================================================================

unit "talos-machineconfig-standby" {
  source = "${get_repo_root()}/catalog/units/talos-machineconfig"
  path   = "${local.standby_dc}/talos-machineconfig"
  values = { dc = local.standby_dc }
}

unit "talos-cluster-standby" {
  source = "${get_repo_root()}/catalog/units/talos-cluster"
  path   = "${local.standby_dc}/talos-cluster"
  values = { dc = local.standby_dc }
}

unit "baremetal-cilium-lb-standby" {
  source = "${get_repo_root()}/catalog/units/baremetal-cilium-lb"
  path   = "${local.standby_dc}/baremetal-cilium-lb"
  values = { dc = local.standby_dc }
}

unit "baremetal-rook-ceph-standby" {
  source = "${get_repo_root()}/catalog/units/baremetal-rook-ceph"
  path   = "${local.standby_dc}/baremetal-rook-ceph"
  values = { dc = local.standby_dc }
}

unit "talos-gpu-nodepool-standby" {
  source = "${get_repo_root()}/catalog/units/talos-gpu-nodepool"
  path   = "${local.standby_dc}/talos-gpu-nodepool"
  values = { dc = local.standby_dc }
}

unit "baremetal-gpu-operator-standby" {
  source = "${get_repo_root()}/catalog/units/baremetal-gpu-operator"
  path   = "${local.standby_dc}/baremetal-gpu-operator"
  values = { dc = local.standby_dc }
}

unit "baremetal-gpu-dcgm-standby" {
  source = "${get_repo_root()}/catalog/units/baremetal-gpu-dcgm"
  path   = "${local.standby_dc}/baremetal-gpu-dcgm"
  values = { dc = local.standby_dc }
}

unit "baremetal-gpu-scheduling-standby" {
  source = "${get_repo_root()}/catalog/units/baremetal-gpu-scheduling"
  path   = "${local.standby_dc}/baremetal-gpu-scheduling"
  values = { dc = local.standby_dc }
}

unit "baremetal-gpu-fabric-standby" {
  source = "${get_repo_root()}/catalog/units/baremetal-gpu-fabric"
  path   = "${local.standby_dc}/baremetal-gpu-fabric"
  values = { dc = local.standby_dc }
}

unit "baremetal-ingress-waf-standby" {
  source = "${get_repo_root()}/catalog/units/baremetal-ingress-waf"
  path   = "${local.standby_dc}/baremetal-ingress-waf"
  values = { dc = local.standby_dc }
}

# =====================================================================================================================
# SCAFFOLD — sibling-workstream units (WS-B..F), default OFF. These are owned here so sibling
# PRs add ONLY their unit/module + flip the toggle in baremetal_config; they never edit this
# stack. Each block is commented because the referenced catalog unit ships in that WS's PR —
# uncommenting an empty source would break `stack generate`. The WS-A owner (this file) is
# the single place these per-DC compositions live.
#
# WS-B — ML CI/CD + registry (ADR-0037 reused; substrate delta in ADR-0052):
#   unit "baremetal-ml-artifact-store-primary" {
#     source = "${get_repo_root()}/catalog/units/baremetal-ml-artifact-store"
#     path   = "${local.primary_dc}/baremetal-ml-artifact-store"   # consumes rook-ceph s3_endpoint
#     values = { dc = local.primary_dc }
#   }
#   unit "baremetal-ml-artifact-store-standby" { ...standby... }
#
# WS-E — Security posture / SOC (ADR-0040 reused; Talos-posture delta in ADR-0050):
#   unit "baremetal-org-policy-primary" {
#     source = "${get_repo_root()}/catalog/units/baremetal-org-policy"
#     path   = "${local.primary_dc}/baremetal-org-policy"          # Talos posture + Kyverno/Gatekeeper bundle
#     values = { dc = local.primary_dc }
#   }
#   unit "baremetal-org-policy-standby" { ...standby... }
#
# WS-C (ml-monitoring), WS-D (grafana-self-serve + bare-metal panels), WS-F (golden paths)
# are delivered as ArgoCD apps / dashboards / templates, not new catalog units — they ride
# the in-cluster delivery layer (apps/infra/*) and do not add per-DC stack units here.
# =====================================================================================================================
