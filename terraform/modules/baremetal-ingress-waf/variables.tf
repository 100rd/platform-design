variable "enabled" {
  description = "Master toggle. When false the module creates nothing (apply-gated default-OFF posture for the WS-A stack)."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace the serving Gateway + rate-limit policy live in."
  type        = string
  default     = "ml-inference"
}

variable "gateway_backend" {
  description = "Serving gateway backend. cilium = Cilium Gateway (one networking stack, ADR-0051/0053 recommendation); envoy = Envoy Gateway (reuse apps/infra/envoy-gateway)."
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["cilium", "envoy"], var.gateway_backend)
    error_message = "gateway_backend must be one of cilium, envoy."
  }
}

variable "gateway_name" {
  description = "Name of the serving Gateway."
  type        = string
  default     = "ml-serving"
}

variable "cilium_gateway_class" {
  description = "GatewayClass name for the Cilium Gateway backend."
  type        = string
  default     = "cilium"
}

variable "envoy_gateway_class" {
  description = "GatewayClass name for the Envoy Gateway backend."
  type        = string
  default     = "envoy-gateway"
}

variable "tls_secret_name" {
  description = "Name of the TLS secret (cert/key) the HTTPS listener terminates with. Sourced from cert-manager/ESO — never committed."
  type        = string
  default     = "ml-serving-tls"
}

variable "protected_path" {
  description = "Request path the WAF/rate-limit applies to (the inference endpoint)."
  type        = string
  default     = "/v1/.*"
}

variable "rate_limit_requests" {
  description = "Request count allowed per rate_limit_unit (Cloud-Armor-mirror rate limit, Envoy backend)."
  type        = number
  default     = 100
}

variable "rate_limit_unit" {
  description = "Rate-limit time unit (Second/Minute/Hour) for the Envoy backend."
  type        = string
  default     = "Second"

  validation {
    condition     = contains(["Second", "Minute", "Hour"], var.rate_limit_unit)
    error_message = "rate_limit_unit must be one of Second, Minute, Hour."
  }
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-inference) applied to the Gateway and rate-limit policy."
  type        = map(string)
  default     = {}
  nullable    = false
}
