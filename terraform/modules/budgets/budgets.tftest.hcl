mock_provider "aws" {}

variables {
  project = "test-project"
}

run "default_monthly_budget" {
  command = plan

  assert {
    condition     = var.monthly_budget_amount == "10000"
    error_message = "Default monthly budget should be $10,000"
  }
}

run "creates_monthly_total_budget" {
  command = plan

  assert {
    condition     = aws_budgets_budget.monthly_total.budget_type == "COST"
    error_message = "Monthly budget type should be COST"
  }
}

run "creates_budget_with_project_name" {
  command = plan

  assert {
    condition     = aws_budgets_budget.monthly_total.name == "test-project-monthly-total"
    error_message = "Budget name should include project name"
  }
}
