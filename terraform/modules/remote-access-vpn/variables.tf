# ---------------------------------------------------------------------------------------------------------------------
# Remote-Access VPN — input variables (ADR-0013)
# ---------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "Name prefix for all resources and tags. Use <account>-<region> (e.g. network-eu-west-1)."
  type        = string
}

variable "vpc_id" {
  description = "ID of the Network-account VPC in which to deploy the VPN host."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the VPN EC2 instance. At least one required."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the NLB (EIP attachment). At least one required."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt EBS volumes and CloudWatch log groups."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the VPN host."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Size in GiB of the root EBS volume."
  type        = number
  default     = 20
}

variable "datastore_volume_size_gb" {
  description = "Size in GiB of the dedicated EBS data volume for the VPN datastore (/var/lib/mongodb)."
  type        = number
  default     = 30
}

variable "datastore_port" {
  description = "TCP port for the local single-node VPN datastore (MongoDB default 27017). Loopback only."
  type        = number
  default     = 27017
}

# ─── VPN client pool + trust sub-pools (ADR-0013 trust model) ─────────────────

variable "vpn_client_cidr" {
  description = "CIDR for the entire VPN client pool. Must not overlap any estate CIDR. Use a placeholder/representative range."
  type        = string
  default     = "10.100.0.0/20"
}

variable "vpn_ops_subpool_cidr" {
  description = "Sub-CIDR for ops-tier VPN clients. Only this sub-pool is routed to production (ADR-0013 trust model)."
  type        = string
  default     = "10.100.0.0/24"
}

variable "vpn_standard_subpool_cidr" {
  description = "Sub-CIDR for standard-tier VPN clients. Routed to the shared range only; blocked from production by the prod NACL backstop (ADR-0013)."
  type        = string
  default     = "10.100.1.0/24"
}

variable "vpn_data_port" {
  description = "UDP/TCP port for the VPN data plane (Pritunl default 443)."
  type        = number
  default     = 443
}

variable "vpn_ui_port" {
  description = "TCP port for the VPN web UI + NLB health check. Reachable only over TGW from admin networks; not public. Must differ from vpn_data_port."
  type        = number
  default     = 8443
}

variable "reachable_cidrs" {
  description = "Spoke/legacy CIDRs VPN clients may reach. Added as instance-SG egress rules. Routing to these CIDRs is configured by the inter-vpc-security module's TGW route tables (ADR-0013 allow-list)."
  type        = list(string)
  default     = []
}

# ─── Secrets + backups ────────────────────────────────────────────────────────

variable "secrets_path_prefix" {
  description = "Secrets Manager path prefix for this deployment (e.g. org/network/remote-access-vpn). Secret names are <prefix>/datastore-uri and <prefix>/setup-key. Values are set out-of-band and never stored in this repo."
  type        = string
  default     = "org/network/remote-access-vpn"
}

variable "secrets_arn_prefix" {
  description = "Full ARN prefix for Secrets Manager secrets read by the instance at boot (e.g. arn:aws:secretsmanager:eu-west-1:000000000000:secret:org/network/remote-access-vpn). Used in the IAM policy Resource condition. Use a placeholder account ID."
  type        = string
}

variable "backup_s3_bucket" {
  description = "Name of the S3 bucket used for datastore backups. The bucket must exist with SSE-KMS enabled before apply."
  type        = string
}

# ─── Observability ────────────────────────────────────────────────────────────

variable "alert_sns_topic_arn" {
  description = "ARN of the SNS topic to which CloudWatch alarms send notifications."
  type        = string
}

variable "flow_log_retention_days" {
  description = "Retention period in days for the VPC flow log and application log CloudWatch log groups."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a valid CloudWatch log group retention value."
  }
}

variable "dlm_snapshot_retain_days" {
  description = "Number of days to retain EBS snapshots created by the DLM lifecycle policy."
  type        = number
  default     = 7
}

variable "enable_deletion_protection" {
  description = "Whether to enable deletion protection on the NLB. Set false for non-production test environments."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags merged on top of default tags for all resources."
  type        = map(string)
  default     = {}
}
