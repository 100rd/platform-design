# Tests for the baremetal-grafana-self-serve module.
# kubernetes provider is mocked — no cluster or credentials required.
#
# ADR-0039: Self-Serve Observability
# ADR-0028: platform.system = observability (mandatory label on every resource)

mock_provider "kubernetes" {}

variables {
  team_slug          = "team-baremetal-gpu"
  team_namespace     = "ml-baremetal"
  ci_service_account = "baremetal-gpu-ci"

  platform_labels = {
    "platform.env"   = "production"
    "platform.owner" = "team-baremetal-gpu"
  }
}

# ---------------------------------------------------------------------------
# disabled_creates_nothing: master toggle enforces apply-gated / default-OFF
# ---------------------------------------------------------------------------
run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(kubernetes_role.prometheusrule_manager) == 0
    error_message = "PrometheusRule manager Role must not be created when enabled=false."
  }

  assert {
    condition     = length(kubernetes_role_binding.prometheusrule_manager) == 0
    error_message = "PrometheusRule manager RoleBinding must not be created when enabled=false."
  }

  assert {
    condition     = length(kubernetes_role.grafana_dashboard_writer) == 0
    error_message = "Grafana dashboard writer Role must not be created when enabled=false."
  }

  assert {
    condition     = length(kubernetes_cluster_role.loki_log_reader) == 0
    error_message = "Loki log reader ClusterRole must not be created when enabled=false."
  }

  assert {
    condition     = length(kubernetes_cluster_role_binding.loki_log_reader) == 0
    error_message = "Loki log reader ClusterRoleBinding must not be created when enabled=false."
  }
}

# ---------------------------------------------------------------------------
# enabled_creates_rbac: enabled=true provisions all RBAC resources
# ---------------------------------------------------------------------------
run "enabled_creates_rbac" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(kubernetes_role.prometheusrule_manager) == 1
    error_message = "PrometheusRule manager Role must be created when enabled=true and ci_service_account is set."
  }

  assert {
    condition     = length(kubernetes_role_binding.prometheusrule_manager) == 1
    error_message = "PrometheusRule manager RoleBinding must be created when enabled=true and ci_service_account is set."
  }

  assert {
    condition     = length(kubernetes_role.grafana_dashboard_writer) == 1
    error_message = "Grafana dashboard writer Role must be created when enabled=true."
  }

  assert {
    condition     = length(kubernetes_cluster_role.loki_log_reader) == 1
    error_message = "Loki log reader ClusterRole must be created when enabled=true and create_loki_access=true (default)."
  }
}

# ---------------------------------------------------------------------------
# adr0028_labels: every resource carries platform.system = observability
# ---------------------------------------------------------------------------
run "adr0028_labels_on_prometheusrule_role" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = kubernetes_role.prometheusrule_manager[0].metadata[0].labels["platform.system"] == "observability"
    error_message = "PrometheusRule manager Role must carry platform.system = observability per ADR-0028."
  }

  assert {
    condition     = kubernetes_role.prometheusrule_manager[0].metadata[0].labels["platform.component"] == "self-serve"
    error_message = "PrometheusRule manager Role must carry platform.component = self-serve per ADR-0028."
  }
}

run "adr0028_labels_on_loki_clusterrole" {
  command = plan

  variables {
    enabled            = true
    create_loki_access = true
  }

  assert {
    condition     = kubernetes_cluster_role.loki_log_reader[0].metadata[0].labels["platform.system"] == "observability"
    error_message = "Loki ClusterRole must carry platform.system = observability per ADR-0028."
  }

  assert {
    condition     = kubernetes_cluster_role.loki_log_reader[0].metadata[0].labels["team"] == var.team_slug
    error_message = "Loki ClusterRole must carry the team label matching team_slug."
  }
}

# ---------------------------------------------------------------------------
# no_loki_when_disabled: create_loki_access=false skips Loki resources
# ---------------------------------------------------------------------------
run "no_loki_when_disabled" {
  command = plan

  variables {
    enabled            = true
    create_loki_access = false
  }

  assert {
    condition     = length(kubernetes_cluster_role.loki_log_reader) == 0
    error_message = "Loki ClusterRole must not be created when create_loki_access=false."
  }

  assert {
    condition     = length(kubernetes_cluster_role_binding.loki_log_reader) == 0
    error_message = "Loki ClusterRoleBinding must not be created when create_loki_access=false."
  }
}

# ---------------------------------------------------------------------------
# no_rbac_when_ci_sa_empty: optional CI SA skips RoleBindings but not Roles
# ---------------------------------------------------------------------------
run "no_rbac_when_ci_sa_empty" {
  command = plan

  variables {
    enabled            = true
    ci_service_account = ""
  }

  assert {
    condition     = length(kubernetes_role_binding.prometheusrule_manager) == 0
    error_message = "PrometheusRule RoleBinding must not be created when ci_service_account is empty."
  }

  assert {
    condition     = length(kubernetes_role_binding.grafana_dashboard_writer) == 0
    error_message = "Grafana dashboard RoleBinding must not be created when ci_service_account is empty."
  }

  assert {
    condition     = length(kubernetes_cluster_role_binding.loki_log_reader) == 0
    error_message = "Loki ClusterRoleBinding must not be created when ci_service_account is empty."
  }

  assert {
    condition     = length(kubernetes_role.grafana_dashboard_writer) == 1
    error_message = "Grafana dashboard Role must still be created even when ci_service_account is empty."
  }
}

# ---------------------------------------------------------------------------
# grafana_role_scoped_to_team_configmaps: least-privilege check
# ---------------------------------------------------------------------------
run "grafana_role_scoped_to_team_configmaps" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition = contains(
      tolist(kubernetes_role.grafana_dashboard_writer[0].rule[0].resource_names),
      "team-baremetal-gpu-grafana-baremetal-dashboard"
    )
    error_message = "Grafana dashboard writer Role must include the bare-metal dashboard ConfigMap name."
  }

  assert {
    condition = contains(
      tolist(kubernetes_role.grafana_dashboard_writer[0].rule[0].resource_names),
      "team-baremetal-gpu-grafana-folder"
    )
    error_message = "Grafana dashboard writer Role must include the folder ConfigMap name."
  }
}

# ---------------------------------------------------------------------------
# outputs_reflect_disabled_state
# ---------------------------------------------------------------------------
run "outputs_reflect_disabled_state" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = output.prometheusrule_role_name == ""
    error_message = "prometheusrule_role_name output must be empty string when disabled."
  }

  assert {
    condition     = output.loki_cluster_role_name == ""
    error_message = "loki_cluster_role_name output must be empty string when disabled."
  }

  assert {
    condition     = output.grafana_dashboard_role_name == ""
    error_message = "grafana_dashboard_role_name output must be empty string when disabled."
  }
}
