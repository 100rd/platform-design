variable "chart_version" {
  description = "Falco Helm chart version"
  type        = string
  default     = "4.16.1"
}

variable "namespace" {
  description = "Kubernetes namespace for Falco"
  type        = string
  default     = "falco-system"
}

variable "create_namespace" {
  description = "Whether to create the namespace"
  type        = bool
  default     = true
}

variable "enable_sidekick" {
  description = "Enable Falcosidekick for alert routing"
  type        = bool
  default     = true
}

variable "driver_kind" {
  description = "Falco driver type (modern_ebpf, ebpf, kmod)"
  type        = string
  default     = "modern_ebpf"
  validation {
    condition     = contains(["modern_ebpf", "ebpf", "kmod"], var.driver_kind)
    error_message = "Driver kind must be one of: modern_ebpf, ebpf, kmod"
  }
}

variable "custom_rules_enabled" {
  description = "Deploy custom PCI-DSS Falco rules ConfigMap"
  type        = bool
  default     = true
}

variable "custom_rules_yaml" {
  description = "YAML content for custom Falco rules"
  type        = string
  default     = ""
}

variable "log_level" {
  description = "Falco log level"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["emergency", "alert", "critical", "error", "warning", "notice", "info", "debug"], var.log_level)
    error_message = "Log level must be a valid syslog level"
  }
}

variable "minimum_priority" {
  description = "Minimum Falco rule priority to output (emergency, alert, critical, error, warning, notice, informational, debug)"
  type        = string
  default     = "warning"
}

variable "falco_resources" {
  description = "Resource requests and limits for Falco pods"
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
      memory = "256Mi"
    }
    limits = {
      cpu    = "1000m"
      memory = "512Mi"
    }
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
