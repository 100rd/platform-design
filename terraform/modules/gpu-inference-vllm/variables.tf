variable "vllm_version" {
  description = "vLLM container image version to deploy"
  type        = string
  default     = "0.19.0"
}

variable "replicas" {
  description = "Number of vLLM Deployment replicas"
  type        = number
  default     = 3
}

variable "model_name" {
  description = "HuggingFace model identifier (used as served-model-name and path suffix)"
  type        = string
  default     = "meta-llama/Llama-3-70B-Instruct"
}

variable "tensor_parallel_size" {
  description = "Number of GPUs for tensor parallelism per replica"
  type        = number
  default     = 8
}

variable "max_model_len" {
  description = "Maximum context length (tokens) the model will handle"
  type        = number
  default     = 131072
}

variable "enable_lora" {
  description = "Enable Multi-LoRA adapter support in vLLM"
  type        = bool
  default     = true
}

variable "max_loras" {
  description = "Maximum number of LoRA adapters that can be loaded simultaneously"
  type        = number
  default     = 8
}

variable "lora_modules" {
  description = "List of LoRA modules to register at startup. Each entry has name and path."
  type = list(object({
    name = string
    path = string
  }))
  default = [
    { name = "finance-adapter", path = "/lora-adapters/finance-v1" },
    { name = "code-adapter", path = "/lora-adapters/code-v2" },
    { name = "summarization-adapter", path = "/lora-adapters/summarization-v1" },
  ]
}

variable "gpu_memory_utilization" {
  description = "Fraction of GPU memory to reserve for model weights (0.0–1.0)"
  type        = number
  default     = 0.92
}

variable "namespace" {
  description = "Kubernetes namespace for the gpu-inference workloads"
  type        = string
  default     = "gpu-inference"
}

variable "resource_claim_template_name" {
  description = "Name of the DRA ResourceClaimTemplate that allocates GPUs to each pod"
  type        = string
  default     = "single-gpu-inference"
}

variable "scheduler_name" {
  description = "Scheduler to use for vLLM pods (volcano for gang scheduling)"
  type        = string
  default     = "volcano"
}

variable "priority_class_name" {
  description = "PriorityClass for vLLM pods"
  type        = string
  default     = "gpu-inference-medium"
}

variable "tags" {
  description = "Tags to apply to taggable resources (informational — used in labels)"
  type        = map(string)
  default     = {}
}
