# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-inference-gateway — model-/cache-aware serving front (ADR-0047 D1/D2/D3/D4)
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Deploy the inference-gateway objects. When false the module no-ops (keeps the vLLM ClusterIP front; default-OFF, apply-gated)."
  type        = bool
  default     = false
  nullable    = false
}

variable "namespace" {
  description = "Namespace for the Gateway / InferencePool / InferenceObjective / EPP (where vLLM runs)."
  type        = string
  default     = "gpu-inference"
}

variable "data_plane" {
  description = "Gateway API data plane: 'envoy' (default, ADR-0047 D2 — inference-extension reference plane) or 'alb' (fallback, ADR-0047 D3)."
  type        = string
  default     = "envoy"

  validation {
    condition     = contains(["envoy", "alb"], var.data_plane)
    error_message = "data_plane must be 'envoy' or 'alb'."
  }
}

variable "gateway_class" {
  description = "GatewayClass name. Default is the Envoy Gateway class (ADR-0025 reuse); the ALB LBC class for the D3 fallback."
  type        = string
  default     = "envoy-gateway"
}

variable "gateway_name" {
  description = "Name of the Gateway."
  type        = string
  default     = "vllm-inference-gateway"
}

variable "hostnames" {
  description = "HTTPRoute hostnames. Empty matches all."
  type        = list(string)
  default     = []
}

variable "inference_pool_name" {
  description = "Name of the InferencePool (the set of vLLM replicas sharing accelerator + base model)."
  type        = string
  default     = "vllm-pool"
}

variable "inference_pool_selector" {
  description = "Label selector identifying the vLLM replica pods that form the InferencePool."
  type        = map(string)
  default     = { "app" = "vllm" }
  nullable    = false
}

variable "inference_pool_target_port" {
  description = "Container port vLLM serves on."
  type        = number
  default     = 8000
}

variable "inference_objectives" {
  description = "Per-workload routing/criticality objects (v1 GA InferenceObjective; was InferenceModel). Multi-LoRA → multiple objectives (ADR-0047 D1)."
  type = list(object({
    name         = string
    criticality  = optional(string, "Standard")
    target_model = string
  }))
  default  = []
  nullable = false
}

variable "inference_crd_version" {
  description = "Pinned Gateway API Inference Extension CRD/version (v1 GA; no main/latest, ADR-0047 D1/Risks)."
  type        = string
  default     = "v1.0.0"
}

variable "deploy_epp" {
  description = "Deploy the Endpoint Picker (EPP) ext-proc Deployment + Service. The EPP is NOT installed automatically by the gateway — it is a named deliverable (ADR-0047 D2)."
  type        = bool
  default     = true
  nullable    = false
}

variable "epp_image" {
  description = "Endpoint-Picker (EPP) ext-proc container image."
  type        = string
  default     = "registry.k8s.io/gateway-api-inference-extension/epp:v1.0.0"
}

variable "epp_replicas" {
  description = "EPP replica count."
  type        = number
  default     = 2
}

variable "epp_config" {
  description = "EPP routing weights (KV-cache utilisation, queue depth) — turns model-server metrics into routing decisions (ADR-0047 D1)."
  type        = map(string)
  default = {
    "kv-cache-weight"    = "1.0"
    "queue-depth-weight" = "1.0"
  }
  nullable = false
}

variable "waf_web_acl_arn" {
  description = "AWS WAF WebACL ARN (from the reused `waf` module, ADR-0047 D4) associated with the serving LB. Empty leaves the gateway without WAF (surface a warning in review)."
  type        = string
  default     = ""
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys) on every serving object."
  type        = map(string)
  default     = {}
  nullable    = false
}
