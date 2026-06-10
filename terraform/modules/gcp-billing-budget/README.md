# gcp-billing-budget

Creates a GCP **billing budget** scoped to one or more GPU projects, with threshold
alerts at **80% / 100% / 120%** of a configurable monthly amount, delivered to a
**Pub/Sub topic** that an Alertmanager webhook bridge subscribes to.

Part of **WS-A** of the GCP ML Platform. System: `ml-infra`.

## What it creates

| Resource | Purpose |
|----------|---------|
| `google_billing_budget.this` | Budget on the billing account, filtered to GPU project(s), with forecasted-spend threshold rules. |
| `google_pubsub_topic.budget_alerts` (optional) | Notification topic for budget events. Created by default; set `create_pubsub_topic = false` to reuse an existing topic. |
| `google_pubsub_topic_iam_member.budget_publisher` (optional) | Grants the Cloud Billing budgets service agent `roles/pubsub.publisher` on the topic. Created only when this module owns the topic. |

## Alertmanager integration

GCP budget alerts are published to the Pub/Sub topic exposed as the `pubsub_topic_id`
output. A push subscription (or a Cloud Function / pubsub→webhook bridge) forwards
those messages to the Alertmanager webhook receiver. This module owns the topic and
its labels; the subscription/bridge is provisioned by the observability workstream.

**Publisher permission (required):** the Google-managed budgets service agent
`cloud-billing-budgets@system.gserviceaccount.com` must hold `roles/pubsub.publisher`
on the topic or notifications never fire. When this module creates the topic
(`create_pubsub_topic = true`) it also creates that binding. When reusing an external
topic, the caller must grant the binding themselves.

## ADR-0028 labeling

`google_billing_budget` has **no `labels` argument**, so the unified platform
taxonomy is applied where it can be:

- **Pub/Sub topic** carries the GCP-plane labels: `platform_system = ml-infra`,
  `platform_component = cost-control`, `platform_managed_by = terragrunt`, plus any
  caller overrides (e.g. `platform_env`, `platform_owner`).
- **Budget display name** echoes `[platform_system=ml-infra]` for billing-console
  grouping.

> GCP label **keys** use underscores (`platform_system`) rather than the colon form
> (`platform:system`) used for AWS tags, because GCP labels disallow `:`. This is the
> documented GCP-plane spelling of the ADR-0028 keys.

## Usage

```hcl
module "gpu_budget" {
  source = "../../terraform/modules/gcp-billing-budget"

  billing_account_id = "0X0X0X-0X0X0X-0X0X0X"
  topic_project_id   = "ml-infra-gpu-prod"
  monthly_amount     = 50000
  gpu_project_ids    = ["ml-infra-gpu-prod", "ml-infra-gpu-prod-eu"]

  labels = {
    platform_env   = "production"
    platform_owner = "team-data"
  }
}
```

## Inputs (key)

| Name | Description | Default |
|------|-------------|---------|
| `billing_account_id` | Billing account that owns the budget. | (required) |
| `monthly_amount` | Monthly budget amount in `currency_code`. | (required) |
| `gpu_project_ids` | GPU projects to scope the filter to (empty = whole account). | `[]` |
| `threshold_percentages` | Alert fractions of the monthly amount. | `[0.8, 1.0, 1.2]` |
| `create_pubsub_topic` | Create the notification topic + publisher binding in this module. | `true` |
| `topic_project_id` | Project that hosts the notification topic. | (required) |

## Outputs

| Name | Description |
|------|-------------|
| `budget_id` | Full budget resource ID. |
| `pubsub_topic_id` | Topic the budget notifies; subscribe Alertmanager here. |
| `threshold_percentages` | Configured threshold fractions. |

## Testing

```bash
terraform init -backend=false
terraform test
```

Tests use `mock_provider "google"` — no real GCP credentials, billing account, or
`terraform plan` against live infrastructure are required.
