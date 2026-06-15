output "enabled" {
  description = "Whether the cluster bootstrap module is enabled."
  value       = var.enabled
}

output "bootstrapped" {
  description = "Whether the etcd bootstrap resource was actually created (enabled AND bootstrap_control_plane). False in the default apply-gated posture."
  value       = local.do_bootstrap
}

output "kubeconfig" {
  description = "Raw cluster kubeconfig (sensitive) for downstream in-cluster units. Null until bootstrapped; the stack mocks this at plan time."
  value       = local.do_bootstrap ? talos_cluster_kubeconfig.this[0].kubeconfig_raw : null
  sensitive   = true
}

output "cluster_endpoint" {
  description = "Control-plane API endpoint (the VIP), for downstream provider wiring."
  value       = "https://${var.control_plane_vip}:6443"
}

output "etcd_snapshot_schedule" {
  description = "etcd snapshot cron schedule (ADR-0049 control-plane gate) for the GitOps CronJob to consume."
  value       = var.etcd_snapshot_schedule
}

output "platform_labels" {
  description = "Effective ADR-0028 dotted labels for the control-plane system."
  value       = local.platform_labels
}
