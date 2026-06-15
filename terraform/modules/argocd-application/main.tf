# ---------------------------------------------------------------------------------------------------------------------
# Generic ArgoCD Application wrapper
# ---------------------------------------------------------------------------------------------------------------------
# Renders a single argoproj.io/v1alpha1 Application object via the kubernetes provider's
# kubernetes_manifest resource. Substrate-agnostic: it creates an ArgoCD Application that
# points at a Helm chart in a Git repo; the actual in-cluster workloads are rendered by Helm
# and reconciled by ArgoCD. Any catalog unit can source this module (ADR-0028 taxonomy).
#
# Apply gate: the resource is created only when var.enabled = true (default false), via
# count. A plan/validate with the default creates nothing — satisfies never_apply CI policy.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # -------------------------------------------------------------------------------------------------------------------
  # ADR-0028 label normalization
  # -------------------------------------------------------------------------------------------------------------------
  # Catalog units pass labels with underscore keys (platform_system, ...) because dotted keys
  # are awkward in HCL map literals. ArgoCD/Kubernetes expect the canonical dotted form
  # (platform.system, ...). Map the five core taxonomy keys (+ the platform_cluster extension)
  # to their dotted equivalents; pass any other keys through verbatim.
  taxonomy_key_map = {
    platform_system     = "platform.system"
    platform_component  = "platform.component"
    platform_env        = "platform.env"
    platform_owner      = "platform.owner"
    platform_managed_by = "platform.managed-by"
    platform_cluster    = "platform.cluster"
  }

  normalized_labels = {
    for k, v in var.labels :
    lookup(local.taxonomy_key_map, k, k) => v
  }

  # -------------------------------------------------------------------------------------------------------------------
  # Helm source block — only emit valueFiles / parameters when non-empty so the rendered
  # manifest stays minimal and ArgoCD does not see spurious empty keys.
  # -------------------------------------------------------------------------------------------------------------------
  helm_parameters = [
    for name, value in var.helm_set_values : {
      name  = name
      value = value
    }
  ]

  helm_block = merge(
    length(var.helm_value_files) > 0 ? { valueFiles = var.helm_value_files } : {},
    length(local.helm_parameters) > 0 ? { parameters = local.helm_parameters } : {},
  )

  source_block = merge(
    {
      repoURL        = var.repo_url
      targetRevision = var.target_revision
      path           = var.chart_path
    },
    length(local.helm_block) > 0 ? { helm = local.helm_block } : {},
  )

  # -------------------------------------------------------------------------------------------------------------------
  # syncPolicy — automated sync is opt-in and off by default (apply-gated repo). syncOptions
  # always include CreateNamespace per create_namespace.
  # -------------------------------------------------------------------------------------------------------------------
  sync_options = var.create_namespace ? ["CreateNamespace=true"] : []

  automated_block = var.automated_sync ? {
    automated = {
      prune    = var.auto_prune
      selfHeal = var.self_heal
    }
  } : {}

  sync_policy = merge(
    local.automated_block,
    length(local.sync_options) > 0 ? { syncOptions = local.sync_options } : {},
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# The ArgoCD Application. count = enabled ? 1 : 0 — apply gate. Nothing is created on a
# default plan/validate.
# ---------------------------------------------------------------------------------------------------------------------
resource "kubernetes_manifest" "application" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.app_name
      namespace = var.argocd_namespace
      labels    = local.normalized_labels
      annotations = {
        "argocd.argoproj.io/sync-wave" = tostring(var.sync_wave)
      }
    }
    spec = merge(
      {
        project = var.project
        source  = local.source_block
        destination = {
          server    = var.destination_server
          namespace = var.destination_namespace
        }
      },
      length(local.sync_policy) > 0 ? { syncPolicy = local.sync_policy } : {},
    )
  }
}
