# ---------------------------------------------------------------------------------------------------------------------
# Tests for the baremetal-rook-ceph module. helm + kubernetes providers are mocked;
# assertions run at plan time over the Ceph CRs and the load-bearing rbd+ceph prerequisite.
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
    condition     = length(helm_release.rook_ceph_operator) == 0
    error_message = "No Rook operator when enabled = false."
  }

  assert {
    condition     = length(kubernetes_manifest.ceph_cluster) == 0
    error_message = "No CephCluster when enabled = false."
  }

  assert {
    condition     = output.rgw_bucket_name == null
    error_message = "rgw_bucket_name must be null when the object store is not deployed."
  }
}

run "deploys_ceph_block_and_object" {
  command = plan

  assert {
    condition     = helm_release.rook_ceph_operator[0].version == var.chart_version
    error_message = "Rook operator must use the pinned chart version."
  }

  assert {
    condition     = length(kubernetes_manifest.ceph_block_pool) == 1
    error_message = "A replicated RBD block pool must be created."
  }

  # Ceph-RGW S3 object store on by default (WS-B artifact-store backend).
  assert {
    condition     = length(kubernetes_manifest.ceph_object_store) == 1
    error_message = "Ceph-RGW S3 object store must be created (WS-B artifact-store backend, ADR-0052)."
  }

  assert {
    condition     = output.s3_endpoint != null
    error_message = "An S3 endpoint must be surfaced when the object store is enabled."
  }

  # rgw_bucket_name is consumed by baremetal-ml-monitoring (driftExporter.referenceBucketUri, ADR-0038).
  assert {
    condition     = output.rgw_bucket_name == var.object_store_name
    error_message = "rgw_bucket_name must surface the object-store name when the object store is enabled (consumed by ml-monitoring)."
  }
}

run "rbd_prerequisite_enforced" {
  command = plan

  # ADR-0052 load-bearing gate: the module confirms rbd+ceph are declared upstream.
  assert {
    condition     = output.rbd_prerequisite_satisfied == true
    error_message = "rbd+ceph prerequisite must be satisfied (ADR-0052)."
  }
}

run "missing_rbd_module_fails_plan" {
  command = plan

  variables {
    # Simulate talos-machineconfig NOT declaring rbd → must fail (csi-rbdplugin would crash).
    ceph_kernel_modules = ["ceph"]
  }

  expect_failures = [var.ceph_kernel_modules]
}

run "replicas_below_three_rejected" {
  command = plan

  variables {
    block_pool_replicas = 2
  }

  expect_failures = [var.block_pool_replicas]
}
