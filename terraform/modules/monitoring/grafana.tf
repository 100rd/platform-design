# Grafana is currently deployed as part of the kube-prometheus-stack in prometheus.tf
# This file is reserved for standalone Grafana configuration or additional resources
# such as Dashboards and Datasources defined as Kubernetes manifests.

# Example of how to add a dashboard via ConfigMap (future implementation)
# resource "kubernetes_config_map" "grafana_dashboards" { ... }
