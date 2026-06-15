# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-vpc — input contract (ADR-0044 D5, ADR-0045 D1)
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Master toggle. When false the module creates no VPC, subnets, or security groups (default-OFF so the stack never provisions real infra until the apply gate)."
  type        = bool
  default     = false
  nullable    = false
}

variable "name" {
  description = "Name prefix for the greenfield GPU VPC and its resources (e.g. aws-eks-gpu-eu-west-1)."
  type        = string
  default     = "aws-eks-gpu"
}

variable "cluster_name" {
  description = "EKS cluster name used to tag subnets for Karpenter/ELB discovery (kubernetes.io/cluster/<name>, karpenter.sh/discovery)."
  type        = string
}

variable "vpc_cidr" {
  description = "Primary IPv4 CIDR block for the GPU VPC."
  type        = string
  default     = "10.80.0.0/16"
}

variable "azs" {
  description = "Availability zones the VPC spans. EFA cluster placement groups are single-AZ (ADR-0045 D1), so GPU pools pin one AZ; the VPC still spans multiple AZs for HA control-plane subnets."
  type        = list(string)
  default     = []
}

variable "private_subnets" {
  description = "Private subnet CIDRs (control-plane / general workloads, multi-AZ)."
  type        = list(string)
  default     = []
}

variable "gpu_subnets" {
  description = "GPU/EFA subnet CIDRs. EFA pools launch into a single-AZ GPU subnet (ADR-0045 D1); each entry maps positionally to an AZ in var.azs."
  type        = list(string)
  default     = []
}

variable "mtu" {
  description = "Jumbo-frame MTU for the GPU subnets. 9001 is the in-VPC AWS maximum and the documented setting for EFA / GPUDirect workloads (ADR-0045 D1)."
  type        = number
  default     = 9001

  validation {
    condition     = var.mtu >= 1500 && var.mtu <= 9001
    error_message = "mtu must be between 1500 and 9001 (9001 is the in-VPC AWS maximum)."
  }
}

variable "single_az_gpu_subnet" {
  description = "When true, EFA GPU pools are pinned to the first GPU subnet/AZ (EFA cluster placement groups cannot span AZs, ADR-0045 D1 / Negative)."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_efa_security_group" {
  description = "Create the self-referencing all-traffic security group EFA requires for intra-placement-group GPU<->GPU RDMA traffic (ADR-0045 D1/D4)."
  type        = bool
  default     = true
  nullable    = false
}

variable "flow_log_retention_days" {
  description = "Retention in days for VPC Flow Logs (audit/forensics)."
  type        = number
  default     = 365
}

variable "tags" {
  description = "ADR-0028 platform taxonomy tags (platform:system / platform:component / platform:owner / platform:env / platform:managed-by) applied to every resource."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "public_subnets" {
  description = "Public subnet CIDRs that host the NAT gateways for private-subnet egress (image pulls, API calls). Empty disables NAT (rely on VPC endpoints / intra-only)."
  type        = list(string)
  default     = []
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT gateway instead of one per AZ (cost vs HA tradeoff). Only relevant when public_subnets is non-empty."
  type        = bool
  default     = true
  nullable    = false
}
