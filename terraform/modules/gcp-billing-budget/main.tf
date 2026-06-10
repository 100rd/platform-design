# ---------------------------------------------------------------------------------------------------------------------
# GCP Billing Budget Module (WS-A — ml-infra)
# ---------------------------------------------------------------------------------------------------------------------
# Creates a google_billing_budget on a billing account, scoped to one or more GPU
# projects, with threshold alerts at 80% / 100% / 120% of a specified monthly
# amount (configurable). Notifications are delivered to a Pub/Sub topic that an
# Alertmanager webhook bridge subscribes to (the topic is created here by default).
#
# ADR-0028 note: google_billing_budget does NOT support a `labels` argument, so the
# unified platform taxonomy labels (platform_system = ml-infra, etc.) are applied to
# the Pub/Sub notification topic — the only labelable resource in this module — and
# the taxonomy is echoed into the budget display name for billing-console grouping.
# GCP label keys use underscores (platform_system), not colons, because GCP labels
# disallow ':' — this is the GCP-plane spelling of the ADR-0028 keys.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Full Pub/Sub topic ID the budget notifies. Either the one we create, or a
  # pre-existing topic supplied by the caller.
  notification_topic_id = var.create_pubsub_topic ? google_pubsub_topic.budget_alerts[0].id : var.pubsub_topic_id

  # Google-managed Cloud Billing budgets service agent. It must be a Pub/Sub
  # publisher on the budget topic or notifications never fire.
  billing_budgets_sa = "serviceAccount:cloud-billing-budgets@system.gserviceaccount.com"

  # ADR-0028 baseline labels for the ml-infra system, merged with caller overrides.
  platform_labels = merge(
    {
      platform_system     = "ml-infra"
      platform_component  = "cost-control"
      platform_managed_by = "terragrunt"
    },
    var.labels,
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# Pub/Sub topic — budget notifications land here; Alertmanager webhook bridge subscribes.
# ---------------------------------------------------------------------------------------------------------------------

resource "google_pubsub_topic" "budget_alerts" {
  count = var.create_pubsub_topic ? 1 : 0

  project = var.topic_project_id
  name    = var.pubsub_topic_name

  labels = local.platform_labels
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM — grant the Cloud Billing budgets service agent publish rights on the topic.
# Without this binding the budget cannot publish notifications and the cost guardrail
# is inert. Only created when this module owns the topic (create_pubsub_topic = true);
# when reusing an external topic the caller must already grant this.
# ---------------------------------------------------------------------------------------------------------------------

resource "google_pubsub_topic_iam_member" "budget_publisher" {
  count = var.create_pubsub_topic ? 1 : 0

  project = var.topic_project_id
  topic   = google_pubsub_topic.budget_alerts[0].name
  role    = "roles/pubsub.publisher"
  member  = local.billing_budgets_sa
}

# ---------------------------------------------------------------------------------------------------------------------
# Billing budget — scoped to GPU project(s), with 0.8 / 1.0 / 1.2 threshold rules.
# ---------------------------------------------------------------------------------------------------------------------

resource "google_billing_budget" "this" {
  billing_account = var.billing_account_id
  display_name    = "${var.budget_display_name} [platform_system=ml-infra]"

  budget_filter {
    projects               = [for p in var.gpu_project_ids : "projects/${p}"]
    credit_types_treatment = var.credit_types_treatment
  }

  amount {
    specified_amount {
      currency_code = var.currency_code
      units         = tostring(var.monthly_amount)
    }
  }

  # One threshold rule per configured percentage (default 0.8 / 1.0 / 1.2),
  # evaluated against the forecasted spend so alerts fire ahead of overspend.
  dynamic "threshold_rules" {
    for_each = var.threshold_percentages
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "FORECASTED_SPEND"
    }
  }

  all_updates_rule {
    pubsub_topic                   = local.notification_topic_id
    schema_version                 = "1.0"
    disable_default_iam_recipients = var.disable_default_iam_recipients
  }
}
