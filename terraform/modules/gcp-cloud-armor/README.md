# gcp-cloud-armor

Cloud Armor security policy for the **GPU Inference frontend** (ADR-0042 D5).

Puts a WAF / DDoS / per-client rate-limit layer in front of the GKE Inference Gateway
load balancer — the vLLM inference endpoint has none today. The policy is attached to the
Inference Gateway backend service (see `gke-inference-gateway`, which accepts a
`cloud_armor_policy_id`).

## What it creates

A single `google_compute_security_policy` (type `CLOUD_ARMOR`) with:

| Priority | Rule | Default |
|----------|------|---------|
| 1000 | Per-client rate-based ban (`deny(429)` above threshold) | 600 req / 60s, 300s ban |
| 2000+ | Preconfigured WAF deny rules (one per expression) | `sqli-v33-stable`, `xss-v33-stable` |
| 2147483647 | Default allow (explicit) | — |
| (config) | Adaptive Protection — ML L7 DDoS defense | enabled |

## Usage

```hcl
module "inference_armor" {
  source = "../../modules/gcp-cloud-armor"

  project_id           = var.project_id
  security_policy_name = "gpu-inference-armor"
  rate_limit_threshold = 600
  waf_preconfigured_rules = ["sqli-v33-stable", "xss-v33-stable"]

  labels = local.platform_labels # platform.system surfaced in the policy description
}
```

## ADR-0028 note

`google_compute_security_policy` does **not** support resource labels. The module accepts
a `labels` map for interface parity and surfaces `platform.system` in the policy
description for cost/ownership attribution.

## References

- ADR-0042 §D5 — Cloud Armor on the inference frontend.
- <https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_security_policy>
