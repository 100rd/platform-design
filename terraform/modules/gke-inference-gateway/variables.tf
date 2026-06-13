variable "enabled" {
  description = "Deploy the Inference Gateway objects. Set false to no-op (keep the vLLM ClusterIP front)."
  type        = bool
  default     = true
  nullable    = false
}

variable "namespace" {
  description = "Namespace for the Gateway / InferencePool / InferenceModel objects (where vLLM runs)."
  type        = string
  default     = "gpu-inference"
}

variable "gateway_name" {
  description = "Name of the Gateway."
  type        = string
  default     = "vllm-inference-gateway"
}

variable "gateway_class" {
  description = "GKE inference GatewayClass (e.g. gke-l7-rilb for internal, gke-l7-regional-external-managed for external)."
  type        = string
  default     = "gke-l7-rilb"
}

variable "hostnames" {
  description = "HTTPRoute hostnames. Empty matches all."
  type        = list(string)
  default     = []
}

variable "inference_pool_name" {
  description = "Name of the InferencePool (the set of vLLM replicas)."
  type        = string
  default     = "vllm-pool"
}

variable "inference_pool_target_port" {
  description = "Container port vLLM serves on."
  type        = number
  default     = 8000
}

variable "inference_pool_selector" {
  description = "Label selector matching the vLLM pods (unchanged from gpu-inference-vllm)."
  type        = map(string)
  default     = { "app" = "vllm" }
}

variable "endpoint_picker_name" {
  description = "Name of the endpoint-picker (EPP) service that does KV-cache/load-aware routing for the pool."
  type        = string
  default     = "vllm-epp"
}

variable "inference_models" {
  description = "Per-model routing. Each maps an external model name to a served target model (multi-LoRA → multiple entries)."
  type = list(object({
    name         = string                       # InferenceModel object name
    model_name   = string                       # external model name clients request
    target_model = string                       # served model / LoRA adapter name
    criticality  = optional(string, "Standard") # Critical | Standard | Sheddable
    weight       = optional(number, 100)
  }))
  default = []

  validation {
    condition = alltrue([
      for m in var.inference_models : contains(["Critical", "Standard", "Sheddable"], m.criticality)
    ])
    error_message = "criticality must be one of: Critical, Standard, Sheddable."
  }
}

variable "enable_body_based_router" {
  description = "Enable the Body-Based Router (reads the model name from the OpenAI-style request body into a header for routing)."
  type        = bool
  default     = true
  nullable    = false
}

variable "cloud_armor_policy_id" {
  description = "Cloud Armor security policy ID to attach via GCPBackendPolicy (ADR-0042 D5). Null skips the policy."
  type        = string
  default     = null
}

variable "platform_labels" {
  description = "Additional ADR-0028 Kubernetes-plane platform labels (dotted keys)."
  type        = map(string)
  default     = {}
}
