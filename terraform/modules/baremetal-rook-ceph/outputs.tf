output "enabled" {
  description = "Whether Rook-Ceph was deployed."
  value       = var.enabled
}

output "namespace" {
  description = "Namespace Rook-Ceph runs in (null when disabled)."
  value       = var.enabled ? kubernetes_namespace.rook_ceph[0].metadata[0].name : null
}

output "rbd_prerequisite_satisfied" {
  description = "Confirms the rbd+ceph kernel-module prerequisite (ADR-0052) is satisfied — true means RBD PVCs can mount on the Talos nodes."
  value       = contains(var.ceph_kernel_modules, "rbd") && contains(var.ceph_kernel_modules, "ceph")
}

output "object_store_enabled" {
  description = "Whether the Ceph-RGW S3 object store was created (the optional WS-B artifact-store backend)."
  value       = local.deploy_object_store
}

output "s3_endpoint" {
  description = "In-cluster S3 endpoint for the RGW object store (null when the object store is disabled). Consumed by baremetal-ml-artifact-store / WS-B."
  value       = local.deploy_object_store ? "http://rook-ceph-rgw-${var.object_store_name}.${var.namespace}.svc:${var.rgw_port}" : null
}

output "rgw_bucket_name" {
  description = "Name of the Ceph-RGW object store / bucket (null when the object store is disabled). Consumed by baremetal-ml-monitoring (driftExporter.referenceBucketUri, ADR-0038) and other WS-B/WS-C units."
  value       = local.deploy_object_store ? var.object_store_name : null
}

output "block_pool_replicas" {
  description = "Replication factor of the Ceph pools."
  value       = var.block_pool_replicas
}

output "platform_labels" {
  description = "Effective ADR-0028 dotted labels."
  value       = local.platform_labels
}
