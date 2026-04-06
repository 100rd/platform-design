output "namespace" {
  description = "Kubernetes namespace where the validation suite is deployed"
  value       = kubernetes_namespace_v1.validation.metadata[0].name
}

output "service_account_name" {
  description = "ServiceAccount name used by validation Jobs"
  value       = kubernetes_service_account_v1.validator.metadata[0].name
}

output "cronjob_name" {
  description = "Name of the CronJob that runs the weekly validation suite"
  value       = kubernetes_cron_job_v1.validation_suite.metadata[0].name
}

output "config_map_name" {
  description = "Name of the ConfigMap holding all test manifests"
  value       = kubernetes_config_map_v1.test_manifests.metadata[0].name
}
