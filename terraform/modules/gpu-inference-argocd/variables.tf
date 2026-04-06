variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  type        = string
  default     = "argocd"
}

variable "gpu_inference_repo_url" {
  description = "Git repository URL for gpu-inference configurations"
  type        = string
}

variable "gpu_inference_repo_path" {
  description = "Path within the repo for gpu-inference ArgoCD apps"
  type        = string
  default     = "argocd/gpu-inference"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
