# ---------------------------------------------------------------------------------------------------------------------
# Tests for the gcp-billing-budget module.
# Uses a mocked google provider so no real GCP credentials or billing account are
# required — these are plan-time assertions over the module's logic.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "google" {}

variables {
  billing_account_id = "0X0X0X-0X0X0X-0X0X0X"
  topic_project_id   = "test-ml-infra-gpu"
  monthly_amount     = 10000
  gpu_project_ids    = ["test-ml-infra-gpu", "test-ml-infra-gpu-eu"]

  labels = {
    platform_env   = "staging"
    platform_owner = "team-data"
  }
}

run "creates_default_three_thresholds" {
  command = plan

  assert {
    condition     = length(google_billing_budget.this.threshold_rules) == 3
    error_message = "Expected 3 threshold rules by default (0.8 / 1.0 / 1.2)."
  }
}

run "thresholds_match_80_100_120" {
  command = plan

  assert {
    condition = alltrue([
      for r in google_billing_budget.this.threshold_rules : contains([0.8, 1.0, 1.2], r.threshold_percent)
    ])
    error_message = "Threshold percentages must default to 0.8, 1.0 and 1.2."
  }
}

run "budget_scoped_to_gpu_projects" {
  command = plan

  assert {
    condition     = length(google_billing_budget.this.budget_filter[0].projects) == 2
    error_message = "Budget filter should be scoped to the two supplied GPU projects."
  }

  assert {
    condition     = contains(google_billing_budget.this.budget_filter[0].projects, "projects/test-ml-infra-gpu")
    error_message = "Budget filter must prefix project IDs with projects/."
  }
}

run "specified_amount_is_monthly_value" {
  command = plan

  assert {
    condition     = google_billing_budget.this.amount[0].specified_amount[0].units == "10000"
    error_message = "Specified amount units must equal the monthly_amount as a string."
  }
}

run "display_name_carries_platform_system" {
  command = plan

  assert {
    condition     = strcontains(google_billing_budget.this.display_name, "platform_system=ml-infra")
    error_message = "Budget display name must echo the ADR-0028 platform_system = ml-infra taxonomy."
  }
}

run "creates_pubsub_topic_with_platform_labels" {
  command = plan

  assert {
    condition     = length(google_pubsub_topic.budget_alerts) == 1
    error_message = "Pub/Sub topic should be created by default."
  }

  assert {
    condition     = google_pubsub_topic.budget_alerts[0].labels["platform_system"] == "ml-infra"
    error_message = "Pub/Sub topic must carry the ADR-0028 platform_system = ml-infra label."
  }
}

run "grants_billing_sa_publisher_on_topic" {
  command = plan

  assert {
    condition     = length(google_pubsub_topic_iam_member.budget_publisher) == 1
    error_message = "A Pub/Sub publisher binding should be created for the budget topic by default."
  }

  assert {
    condition     = google_pubsub_topic_iam_member.budget_publisher[0].role == "roles/pubsub.publisher"
    error_message = "The budget service agent must be granted roles/pubsub.publisher."
  }

  assert {
    condition     = google_pubsub_topic_iam_member.budget_publisher[0].member == "serviceAccount:cloud-billing-budgets@system.gserviceaccount.com"
    error_message = "Publisher binding must target the Cloud Billing budgets service agent."
  }
}

run "custom_thresholds_respected" {
  command = plan

  variables {
    threshold_percentages = [0.5, 0.9]
  }

  assert {
    condition     = length(google_billing_budget.this.threshold_rules) == 2
    error_message = "Custom threshold list should override the default three rules."
  }
}

run "reuses_existing_topic_when_create_disabled" {
  command = plan

  variables {
    create_pubsub_topic = false
    pubsub_topic_id     = "projects/test-ml-infra-gpu/topics/existing-budget-topic"
  }

  assert {
    condition     = length(google_pubsub_topic.budget_alerts) == 0
    error_message = "No Pub/Sub topic should be created when create_pubsub_topic = false."
  }

  assert {
    condition     = length(google_pubsub_topic_iam_member.budget_publisher) == 0
    error_message = "No publisher binding should be created when reusing an external topic."
  }

  assert {
    condition     = google_billing_budget.this.all_updates_rule[0].pubsub_topic == "projects/test-ml-infra-gpu/topics/existing-budget-topic"
    error_message = "Budget should notify the externally supplied topic when reuse is requested."
  }
}
