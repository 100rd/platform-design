# ---------------------------------------------------------------------------------------------------------------------
# Variables — aws-ml-abac-iam
# ---------------------------------------------------------------------------------------------------------------------
# WS-E IAM least-privilege + ABAC role for ML workloads on the greenfield EKS GPU
# cluster. Provides an EKS Pod Identity role (ADR-0018) whose permission policy is
# scoped to the ml-platform $system axis by the ADR-0028 ABAC condition
#   aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system
# so a pod can only touch S3/KMS/Secrets resources tagged with its own system.
# apply-gated / default-OFF: gated by `enabled` so plan/validate creates no IAM.
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Master gate. When false (DEFAULT), the module creates NO IAM role / policy / Pod Identity association — apply-gated so plan/validate is inert. Set true only behind an explicit human apply (IAM is identity-critical)."
  type        = bool
  default     = false
}

variable "name" {
  description = "Base name for the IAM role and policy (e.g. 'ml-platform-workload'). The role is named '<name>-role'; the policy '<name>-policy'."
  type        = string
  default     = "ml-platform-workload"
}

variable "platform_system" {
  description = "The ADR-0028 platform:system value this role is scoped to (e.g. 'ml-platform', 'ml-pipeline'). Stamped as a principal tag on the role and used as the ABAC match key — the role may only access resources whose platform:system ResourceTag equals this principal tag."
  type        = string
  default     = "ml-platform"
}

variable "artifact_bucket_arns" {
  description = "List of S3 bucket ARNs (e.g. the MLflow artifact store from aws-ml-artifact-store, ADR-0048 D2) the role may access. Object-level access is still gated by the ABAC platform:system tag-match condition — listing these ARNs scopes the resource, ABAC scopes the ownership."
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "List of KMS key ARNs used for SSE-KMS on the ML artifact store / Secrets. Decrypt/GenerateDataKey is granted only under the ABAC tag-match condition. Empty by default."
  type        = list(string)
  default     = []
}

variable "secret_arns" {
  description = "List of Secrets Manager secret ARNs (e.g. MLflow RDS creds via ESO, ADR-0008/0031) the role may read. GetSecretValue is gated by the ABAC tag-match condition. Empty by default."
  type        = list(string)
  default     = []
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster to create the Pod Identity association against (ADR-0018). When empty, no association is created (the role can still be assumed by other means once enabled)."
  type        = string
  default     = ""
}

variable "service_account_namespace" {
  description = "Kubernetes namespace of the workload ServiceAccount for the Pod Identity association. Used only when eks_cluster_name is set."
  type        = string
  default     = "ml-platform"
}

variable "service_account_name" {
  description = "Name of the workload ServiceAccount bound to this role via Pod Identity. Used only when eks_cluster_name is set."
  type        = string
  default     = "ml-platform-workload"
}

variable "tags" {
  description = "ADR-0028 platform taxonomy tags applied to the IAM role/policy. Defaults set platform:system from var.platform_system, platform:component=ml-iam, platform:owner=team-ml-platform. The role's principal tag platform:system (used for ABAC) is derived from var.platform_system, not from this map."
  type        = map(string)
  default     = {}
}
