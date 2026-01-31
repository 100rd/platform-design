output "nodepool_names" {
  description = "Names of created Karpenter NodePools"
  value       = [for k, v in kubernetes_manifest.node_pool : v.manifest.metadata.name]
}

output "ec2_nodeclass_names" {
  description = "Names of created EC2NodeClasses"
  value       = [for k, v in kubernetes_manifest.ec2_node_class : v.manifest.metadata.name]
}
