# ---------------------------------------------------------------------------------------------------------------------
# Native test — generic ArgoCD Application wrapper
# ---------------------------------------------------------------------------------------------------------------------
# Plan-command test with a mocked kubernetes provider (no live cluster). Asserts that:
#   1. With the default apply gate (enabled = false) NOTHING is rendered.
#   2. With enabled = true the Application renders as argoproj.io/v1alpha1 Application,
#      with the destination/source wired and ADR-0028 taxonomy labels normalized to dotted
#      K8s label keys on the Application metadata.
# Mirrors the baremetal-ml-monitoring unit's interface.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "kubernetes" {}

variables {
  app_name              = "ml-monitoring-baremetal"
  argocd_namespace      = "argocd"
  project               = "platform"
  repo_url              = "https://github.com/your-org/platform-infrastructure.git"
  target_revision       = "main"
  chart_path            = "apps/infra/ml-monitoring"
  helm_value_files      = ["values.yaml", "values-baremetal.yaml"]
  destination_server    = "https://mock-talos-endpoint.internal:6443"
  destination_namespace = "ml-monitoring"
  sync_wave             = 20

  labels = {
    platform_system     = "ml-monitoring"
    platform_component  = "drift-exporter"
    platform_env        = "production"
    platform_owner      = "team-ml-platform"
    platform_managed_by = "argocd"
    platform_cluster    = "talos-uk-primary"
  }

  helm_set_values = {
    "driftExporter.referenceBucketUri"    = "s3://ml-reference-data"
    "externalSecrets.secretStoreRef.name" = "vault-cluster-secret-store"
  }
}

# Apply gate default: no Application created on a plan.
run "apply_gated_off_by_default" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(kubernetes_manifest.application) == 0
    error_message = "With enabled = false the module must render zero Application resources (apply gate)."
  }
}

# When enabled, the Application renders with the correct kind and identity.
run "renders_application_when_enabled" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(kubernetes_manifest.application) == 1
    error_message = "With enabled = true exactly one ArgoCD Application must be rendered."
  }

  assert {
    condition     = kubernetes_manifest.application[0].manifest.apiVersion == "argoproj.io/v1alpha1"
    error_message = "Application apiVersion must be argoproj.io/v1alpha1."
  }

  assert {
    condition     = kubernetes_manifest.application[0].manifest.kind == "Application"
    error_message = "Rendered manifest kind must be Application."
  }

  assert {
    condition     = kubernetes_manifest.application[0].manifest.metadata.name == "ml-monitoring-baremetal"
    error_message = "Application metadata.name must equal app_name."
  }

  assert {
    condition     = kubernetes_manifest.application[0].manifest.spec.destination.namespace == "ml-monitoring"
    error_message = "spec.destination.namespace must equal destination_namespace."
  }

  assert {
    condition     = kubernetes_manifest.application[0].manifest.spec.source.path == "apps/infra/ml-monitoring"
    error_message = "spec.source.path must equal chart_path."
  }
}

# ADR-0028 labels are normalized to dotted K8s label keys on the Application metadata.
run "adr0028_labels_normalized" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = kubernetes_manifest.application[0].manifest.metadata.labels["platform.system"] == "ml-monitoring"
    error_message = "platform_system must be normalized to the dotted label platform.system."
  }

  assert {
    condition     = kubernetes_manifest.application[0].manifest.metadata.labels["platform.managed-by"] == "argocd"
    error_message = "platform_managed_by must be normalized to platform.managed-by."
  }

  assert {
    condition     = kubernetes_manifest.application[0].manifest.metadata.annotations["argocd.argoproj.io/sync-wave"] == "20"
    error_message = "sync_wave must be rendered as the argocd.argoproj.io/sync-wave annotation."
  }
}
