# ---------------------------------------------------------------------------------------------------------------------
# Inter-VPC Access Security — input variables (ADR-0013)
# ---------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "Name prefix for resources and tags. Use <account>-<region>."
  type        = string
}

variable "transit_gateway_id" {
  description = "ID of the hub Transit Gateway (from the transit-gateway module)."
  type        = string
}

# ─── VPN routing (sequencing-gated) ───────────────────────────────────────────

variable "enable_vpn_routing" {
  description = "Master gate for the VPN TGW routing (ADR-0013 sequencing gate). Flip to true ONLY after the network VPC + attachment are applied AND the prod NACL backstop is in place. Default false."
  type        = bool
  default     = false
}

variable "network_vpc_id" {
  description = "VPC ID of the Network-account VPN VPC. Used to look up its TGW attachment. Only required when enable_vpn_routing = true."
  type        = string
  default     = ""
}

variable "vpn_forward_routes" {
  description = <<-EOT
    Outbound allow-list for the VPN route table — one forward route per permitted
    destination. Map of key -> { destination_cidr, tgw_attachment_id }. The
    attachment is either a new-estate spoke attachment or the legacy admin-VPC's
    existing attachment (the cross-estate join / legacy-side routes). Use
    representative/placeholder CIDRs and attachment IDs; no estate-specific value
    is hardcoded in the module.
  EOT
  type = map(object({
    destination_cidr  = string
    tgw_attachment_id = string
  }))
  default = {}
}

variable "vpn_return_routes" {
  description = <<-EOT
    Return routes added on spoke route tables pointing back at the VPN pool. Map
    of key -> { route_table_id, vpn_pool_cidr }. For PROD-tier route tables pass
    the ops sub-pool CIDR (asymmetric return — control c); for shared/dev-tier
    route tables pass the full VPN pool CIDR. The VPN attachment is the next hop.
  EOT
  type = map(object({
    route_table_id = string
    vpn_pool_cidr  = string
  }))
  default = {}
}

# ─── Prod NACL backstop (ADR-0013 Layer 3 — design-target) ────────────────────

variable "enable_prod_nacl_backstop" {
  description = "Whether to apply the prod NACL backstop (deny the standard VPN sub-pool on prod subnets, allow the ops sub-pool). Prod-account scoped. Independent of enable_vpn_routing so it can be applied BEFORE routing is switched on."
  type        = bool
  default     = false
}

variable "prod_subnet_nacl_ids" {
  description = "Network ACL IDs of the production subnets to apply the backstop to. Typically passed from the prod-account VPC unit."
  type        = list(string)
  default     = []
}

variable "vpn_ops_subpool_cidr" {
  description = "Ops-tier VPN sub-pool CIDR. Allowed by the prod NACL and used for prod-tier asymmetric return routes."
  type        = string
  default     = "10.100.0.0/24"
}

variable "vpn_standard_subpool_cidr" {
  description = "Standard-tier VPN sub-pool CIDR. Denied by the prod NACL backstop."
  type        = string
  default     = "10.100.1.0/24"
}

variable "nacl_ops_allow_rule_number" {
  description = "NACL inbound rule number for the ops sub-pool ALLOW rule. Must be lower than the standard DENY rule so it is evaluated first."
  type        = number
  default     = 100
}

variable "nacl_standard_deny_rule_number" {
  description = "NACL inbound rule number for the standard sub-pool DENY rule. Must be higher than the ops ALLOW rule."
  type        = number
  default     = 110

  validation {
    condition     = var.nacl_standard_deny_rule_number > var.nacl_ops_allow_rule_number
    error_message = "The standard DENY rule number must be greater than the ops ALLOW rule number so ops is evaluated first."
  }
}

variable "tags" {
  description = "Additional tags merged on top of default tags."
  type        = map(string)
  default     = {}
}
