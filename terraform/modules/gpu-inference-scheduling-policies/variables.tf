# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Scheduling Policies — Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "training_priority" {
  description = "PriorityClass value for gpu-training-high workloads (distributed training jobs)"
  type        = number
  default     = 100000
}

variable "inference_priority" {
  description = "PriorityClass value for gpu-inference-medium workloads (real-time inference)"
  type        = number
  default     = 50000
}

variable "batch_priority" {
  description = "PriorityClass value for gpu-batch-low workloads (batch/offline jobs)"
  type        = number
  default     = 10000
}

variable "enable_resource_quotas" {
  description = "Whether to create ResourceQuota objects per namespace limiting GPU allocation"
  type        = bool
  default     = true
}

variable "gpu_quota_namespaces" {
  description = "Map of namespace => GPU resource quota settings"
  type = map(object({
    requests_gpu = string
    limits_gpu   = string
    requests_cpu = string
    limits_cpu   = string
    requests_mem = string
    limits_mem   = string
  }))
  default = {
    "gpu-training" = {
      requests_gpu = "64"
      limits_gpu   = "64"
      requests_cpu = "2048"
      limits_cpu   = "2048"
      requests_mem = "8192Gi"
      limits_mem   = "8192Gi"
    }
    "gpu-inference" = {
      requests_gpu = "32"
      limits_gpu   = "32"
      requests_cpu = "1024"
      limits_cpu   = "1024"
      requests_mem = "4096Gi"
      limits_mem   = "4096Gi"
    }
    "gpu-batch" = {
      requests_gpu = "16"
      limits_gpu   = "16"
      requests_cpu = "512"
      limits_cpu   = "512"
      requests_mem = "2048Gi"
      limits_mem   = "2048Gi"
    }
  }
}

variable "example_podgroup_min_member" {
  description = "Minimum number of members for the example gang-scheduled PodGroup"
  type        = number
  default     = 8
}

variable "example_podgroup_min_resources_gpu" {
  description = "Minimum GPU resources for the example training PodGroup"
  type        = string
  default     = "8"
}

variable "tags" {
  description = "Common tags applied to all resources (passed to annotations)"
  type        = map(string)
  default     = {}
}
