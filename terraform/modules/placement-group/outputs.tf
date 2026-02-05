output "placement_group_names" {
  description = "Map of placement group key => name"
  value       = { for k, v in aws_placement_group.this : k => v.name }
}

output "placement_group_ids" {
  description = "Map of placement group key => id"
  value       = { for k, v in aws_placement_group.this : k => v.id }
}
