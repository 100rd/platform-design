output "enabled" {
  description = "Whether the module rendered Talos config (false = apply-gated OFF, nothing created)."
  value       = var.enabled
}

output "controlplane_machine_configuration" {
  description = "Rendered control-plane MachineConfig YAML (sensitive: contains cluster PKI). Null when disabled. Consumed by the talos-cluster module to bootstrap, apply-gated."
  value       = var.enabled ? data.talos_machine_configuration.controlplane[0].machine_configuration : null
  sensitive   = true
}

output "gpu_worker_machine_configuration" {
  description = "Rendered GPU-worker MachineConfig YAML (sensitive). Carries the rbd+ceph kernel modules (ADR-0052) and the NVIDIA system extension (ADR-0050). Null when disabled."
  value       = var.enabled ? data.talos_machine_configuration.gpu_worker[0].machine_configuration : null
  sensitive   = true
}

output "client_configuration" {
  description = "talosctl client configuration (sensitive: mTLS client cert/key — the only access path, no SSH). Null when disabled."
  value       = var.enabled ? data.talos_client_configuration.this[0].talos_config : null
  sensitive   = true
}

output "machine_secrets" {
  description = "The Talos machine secrets bundle (sensitive PKI) for the talos-cluster module's bootstrap/kubeconfig steps. Null when disabled. Never commit this — source from / persist to a secret manager."
  value       = var.enabled ? talos_machine_secrets.this[0].machine_secrets : null
  sensitive   = true
}

output "ceph_kernel_modules" {
  description = "The kernel modules declared for Rook-Ceph RBD (ADR-0052). Exposed so the baremetal-rook-ceph unit can assert the rbd+ceph prerequisite is satisfied before scheduling Ceph CSI."
  value       = var.ceph_kernel_modules
}

output "platform_labels" {
  description = "Effective ADR-0028 dotted node labels applied to every machine."
  value       = local.platform_node_labels
}
