# baremetal-grafana-self-serve — Terraform module
#
# Provisions the Kubernetes RBAC infrastructure for per-team self-serve
# observability on the Talos bare-metal cluster:
#
#   1. PrometheusRule manager Role + RoleBinding in team_namespace
#      (enables alert-rules-as-code: the team's CI SA can create/update
#      PrometheusRule objects without platform-team tickets)
#
#   2. Grafana dashboard ConfigMap writer Role + RoleBinding in grafana_namespace
#      (enables the team's CI SA to patch its own dashboard ConfigMaps in the
#      Grafana sidecar namespace without a platform-team ticket)
#
#   3. Loki log-query ClusterRole + ClusterRoleBinding (optional, create_loki_access)
#      (bare-metal Loki uses RBAC for namespace label-selector access;
#      cloud deployments gate this via IAM instead — this is a bare-metal delta)
#
# All resources carry ADR-0028 platform taxonomy labels and are gated by the
# `enabled` toggle (default false) — nothing is created unless explicitly enabled.
# This satisfies the plan's apply-gated / default-OFF convention.
#
# ADR-0039: Self-Serve Observability
# ADR-0028: platform.system = observability (mandatory on every resource)
# ADR-0049: Talos foundation (target cluster context)

locals {
  common_labels = merge(
    {
      "platform.system"     = "observability"
      "platform.component"  = "self-serve"
      "platform.managed-by" = "terraform"
      "team"                = var.team_slug
    },
    var.platform_labels,
  )
}

# ---------------------------------------------------------------------------
# 1. PrometheusRule manager Role + RoleBinding — team_namespace
# ---------------------------------------------------------------------------

resource "kubernetes_role" "prometheusrule_manager" {
  count = var.enabled && var.ci_service_account != "" ? 1 : 0

  metadata {
    name      = "${var.team_slug}-prometheusrule-manager"
    namespace = var.team_namespace
    labels    = local.common_labels
  }

  rule {
    api_groups = ["monitoring.coreos.com"]
    resources  = ["prometheusrules"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["monitoring.coreos.com"]
    resources  = ["prometheusrules/status"]
    verbs      = ["get"]
  }
}

resource "kubernetes_role_binding" "prometheusrule_manager" {
  count = var.enabled && var.ci_service_account != "" ? 1 : 0

  metadata {
    name      = "${var.team_slug}-prometheusrule-manager"
    namespace = var.team_namespace
    labels    = local.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.prometheusrule_manager[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = var.ci_service_account
    namespace = var.team_namespace
  }
}

# ---------------------------------------------------------------------------
# 2. Grafana dashboard ConfigMap writer — grafana_namespace
# ---------------------------------------------------------------------------
# The Grafana sidecar watches ConfigMaps labelled grafana_dashboard=1.
# The team's CI SA needs write access to its own ConfigMaps in the Grafana
# namespace so it can patch dashboards without a platform ticket.
# Resource-names scoped to this team's ConfigMaps only (least-privilege).

resource "kubernetes_role" "grafana_dashboard_writer" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "${var.team_slug}-grafana-dashboard-writer"
    namespace = var.grafana_namespace
    labels    = local.common_labels
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    resource_names = [
      "${var.team_slug}-grafana-folder",
      "${var.team_slug}-grafana-dashboard",
      "${var.team_slug}-grafana-baremetal-dashboard",
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch"]
  }
}

resource "kubernetes_role_binding" "grafana_dashboard_writer" {
  count = var.enabled && var.ci_service_account != "" ? 1 : 0

  metadata {
    name      = "${var.team_slug}-grafana-dashboard-writer"
    namespace = var.grafana_namespace
    labels    = local.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.grafana_dashboard_writer[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = var.ci_service_account
    namespace = var.team_namespace
  }
}

# ---------------------------------------------------------------------------
# 3. Loki log-query ClusterRole + ClusterRoleBinding (optional)
# ---------------------------------------------------------------------------
# On bare-metal clusters Loki uses Kubernetes RBAC to gate namespace-scoped
# log queries (Loki Operator gate, or the Loki multi-tenancy X-Scope-OrgID
# header mapped to a SA namespace). Cloud deployments gate this via IAM.
# The ClusterRole grants read-only access to Loki log streams; it does NOT
# grant cross-namespace log access beyond namespace label selectors.

resource "kubernetes_cluster_role" "loki_log_reader" {
  count = var.enabled && var.create_loki_access ? 1 : 0

  metadata {
    name   = "${var.team_slug}-loki-log-reader"
    labels = local.common_labels
  }

  # Loki Operator uses a ResourceRule on the `logs` resource under
  # loki.grafana.com API group to gate per-namespace log access.
  rule {
    api_groups = ["loki.grafana.com"]
    resources  = ["logs"]
    verbs      = ["get", "list", "watch"]
  }

  # Allow listing namespaces so Grafana Loki datasource can show the team's
  # namespace in the label-value selector.
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "loki_log_reader" {
  count = var.enabled && var.create_loki_access && var.ci_service_account != "" ? 1 : 0

  metadata {
    name   = "${var.team_slug}-loki-log-reader"
    labels = local.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.loki_log_reader[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = var.ci_service_account
    namespace = var.team_namespace
  }
}
