# ---------------------------------------------------------------------------------------------------------------------
# AWS Global Accelerator — Multi-Region Traffic Distribution
# ---------------------------------------------------------------------------------------------------------------------
# Creates a Global Accelerator with configurable listeners and per-region endpoint groups.
# Each endpoint group points to an NLB in the target region, enabling active-active
# multi-region routing with health-check-based failover.
#
# Flow logs are written to S3 for traffic analysis and compliance auditing.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# Accelerator
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_globalaccelerator_accelerator" "this" {
  count = var.enabled ? 1 : 0

  name            = var.name
  ip_address_type = var.ip_address_type
  enabled         = true

  attributes {
    flow_logs_enabled   = var.flow_logs_enabled
    flow_logs_s3_bucket = var.flow_logs_s3_bucket
    flow_logs_s3_prefix = var.flow_logs_s3_prefix
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Listeners — one per entry in var.listeners
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_globalaccelerator_listener" "this" {
  count = var.enabled ? length(var.listeners) : 0

  accelerator_arn = aws_globalaccelerator_accelerator.this[0].id
  protocol        = var.listeners[count.index].protocol
  client_affinity = var.listeners[count.index].client_affinity

  dynamic "port_range" {
    for_each = var.listeners[count.index].port_ranges
    content {
      from_port = port_range.value.from
      to_port   = port_range.value.to
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Endpoint Groups — one per region in var.endpoint_groups
# ---------------------------------------------------------------------------------------------------------------------
# Each endpoint group targets a single NLB (endpoint_id) in the specified region.
# Traffic dial percentage controls the fraction of traffic routed to each region.
# Set to 100 for both regions in a true active-active configuration.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_globalaccelerator_endpoint_group" "this" {
  for_each = var.enabled ? var.endpoint_groups : {}

  listener_arn                  = aws_globalaccelerator_listener.this[0].id
  endpoint_group_region         = each.key
  traffic_dial_percentage       = each.value.traffic_dial_percentage
  health_check_port             = each.value.health_check_port
  health_check_protocol         = each.value.health_check_protocol
  health_check_path             = each.value.health_check_protocol == "TCP" ? null : each.value.health_check_path
  health_check_interval_seconds = each.value.health_check_interval
  threshold_count               = each.value.threshold_count

  endpoint_configuration {
    endpoint_id = each.value.endpoint_id
    weight      = each.value.weight
  }
}
