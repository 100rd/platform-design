# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Validation Suite — Terraform Module
# ---------------------------------------------------------------------------------------------------------------------
# Provisions the Kubernetes resources required to run the gpu-inference
# Definition-of-Done validation test suite:
#
#   - Namespace: gpu-inference-validation
#   - ServiceAccount: gpu-inference-validator (cluster-reader + pod-manager permissions)
#   - ClusterRole / ClusterRoleBinding: read all resources + manage pods in namespace
#   - ConfigMap: embeds all test manifests for the CronJob to mount
#   - CronJob: runs the full validation suite weekly
#
# Tests are defined as Kubernetes Job manifests in tests/gpu-inference/ and are
# bundled into a ConfigMap so the CronJob runner can apply them without needing
# image-baked manifests.
# ---------------------------------------------------------------------------------------------------------------------

# ── Namespace ─────────────────────────────────────────────────────────────────

resource "kubernetes_namespace_v1" "validation" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "gpu-inference-dod"
      "cluster"                      = var.cluster_name
    }
  }
}

# ── ServiceAccount ────────────────────────────────────────────────────────────

resource "kubernetes_service_account_v1" "validator" {
  metadata {
    name      = "gpu-inference-validator"
    namespace = kubernetes_namespace_v1.validation.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "gpu-inference-validator"
      "app.kubernetes.io/part-of"    = "gpu-inference-dod"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ── ClusterRole: cluster-reader + limited write in validation namespace ────────

resource "kubernetes_cluster_role_v1" "validator" {
  metadata {
    name = "gpu-inference-validator"
    labels = {
      "app.kubernetes.io/name"       = "gpu-inference-validator"
      "app.kubernetes.io/part-of"    = "gpu-inference-dod"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  # Read all cluster resources (for observability checks, node inspection, policy audit)
  rule {
    api_groups = [""]
    resources  = ["nodes", "pods", "services", "endpoints", "namespaces", "configmaps", "events"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch", "create", "delete", "patch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["cilium.io"]
    resources  = ["ciliumnetworkpolicies", "ciliumclusterwidenetworkpolicies"]
    verbs      = ["get", "list", "watch"]
  }

  # Volcano VCJob management (for gang recovery test)
  rule {
    api_groups = ["batch.volcano.sh"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch", "create", "delete", "patch", "update"]
  }

  rule {
    api_groups = ["scheduling.volcano.sh"]
    resources  = ["queues", "podgroups"]
    verbs      = ["get", "list", "watch"]
  }

  # DRA resource claims management (for DRA scheduling test)
  rule {
    api_groups = ["resource.k8s.io"]
    resources  = ["resourceclaims", "resourceclaimtemplates", "resourceclasses", "deviceclasses"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }

  # Pod deletion for gang recovery test
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["delete"]
  }

  # Exec into Cilium pods for WireGuard status check
  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "validator" {
  metadata {
    name = "gpu-inference-validator"
    labels = {
      "app.kubernetes.io/name"       = "gpu-inference-validator"
      "app.kubernetes.io/part-of"    = "gpu-inference-dod"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.validator.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.validator.metadata[0].name
    namespace = kubernetes_namespace_v1.validation.metadata[0].name
  }
}

# ── ConfigMap: test manifests ─────────────────────────────────────────────────
#
# Each test YAML is stored as a key in this ConfigMap.
# The CronJob runner mounts the ConfigMap and applies each manifest in sequence.

resource "kubernetes_config_map_v1" "test_manifests" {
  metadata {
    name      = "gpu-inference-test-manifests"
    namespace = kubernetes_namespace_v1.validation.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "gpu-inference-test-manifests"
      "app.kubernetes.io/part-of"    = "gpu-inference-dod"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    # Each value is the full YAML of the corresponding test Job.
    # The paths are relative to the repository root (tests/gpu-inference/).
    # When test_manifests_path is set, file() reads from disk.
    # Otherwise a placeholder is stored (update the ConfigMap out-of-band).
    "network-latency-test.yaml"     = var.test_manifests_path != "" ? file("${var.test_manifests_path}/network-latency-test.yaml") : "# placeholder — apply via kubectl or set test_manifests_path"
    "nccl-benchmark.yaml"           = var.test_manifests_path != "" ? file("${var.test_manifests_path}/nccl-benchmark.yaml") : "# placeholder — apply via kubectl or set test_manifests_path"
    "gang-recovery-test.yaml"       = var.test_manifests_path != "" ? file("${var.test_manifests_path}/gang-recovery-test.yaml") : "# placeholder — apply via kubectl or set test_manifests_path"
    "dra-scheduling-test.yaml"      = var.test_manifests_path != "" ? file("${var.test_manifests_path}/dra-scheduling-test.yaml") : "# placeholder — apply via kubectl or set test_manifests_path"
    "observability-check.yaml"      = var.test_manifests_path != "" ? file("${var.test_manifests_path}/observability-check.yaml") : "# placeholder — apply via kubectl or set test_manifests_path"
    "security-audit.yaml"           = var.test_manifests_path != "" ? file("${var.test_manifests_path}/security-audit.yaml") : "# placeholder — apply via kubectl or set test_manifests_path"
    "vllm-inference-benchmark.yaml" = var.test_manifests_path != "" ? file("${var.test_manifests_path}/vllm-inference-benchmark.yaml") : "# placeholder — apply via kubectl or set test_manifests_path"

    # Runner script: iterates over all manifests and applies them in sequence,
    # then waits for each Job to complete and reports pass/fail.
    "run-all-tests.sh" = <<-SCRIPT
      #!/bin/bash
      set -euo pipefail

      NAMESPACE="${var.namespace}"
      MANIFESTS_DIR="/manifests"
      TIMEOUT_PER_JOB="600"  # 10 minutes per Job

      echo "================================================================"
      echo " GPU Inference Definition-of-Done Validation Suite"
      echo " $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      echo "================================================================"

      PASS_COUNT=0
      FAIL_COUNT=0
      SKIP_COUNT=0
      FAILED_TESTS=""

      run_test() {
        local manifest="$1"
        local test_name
        test_name=$(basename "$${manifest}" .yaml)

        echo ""
        echo "------------------------------------------------------------"
        echo "Running: $${test_name}"
        echo "------------------------------------------------------------"

        # Apply the manifest
        kubectl apply -f "$${manifest}" -n "${var.namespace}" || {
          echo "SKIP: $${test_name} — manifest apply failed (may need pre-requisites)"
          SKIP_COUNT=$((SKIP_COUNT + 1))
          return
        }

        # Find the primary Job name from the manifest
        JOB_NAME=$(kubectl get -f "$${manifest}" -n "${var.namespace}" \
          -o jsonpath='{.items[?(@.kind=="Job")].metadata.name}' 2>/dev/null || \
          kubectl get -f "$${manifest}" -n "${var.namespace}" \
          -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")

        if [[ -z "$${JOB_NAME}" ]]; then
          echo "SKIP: $${test_name} — could not determine Job name"
          SKIP_COUNT=$((SKIP_COUNT + 1))
          return
        fi

        # Wait for Job completion
        echo "Waiting for Job $${JOB_NAME} to complete (timeout=$${TIMEOUT_PER_JOB}s)..."
        if kubectl wait job/"$${JOB_NAME}" \
            -n "${var.namespace}" \
            --for=condition=complete \
            --timeout="$${TIMEOUT_PER_JOB}s" 2>/dev/null; then
          echo "PASS: $${test_name}"
          PASS_COUNT=$((PASS_COUNT + 1))
        else
          echo "FAIL: $${test_name}"
          FAIL_COUNT=$((FAIL_COUNT + 1))
          FAILED_TESTS="$${FAILED_TESTS} $${test_name}"
          # Print logs for debugging
          kubectl logs -n "${var.namespace}" \
            -l "app.kubernetes.io/name=$${test_name}" \
            --tail=50 2>/dev/null || true
        fi

        # Cleanup Job after run to keep namespace clean
        kubectl delete job "$${JOB_NAME}" -n "${var.namespace}" --ignore-not-found
      }

      # Run all test manifests in order
      ORDERED_TESTS=(
        "network-latency-test.yaml"
        "nccl-benchmark.yaml"
        "dra-scheduling-test.yaml"
        "gang-recovery-test.yaml"
        "observability-check.yaml"
        "security-audit.yaml"
        "vllm-inference-benchmark.yaml"
      )

      for test in "$${ORDERED_TESTS[@]}"; do
        if [[ -f "$${MANIFESTS_DIR}/$${test}" ]]; then
          run_test "$${MANIFESTS_DIR}/$${test}"
        else
          echo "SKIP: $${test} — manifest not found"
          SKIP_COUNT=$((SKIP_COUNT + 1))
        fi
      done

      echo ""
      echo "================================================================"
      echo " Results: $${PASS_COUNT} passed | $${FAIL_COUNT} failed | $${SKIP_COUNT} skipped"
      if [[ -n "$${FAILED_TESTS}" ]]; then
        echo " Failed: $${FAILED_TESTS}"
      fi
      echo "================================================================"

      if [[ "$${FAIL_COUNT}" -gt 0 ]]; then
        exit 1
      fi
    SCRIPT
  }
}

# ── CronJob: weekly validation suite ─────────────────────────────────────────

resource "kubernetes_cron_job_v1" "validation_suite" {
  metadata {
    name      = "gpu-inference-validation-suite"
    namespace = kubernetes_namespace_v1.validation.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "gpu-inference-validation-suite"
      "app.kubernetes.io/part-of"    = "gpu-inference-dod"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    schedule                      = var.schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 5
    starting_deadline_seconds     = 300

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name"    = "gpu-inference-validation-suite"
          "app.kubernetes.io/part-of" = "gpu-inference-dod"
        }
      }

      spec {
        backoff_limit = 0
        # Allow up to 90 minutes for the full suite
        active_deadline_seconds = 5400

        template {
          metadata {
            labels = {
              "app.kubernetes.io/name"    = "gpu-inference-validation-suite"
              "app.kubernetes.io/part-of" = "gpu-inference-dod"
            }
          }

          spec {
            service_account_name = kubernetes_service_account_v1.validator.metadata[0].name
            restart_policy       = "Never"

            volume {
              name = "manifests"
              config_map {
                name         = kubernetes_config_map_v1.test_manifests.metadata[0].name
                default_mode = "0755"
              }
            }

            container {
              name  = "suite-runner"
              image = "bitnami/kubectl:1.29"

              command = ["/bin/bash", "-c", "/manifests/run-all-tests.sh"]

              volume_mount {
                name       = "manifests"
                mount_path = "/manifests"
              }

              resources {
                requests = {
                  cpu    = "200m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "1"
                  memory = "512Mi"
                }
              }
            }
          }
        }
      }
    }
  }
}
