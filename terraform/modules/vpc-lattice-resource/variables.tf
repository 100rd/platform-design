# ---------------------------------------------------------------------------------------------------------------------
# VPC Lattice Resource Connectivity — Input Variables (ADR-0023)
# ---------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "Name prefix for all VPC Lattice resource-connectivity resources (e.g. 'shared-rds')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$", var.name))
    error_message = "name must be 2-32 chars, lowercase alphanumeric and hyphens, not starting/ending with a hyphen."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Resource Gateway — multi-AZ ingress in the resource-owning VPC
# ---------------------------------------------------------------------------------------------------------------------

variable "vpc_id" {
  description = "ID of the resource-owning VPC where the Resource Gateway is deployed."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs (one per AZ, multi-AZ recommended) for the Resource Gateway ingress."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet ID is required for the Resource Gateway."
  }
}

variable "security_group_ids" {
  description = "Security group IDs to attach to the Resource Gateway. Should scope to the resource port (e.g. 5432/tcp for RDS PostgreSQL)."
  type        = list(string)
  default     = []
}

variable "ip_address_type" {
  description = "IP address type for the Resource Gateway: IPV4, IPV6, or DUALSTACK."
  type        = string
  default     = "IPV4"

  validation {
    condition     = contains(["IPV4", "IPV6", "DUALSTACK"], var.ip_address_type)
    error_message = "ip_address_type must be one of: IPV4, IPV6, DUALSTACK."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Resource Configuration — type = ARN, pointing at the shared resource (e.g. an RDS DB ARN)
# ---------------------------------------------------------------------------------------------------------------------

variable "resource_arn" {
  description = "ARN of the target resource to expose (e.g. an RDS DB instance ARN). Placeholder by default; pass a real ARN per shared resource."
  type        = string
  default     = "arn:aws:rds:eu-west-1:000000000000:db:placeholder-db"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:", var.resource_arn))
    error_message = "resource_arn must be a valid AWS ARN."
  }
}

variable "resource_port" {
  description = "TCP port of the shared resource (VPC Lattice resource connectivity is TCP-only). Defaults to 5432 (PostgreSQL)."
  type        = number
  default     = 5432

  validation {
    condition     = var.resource_port >= 1 && var.resource_port <= 65535
    error_message = "resource_port must be between 1 and 65535."
  }
}

variable "resource_protocol" {
  description = "Protocol for the Resource Configuration. VPC Lattice resource connectivity is TCP-only (ADR-0023)."
  type        = string
  default     = "TCP"

  validation {
    condition     = var.resource_protocol == "TCP"
    error_message = "resource_protocol must be TCP — VPC Lattice resource connectivity is TCP-only (ADR-0023)."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# RAM cross-account sharing of the Service Network
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_ram_share" {
  description = "Whether to share the Service Network cross-account via AWS RAM."
  type        = bool
  default     = false
}

variable "organization_arn" {
  description = "ARN of the AWS Organization to share the Service Network with (org-wide). Used when share_with_organization = true."
  type        = string
  default     = ""
}

variable "share_with_organization" {
  description = "Share with the entire organization (true) or with specific accounts (false)."
  type        = bool
  default     = true
}

variable "share_with_accounts" {
  description = "Map of account name to account ID for targeted RAM sharing (used when share_with_organization = false)."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM auth policy — identity-scoped authorization on the Service Network
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_auth_policy" {
  description = "Attach an IAM auth policy to the Service Network (identity-scoped authorization, ADR-0023)."
  type        = bool
  default     = true
}

variable "principal_org_id" {
  description = "AWS Organization ID (o-xxxxxxxxxx) used to scope the auth policy via aws:PrincipalOrgID. Placeholder by default."
  type        = string
  default     = "o-placeholderorg"

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.principal_org_id))
    error_message = "principal_org_id must be an AWS Organization ID like o-xxxxxxxxxx."
  }
}

variable "allowed_principal_arns" {
  description = "Optional list of specific principal ARNs allowed by the auth policy. When empty, access is scoped solely by aws:PrincipalOrgID."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
