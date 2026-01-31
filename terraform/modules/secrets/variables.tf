variable "secrets" {
  description = "Map of secrets to create. Key is the secret name, value is the description."
  type        = map(string)
  default = {
    "/dns-failover/cloudflare/api-token"  = "Cloudflare API Token for DNS Failover"
    "/dns-failover/registrar/credentials" = "Registrar API Credentials"
    "/dns-failover/database/credentials"  = "Database Credentials"
  }
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
