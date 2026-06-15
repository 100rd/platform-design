variable "enabled" {
  description = "Master toggle. When false the module creates nothing (apply-gated default-OFF posture for the WS-A stack)."
  type        = bool
  default     = false
}

variable "bootstrap_control_plane" {
  description = "Second gate: actually run the one-time etcd bootstrap on the first control-plane node. Kept separate from var.enabled so the cluster can be planned without ever initialising etcd. Apply-gated — never true in this mock repo."
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Talos cluster name (per-DC, e.g. uk-primary / uk-standby)."
  type        = string
  default     = "uk-baremetal-gpu"
}

variable "control_plane_vip" {
  description = "Control-plane VIP / endpoint talosctl bootstraps and fetches kubeconfig against (the API HA endpoint, fronted by KubePrism in-cluster)."
  type        = string
  default     = "10.10.0.10"
}

variable "bootstrap_node" {
  description = "IP/hostname of the single control-plane node etcd is bootstrapped on (bootstrap runs exactly once against one node)."
  type        = string
  default     = "10.10.0.10"
}

variable "client_configuration" {
  description = "talosctl client configuration object from talos-machineconfig (sensitive mTLS client cert/CA/key). Wired via the stack dependency block; mocked at plan time."
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
  default = {
    ca_certificate     = "bW9jay1jYQ=="
    client_certificate = "bW9jay1jZXJ0"
    client_key         = "bW9jay1rZXk="
  }
  sensitive = true
}

variable "etcd_snapshot_schedule" {
  description = "Cron schedule for the etcd snapshot CronJob (ADR-0049: a verified etcd snapshot is taken before every control-plane MachineConfig change / Talos upgrade). Surfaced as an output for the GitOps layer to consume."
  type        = string
  default     = "0 */6 * * *"
}

variable "etcd_snapshot_retention" {
  description = "Number of etcd snapshots to retain."
  type        = number
  default     = 24
}

variable "platform_labels" {
  description = "ADR-0028 dotted platform labels (e.g. platform.system = ml-infra) surfaced via outputs for downstream control-plane K8s resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
