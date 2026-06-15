# ---------------------------------------------------------------------------------------------------------------------
# Tests for the baremetal-gpu-scheduling module. helm + kubernetes providers are mocked;
# assertions run at plan time over Volcano + the UK queue taxonomy + DRA objects.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  enabled = true
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-data"
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(helm_release.volcano) == 0
    error_message = "No Volcano when enabled = false."
  }

  assert {
    condition     = length(kubernetes_manifest.volcano_queue) == 0
    error_message = "No queues when enabled = false."
  }
}

run "deploys_volcano_and_uk_queue_taxonomy" {
  command = plan

  assert {
    condition     = helm_release.volcano[0].version == var.volcano_chart_version
    error_message = "Volcano must use the pinned chart version."
  }

  # The UK taxonomy: 3 training + 4 serving = 7 queues (06-uk-datacenters.md).
  assert {
    condition     = length(kubernetes_manifest.volcano_queue) == 7
    error_message = "Exactly the 7 UK queues must be created (3 training + 4 serving)."
  }

  assert {
    condition     = contains(output.queue_names, "training-urgent") && contains(output.queue_names, "serving-vllm")
    error_message = "Queue taxonomy must include the named UK queues (training-urgent, serving-vllm, ...)."
  }
}

run "training_urgent_carries_job_cap" {
  command = plan

  # 06-uk-datacenters.md: training-urgent has weight 200 and a 2-job capability cap.
  assert {
    condition     = kubernetes_manifest.volcano_queue["training-urgent"].manifest.spec.weight == 200
    error_message = "training-urgent must have weight 200 per the UK taxonomy."
  }

  assert {
    condition     = kubernetes_manifest.volcano_queue["training-urgent"].manifest.spec.capability["volcano.sh/job-count"] == "2"
    error_message = "training-urgent must cap concurrent jobs at 2 per the UK taxonomy."
  }
}

run "dra_device_classes_and_claims" {
  command = plan

  # H100/H200/L40S + fractional → 4 device classes + 4 claim templates.
  assert {
    condition     = length(kubernetes_manifest.dra_device_class) == 4
    error_message = "DRA device classes for H100/H200/L40S + fractional must be created."
  }

  assert {
    condition     = length(kubernetes_manifest.dra_claim_template) == 4
    error_message = "One ResourceClaimTemplate per device class must be created."
  }

  assert {
    condition     = contains(output.device_class_names, "gpu-fractional")
    error_message = "A fractional-GPU device class must exist (folds gpu-inference-dra)."
  }
}

run "dra_can_be_disabled" {
  command = plan

  variables {
    dra_enabled = false
  }

  assert {
    condition     = length(kubernetes_manifest.dra_device_class) == 0
    error_message = "No DRA objects when dra_enabled = false."
  }

  # Queues still exist (Volcano scheduling is independent of DRA).
  assert {
    condition     = length(kubernetes_manifest.volcano_queue) == 7
    error_message = "Queues must still exist when DRA is disabled."
  }
}
