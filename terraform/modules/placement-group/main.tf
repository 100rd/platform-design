# ---------------------------------------------------------------------------------------------------------------------
# AWS Placement Groups
# ---------------------------------------------------------------------------------------------------------------------
# Creates EC2 placement groups for controlling instance placement strategy.
#
# Strategies:
#   - cluster:   Pack instances close together for low-latency networking (single AZ)
#   - spread:    Distribute across distinct hardware (max 7 per AZ)
#   - partition:  Distribute across logical partitions (each partition on separate rack)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_placement_group" "this" {
  for_each = var.placement_groups

  name     = each.value.name
  strategy = each.value.strategy

  # partition_count only applies to partition strategy
  partition_count = each.value.strategy == "partition" ? each.value.partition_count : null

  # spread_level only applies to spread strategy
  spread_level = each.value.strategy == "spread" ? each.value.spread_level : null

  tags = merge(
    var.tags,
    {
      Name     = each.value.name
      Strategy = each.value.strategy
    }
  )
}
