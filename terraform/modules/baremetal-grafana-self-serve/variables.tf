variable "enabled" {
  description = "Master toggle. When false the module creates nothing (apply-gated default-OFF per IMPLEMENTATION_PLAN constraints)."
  type        = bool
  default     = false
}

variable "team_slug" {
  description = "Machine-safe team slug (lowercase, hyphens only). Used as label values and resource name prefixes. Example: team-baremetal-gpu."
  type        = string
}

variable "team_namespace" {
  description = "Kubernetes namespace where the team's workloads run. PrometheusRule RBAC is scoped to this namespace. Must already exist — this module does not create namespaces."
  type        = string
}

variable "ci_service_account" {
  description = "Name of the CI/CD Kubernetes ServiceAccount in team_namespace that needs permission to manage PrometheusRule objects (alert-rules-as-code). Leave empty string to skip RoleBinding creation."
  type        = string
  default     = ""
  nullable    = false
}

variable "grafana_namespace" {
  description = "Namespace where the Grafana deployment lives. Used for the Grafana dashboard ConfigMap RBAC grant."
  type        = string
  default     = "observability"
  nullable    = false
}

variable "grafana_service_account" {
  description = "Grafana Kubernetes ServiceAccount name used for folder Editor access grants. Leave empty string to skip."
  type        = string
  default     = ""
  nullable    = false
}

variable "loki_namespace" {
  description = "Namespace where Loki (or the Loki gateway) runs. Used for the Loki log-query access grant."
  type        = string
  default     = "observability"
  nullable    = false
}

variable "create_loki_access" {
  description = "When true, creates a ClusterRole + ClusterRoleBinding giving the team's CI ServiceAccount read access to Loki endpoints (required for Grafana Loki panel editing and log browsing). On bare-metal Loki access is RBAC-gated, unlike cloud-IAM-gated cloud deployments."
  type        = bool
  default     = true
}

variable "platform_labels" {
  description = "ADR-0028 platform taxonomy labels applied to every Kubernetes resource this module creates. Must include at minimum: platform.env and platform.owner."
  type        = map(string)
  default     = {}
  nullable    = false
}
