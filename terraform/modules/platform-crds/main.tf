# ---------------------------------------------------------------------------------------------------------------------
# Platform CRDs Module
# ---------------------------------------------------------------------------------------------------------------------
# Single owner of all platform CRDs. Terraform installs CRDs before ArgoCD deploys operators.
# Uses alekc/kubectl provider — does NOT require CRDs at plan time (unlike kubernetes_manifest).
#
# CRD sources are version-locked via data "http" fetches from official GitHub releases,
# except prometheus-operator which uses the dedicated prometheus-operator-crds Helm chart.
# ---------------------------------------------------------------------------------------------------------------------

# =====================================================================================================================
# ArgoCD CRDs
# =====================================================================================================================

data "http" "argocd_crds" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/v${var.argocd_version}/manifests/crds/application-crd.yaml"
}

data "http" "argocd_appproject_crd" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/v${var.argocd_version}/manifests/crds/appproject-crd.yaml"
}

data "http" "argocd_applicationset_crd" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/v${var.argocd_version}/manifests/crds/applicationset-crd.yaml"
}

resource "kubectl_manifest" "argocd_application_crd" {
  yaml_body          = data.http.argocd_crds.response_body
  server_side_apply  = true
  force_conflicts    = true
  wait_for_rollout   = false
  override_namespace = ""
}

resource "kubectl_manifest" "argocd_appproject_crd" {
  yaml_body          = data.http.argocd_appproject_crd.response_body
  server_side_apply  = true
  force_conflicts    = true
  wait_for_rollout   = false
  override_namespace = ""
}

resource "kubectl_manifest" "argocd_applicationset_crd" {
  yaml_body          = data.http.argocd_applicationset_crd.response_body
  server_side_apply  = true
  force_conflicts    = true
  wait_for_rollout   = false
  override_namespace = ""
}

# =====================================================================================================================
# cert-manager CRDs
# =====================================================================================================================

data "http" "cert_manager_crds" {
  url = "https://github.com/cert-manager/cert-manager/releases/download/v${var.cert_manager_version}/cert-manager.crds.yaml"
}

resource "kubectl_manifest" "cert_manager_crds" {
  for_each = {
    for idx, doc in split("---", data.http.cert_manager_crds.response_body) :
    idx => doc if trimspace(doc) != "" && length(trimspace(doc)) > 10
  }

  yaml_body          = each.value
  server_side_apply  = true
  force_conflicts    = true
  wait_for_rollout   = false
  override_namespace = ""
}

# =====================================================================================================================
# External Secrets Operator CRDs
# =====================================================================================================================

data "http" "external_secrets_crds" {
  url = "https://raw.githubusercontent.com/external-secrets/external-secrets/v${var.external_secrets_version}/deploy/crds/bundle.yaml"
}

resource "kubectl_manifest" "external_secrets_crds" {
  for_each = {
    for idx, doc in split("---", data.http.external_secrets_crds.response_body) :
    idx => doc if trimspace(doc) != "" && length(trimspace(doc)) > 10
  }

  yaml_body          = each.value
  server_side_apply  = true
  force_conflicts    = true
  wait_for_rollout   = false
  override_namespace = ""
}

# =====================================================================================================================
# Prometheus Operator CRDs (via dedicated Helm chart)
# =====================================================================================================================

resource "helm_release" "prometheus_operator_crds" {
  name             = "prometheus-operator-crds"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-operator-crds"
  version          = var.prometheus_operator_crds_version
  namespace        = "monitoring"
  create_namespace = true

  # No values needed — this chart only installs CRDs
}

# =====================================================================================================================
# OPA Gatekeeper CRDs
# =====================================================================================================================

data "http" "gatekeeper_crds" {
  url = "https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v${var.gatekeeper_version}/deploy/gatekeeper.yaml"
}

locals {
  # Filter gatekeeper manifest to only CRD documents
  gatekeeper_docs = [
    for doc in split("---", data.http.gatekeeper_crds.response_body) :
    doc if length(trimspace(doc)) > 10 && can(regex("kind:\\s+CustomResourceDefinition", doc))
  ]
}

resource "kubectl_manifest" "gatekeeper_crds" {
  for_each = {
    for idx, doc in local.gatekeeper_docs :
    idx => doc
  }

  yaml_body          = each.value
  server_side_apply  = true
  force_conflicts    = true
  wait_for_rollout   = false
  override_namespace = ""
}

# =====================================================================================================================
# Velero CRDs
# =====================================================================================================================

data "http" "velero_crds" {
  url = "https://raw.githubusercontent.com/vmware-tanzu/velero/v${var.velero_version}/config/crd/v1/bases/crds.yaml"
}

resource "kubectl_manifest" "velero_crds" {
  for_each = {
    for idx, doc in split("---", data.http.velero_crds.response_body) :
    idx => doc if trimspace(doc) != "" && length(trimspace(doc)) > 10
  }

  yaml_body          = each.value
  server_side_apply  = true
  force_conflicts    = true
  wait_for_rollout   = false
  override_namespace = ""
}

# =====================================================================================================================
# Kargo CRDs
# =====================================================================================================================

data "http" "kargo_crds" {
  url = "https://raw.githubusercontent.com/akuity/kargo/v${var.kargo_version}/charts/kargo/crds/crds.yaml"
}

resource "kubectl_manifest" "kargo_crds" {
  for_each = {
    for idx, doc in split("---", data.http.kargo_crds.response_body) :
    idx => doc if trimspace(doc) != "" && length(trimspace(doc)) > 10
  }

  yaml_body          = each.value
  server_side_apply  = true
  force_conflicts    = true
  wait_for_rollout   = false
  override_namespace = ""
}
