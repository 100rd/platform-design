variable "chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.8.13"
}

variable "namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "create_namespace" {
  description = "Create the namespace if it doesn't exist"
  type        = bool
  default     = true
}

variable "ha_enabled" {
  description = "Enable HA mode (multiple replicas for controller, repo-server, server)"
  type        = bool
  default     = false
}

variable "enable_dex" {
  description = "Enable Dex OIDC provider"
  type        = bool
  default     = false
}

variable "server_replicas" {
  description = "Number of ArgoCD server replicas (overrides HA defaults)"
  type        = number
  default     = null
}

variable "controller_replicas" {
  description = "Number of application controller replicas (overrides HA defaults)"
  type        = number
  default     = null
}

variable "repo_server_replicas" {
  description = "Number of repo server replicas (overrides HA defaults)"
  type        = number
  default     = null
}

variable "controller_resources" {
  description = "Resource requests/limits for the application controller"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "250m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "1"
      memory = "1Gi"
    }
  }
}

variable "repo_server_resources" {
  description = "Resource requests/limits for the repo server"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "server_service_type" {
  description = "Service type for the ArgoCD server (ClusterIP, LoadBalancer, NodePort)"
  type        = string
  default     = "ClusterIP"
}

variable "additional_helm_values" {
  description = "Additional Helm values to merge (as a map)"
  type        = any
  default     = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
