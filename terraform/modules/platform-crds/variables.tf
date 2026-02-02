# ---------------------------------------------------------------------------------------------------------------------
# CRD Version Variables
# ---------------------------------------------------------------------------------------------------------------------
# Each variable pins the CRD version independently of the operator/controller version.
# This allows upgrading CRDs ahead of or behind the operator as needed.
# ---------------------------------------------------------------------------------------------------------------------

variable "argocd_version" {
  description = "ArgoCD version for CRD installation"
  type        = string
  default     = "2.14.2"
}

variable "cert_manager_version" {
  description = "cert-manager version for CRD installation"
  type        = string
  default     = "1.17.2"
}

variable "external_secrets_version" {
  description = "External Secrets Operator version for CRD installation"
  type        = string
  default     = "0.14.1"
}

variable "prometheus_operator_crds_version" {
  description = "prometheus-operator-crds Helm chart version"
  type        = string
  default     = "18.0.2"
}

variable "gatekeeper_version" {
  description = "OPA Gatekeeper version for CRD installation"
  type        = string
  default     = "3.18.2"
}

variable "velero_version" {
  description = "Velero version for CRD installation"
  type        = string
  default     = "1.15.0"
}

variable "kargo_version" {
  description = "Kargo version for CRD installation"
  type        = string
  default     = "1.2.0"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
