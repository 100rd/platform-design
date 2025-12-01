variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  type        = string
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.8.1"
}

variable "karpenter_controller_role_arn" {
  description = "IAM role ARN for Karpenter controller (from EKS Karpenter submodule)"
  type        = string
}

variable "karpenter_interruption_queue_name" {
  description = "SQS queue name for Karpenter interruption handling (from EKS Karpenter submodule)"
  type        = string
}

variable "karpenter_node_iam_role_name" {
  description = "IAM role name for Karpenter-provisioned nodes (from EKS Karpenter submodule)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to install Karpenter"
  type        = string
  default     = "kube-system"
}

variable "create_namespace" {
  description = "Whether to create the namespace if it doesn't exist"
  type        = bool
  default     = false
}

variable "controller_replicas" {
  description = "Number of Karpenter controller replicas for high availability"
  type        = number
  default     = 2
}

variable "controller_resources" {
  description = "Resource requests and limits for Karpenter controller"
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
      cpu    = "500m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1000m"
      memory = "1Gi"
    }
  }
}

variable "log_level" {
  description = "Log level for Karpenter controller"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "Log level must be one of: debug, info, warn, error"
  }
}

variable "enable_pod_disruption_budget" {
  description = "Enable pod disruption budget for Karpenter controller"
  type        = bool
  default     = true
}

variable "pdb_min_available" {
  description = "Minimum available pods for PDB"
  type        = number
  default     = 1
}

variable "enable_webhook" {
  description = "Enable Karpenter webhook"
  type        = bool
  default     = true
}

variable "webhook_port" {
  description = "Port for Karpenter webhook"
  type        = number
  default     = 8443
}

variable "node_selector" {
  description = "Node selector for Karpenter controller pods"
  type        = map(string)
  default = {
    "karpenter.sh/controller" = "true"
  }
}

variable "tolerations" {
  description = "Tolerations for Karpenter controller pods"
  type = list(object({
    key      = string
    operator = string
    effect   = string
    value    = optional(string)
  }))
  default = [
    {
      key      = "CriticalAddonsOnly"
      operator = "Exists"
      effect   = "NoSchedule"
      value    = null
    }
  ]
}

variable "additional_helm_values" {
  description = "Additional Helm values to merge with defaults"
  type        = any
  default     = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
