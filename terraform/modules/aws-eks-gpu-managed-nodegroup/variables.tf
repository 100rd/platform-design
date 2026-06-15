# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-managed-nodegroup — reserved EFA-DRA training node group (ADR-0046 D2/D4, ADR-0045 D3)
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Master toggle. When false the module creates no node group (default-OFF; apply-gated)."
  type        = bool
  default     = false
  nullable    = false
}

variable "cluster_name" {
  description = "EKS cluster name (from aws-eks-gpu) the node group attaches to."
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for the managed node group's nodes. Empty creates a minimal role within this module."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs (single GPU subnet for EFA single-AZ pinning, ADR-0045 D1)."
  type        = list(string)
  default     = []
}

variable "instance_type" {
  description = "GPU instance type for reserved training (e.g. p6-b200.48xlarge, p5.48xlarge). EFA-capable."
  type        = string
  default     = "p5.48xlarge"
}

variable "desired_size" {
  description = "Pinned node count for the duration of a training run (no autoscaling mid-job, ADR-0046 D2)."
  type        = number
  default     = 0
}

variable "min_size" {
  description = "Minimum nodes. 0 allows scale-to-zero between jobs (ADR-0046 D3) while pinned within a job."
  type        = number
  default     = 0
}

variable "max_size" {
  description = "Maximum nodes for the reserved pool."
  type        = number
  default     = 16
}

variable "capacity_type" {
  description = "Capacity type. EFA training is NOT spot (ADR-0046 D3/D4) — ON_DEMAND or a Capacity Block."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "CAPACITY_BLOCK"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND or CAPACITY_BLOCK (no SPOT for gang training, ADR-0046 A4)."
  }
}

variable "capacity_block_reservation_id" {
  description = "EC2 Capacity Block reservation ID for scarce EFA families (P5en/P6, ADR-0046 D4). Required when capacity_type = CAPACITY_BLOCK; a per-region prerequisite tracked outside Terraform."
  type        = string
  default     = ""
}

variable "placement_group_name" {
  description = "Cluster placement group name (ADR-0045 D1) packing nodes onto one spine for low-latency NCCL."
  type        = string
  default     = ""
}

variable "enable_efa" {
  description = "Enable EFA interfaces on the node group (ADR-0045 D3). Exposed via the EFA DRA driver — valid ONLY on managed node groups (aws-eks-efa-fabric efa_mode = dra)."
  type        = bool
  default     = true
  nullable    = false
}

variable "efa_mode" {
  description = "EFA exposure mode. On managed node groups DRA is the topology-aware path (ADR-0045 D3). Must be 'dra' here — 'device-plugin' belongs on Karpenter pools (ADR-0045 D2)."
  type        = string
  default     = "dra"

  validation {
    condition     = contains(["dra", "device-plugin"], var.efa_mode)
    error_message = "efa_mode must be 'dra' or 'device-plugin'."
  }
}

variable "ami_type" {
  description = "EKS AMI type for the GPU node group. Bottlerocket GPU variant (ADR-0030) bakes the NVIDIA driver."
  type        = string
  default     = "BOTTLEROCKET_x86_64_NVIDIA"
}

variable "labels" {
  description = "Kubernetes labels on the node group's nodes (carry the dotted platform.* ADR-0028 keys)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tags" {
  description = "ADR-0028 platform:* tags applied to every resource."
  type        = map(string)
  default     = {}
  nullable    = false
}
