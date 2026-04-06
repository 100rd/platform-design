variable "kata_version" {
  description = "Kata Containers version to reference in annotations"
  type        = string
  default     = "3.22.0"
}

variable "attestation_service_url" {
  description = "URL of the remote attestation service for CC workloads"
  type        = string
  default     = "https://attestation.example.internal:8443"
}

variable "attestation_tee_type" {
  description = "Trusted Execution Environment type (tdx, sev-snp)"
  type        = string
  default     = "tdx"
}

variable "attestation_policy_namespace" {
  description = "OPA policy namespace for attestation enforcement"
  type        = string
  default     = "gpu-inference-cc"
}

variable "cc_namespace" {
  description = "Kubernetes namespace for CC workloads (used for network policy)"
  type        = string
  default     = "gpu-inference"
}

variable "cc_app_label" {
  description = "Value of app label to match CC workload pods for network policy"
  type        = string
  default     = "vllm-cc"
}

variable "tags" {
  description = "Tags to apply to resources (stored in ConfigMap annotations)"
  type        = map(string)
  default     = {}
}
