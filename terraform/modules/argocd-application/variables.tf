# ---------------------------------------------------------------------------------------------------------------------
# Input variables — generic ArgoCD Application wrapper
# ---------------------------------------------------------------------------------------------------------------------
# Every variable below is part of the public interface that catalog units (e.g.
# catalog/units/baremetal-ml-monitoring) wire in via Terragrunt `inputs`. Each has an
# explicit type and a description per repo Terraform rules. Sensible defaults are provided
# so the module validates/plans standalone in CI.
# ---------------------------------------------------------------------------------------------------------------------

# --- Apply gate -------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Apply gate. When false (default), the module renders NO cluster resources — plan/validate create nothing. CI/CD flips this to true only on main after merge, with explicit human approval. Mirrors the unit's never_apply policy."
  type        = bool
  default     = false
}

# --- Identity ---------------------------------------------------------------------------------------------------------

variable "app_name" {
  description = "Name of the ArgoCD Application object (metadata.name)."
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed and where the Application object is created (metadata.namespace)."
  type        = string
  default     = "argocd"
}

variable "project" {
  description = "ArgoCD AppProject the Application belongs to (spec.project)."
  type        = string
  default     = "default"
}

# --- Source (Git repo + Helm chart path) ------------------------------------------------------------------------------

variable "repo_url" {
  description = "Git repository URL containing the application manifests / Helm chart (spec.source.repoURL)."
  type        = string
}

variable "target_revision" {
  description = "Git revision (branch, tag, or commit) to track (spec.source.targetRevision)."
  type        = string
  default     = "main"
}

variable "chart_path" {
  description = "Path within the repository to the Helm chart or manifests (spec.source.path)."
  type        = string
}

variable "helm_value_files" {
  description = "Ordered list of Helm values files (relative to chart_path) to apply (spec.source.helm.valueFiles). Empty list omits the valueFiles key."
  type        = list(string)
  default     = []
}

variable "helm_set_values" {
  description = "Map of Helm parameter overrides rendered as spec.source.helm.parameters (name/value pairs). Use for substrate-specific wiring resolved from dependency outputs (e.g. S3 bucket URI, secret store ref). No secrets — reference a secret manager instead."
  type        = map(string)
  default     = {}
}

# --- Destination ------------------------------------------------------------------------------------------------------

variable "destination_server" {
  description = "API server URL of the target cluster registered in ArgoCD (spec.destination.server). For the in-cluster ArgoCD target use https://kubernetes.default.svc."
  type        = string
  default     = "https://kubernetes.default.svc"
}

variable "destination_namespace" {
  description = "Namespace in the destination cluster where the application is deployed (spec.destination.namespace)."
  type        = string
}

# --- Sync behaviour ---------------------------------------------------------------------------------------------------

variable "sync_wave" {
  description = "ArgoCD sync wave for ordering relative to other Applications. Rendered as the argocd.argoproj.io/sync-wave annotation."
  type        = number
  default     = 0
}

variable "automated_sync" {
  description = "Enable ArgoCD automated sync (spec.syncPolicy.automated). Default false — sync is gated and requires explicit human approval in this mock/apply-gated repo."
  type        = bool
  default     = false
}

variable "auto_prune" {
  description = "When automated_sync is true, prune resources removed from Git (spec.syncPolicy.automated.prune)."
  type        = bool
  default     = false
}

variable "self_heal" {
  description = "When automated_sync is true, automatically correct drift (spec.syncPolicy.automated.selfHeal)."
  type        = bool
  default     = false
}

variable "create_namespace" {
  description = "Add CreateNamespace=true to spec.syncPolicy.syncOptions so ArgoCD creates the destination namespace."
  type        = bool
  default     = true
}

# --- ADR-0028 taxonomy labels -----------------------------------------------------------------------------------------

variable "labels" {
  description = "Platform taxonomy labels (ADR-0028). Keys use the underscore form the catalog units pass (e.g. platform_system, platform_component, platform_env, platform_owner, platform_managed_by, platform_cluster); the module normalizes them to the canonical dotted K8s label keys (platform.system, ...) on the Application metadata and propagates them to the destination workload via Helm-rendered metadata. Non-taxonomy keys are passed through verbatim."
  type        = map(string)
  default     = {}
}
