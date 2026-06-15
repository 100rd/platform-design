# Outputs for baremetal-grafana-self-serve

output "prometheusrule_role_name" {
  description = "Name of the PrometheusRule manager Role created in team_namespace. Empty string when enabled=false or ci_service_account is empty."
  value       = var.enabled && var.ci_service_account != "" ? kubernetes_role.prometheusrule_manager[0].metadata[0].name : ""
}

output "grafana_dashboard_role_name" {
  description = "Name of the Grafana dashboard ConfigMap writer Role created in grafana_namespace. Empty string when enabled=false."
  value       = var.enabled ? kubernetes_role.grafana_dashboard_writer[0].metadata[0].name : ""
}

output "loki_cluster_role_name" {
  description = "Name of the Loki log-reader ClusterRole. Empty string when create_loki_access=false or enabled=false."
  value       = var.enabled && var.create_loki_access ? kubernetes_cluster_role.loki_log_reader[0].metadata[0].name : ""
}

output "resources_created" {
  description = "Map of resource types to created resource names for plan-output auditing. Values are '(skipped)' when the resource is disabled via toggle."
  value = {
    prometheusrule_role        = var.enabled && var.ci_service_account != "" ? kubernetes_role.prometheusrule_manager[0].metadata[0].name : "(skipped)"
    prometheusrule_rolebinding = var.enabled && var.ci_service_account != "" ? kubernetes_role_binding.prometheusrule_manager[0].metadata[0].name : "(skipped)"
    grafana_role               = var.enabled ? kubernetes_role.grafana_dashboard_writer[0].metadata[0].name : "(skipped)"
    grafana_rolebinding        = var.enabled && var.ci_service_account != "" ? kubernetes_role_binding.grafana_dashboard_writer[0].metadata[0].name : "(skipped)"
    loki_clusterrole           = var.enabled && var.create_loki_access ? kubernetes_cluster_role.loki_log_reader[0].metadata[0].name : "(skipped)"
    loki_clusterrolebinding    = var.enabled && var.create_loki_access && var.ci_service_account != "" ? kubernetes_cluster_role_binding.loki_log_reader[0].metadata[0].name : "(skipped)"
  }
}
