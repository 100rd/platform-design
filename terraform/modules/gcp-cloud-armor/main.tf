# ---------------------------------------------------------------------------------------------------------------------
# Cloud Armor security policy for the GPU Inference frontend (ADR-0042 D5)
# ---------------------------------------------------------------------------------------------------------------------
# Wraps google_compute_security_policy to put a WAF / DDoS / per-client rate-limit layer
# in front of the GKE Inference Gateway load balancer (today the vLLM inference endpoint
# has none). Attach the resulting policy to the Inference Gateway backend service.
#
# Rule layout (priority order):
#   1000          — per-client rate limit (throttle/deny above var.rate_limit_threshold)
#   2000+         — preconfigured WAF rules (var.waf_preconfigured_rules: sqli, xss, ...)
#   2147483647    — default allow (the implicit final rule, made explicit)
#
# Note: google_compute_security_policy does not support resource labels; ADR-0028
# attribution is carried in the policy/rule descriptions instead.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  system_tag = lookup(var.labels, "platform.system", "ml-infra")
}

resource "google_compute_security_policy" "this" {
  count = var.enabled ? 1 : 0

  project     = var.project_id
  name        = var.security_policy_name
  description = "ADR-0042 GPU inference WAF/DDoS/rate-limit (platform.system=${local.system_tag})"
  type        = "CLOUD_ARMOR"

  # ---------------------------------------------------------------------------
  # Adaptive Protection — ML-based L7 DDoS detection.
  # ---------------------------------------------------------------------------
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = var.enable_adaptive_protection
    }
  }

  # ---------------------------------------------------------------------------
  # Per-client rate limiting (priority 1000).
  # ---------------------------------------------------------------------------
  rule {
    action      = "rate_based_ban"
    priority    = 1000
    description = "Per-client rate limit for inference requests"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action   = "allow"
      exceed_action    = "deny(429)"
      enforce_on_key   = "IP"
      ban_duration_sec = var.rate_limit_ban_duration_sec

      rate_limit_threshold {
        count        = var.rate_limit_threshold
        interval_sec = var.rate_limit_interval_sec
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Preconfigured WAF rules (priority 2000+).
  # ---------------------------------------------------------------------------
  dynamic "rule" {
    for_each = { for idx, expr in var.waf_preconfigured_rules : idx => expr }
    content {
      action      = "deny(403)"
      priority    = 2000 + rule.key
      description = "Preconfigured WAF rule: ${rule.value}"

      match {
        expr {
          expression = "evaluatePreconfiguredExpr('${rule.value}')"
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Default rule — allow (made explicit, lowest priority).
  # ---------------------------------------------------------------------------
  rule {
    action      = "allow"
    priority    = 2147483647
    description = "Default allow"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
