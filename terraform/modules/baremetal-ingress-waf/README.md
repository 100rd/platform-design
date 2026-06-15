# baremetal-ingress-waf

**On-prem WAF / rate-limit** at the serving edge — the bare-metal mirror of Cloud Armor.
Part of **WS-A** of the Bare-Metal ML Platform. System: `ml-inference`.

**ADRs:** [ADR-0053](../../../docs/adrs/0053-baremetal-gpu-fabric-roce-infiniband.md)
(serving axis: on-prem Gateway API + WAF/rate-limit, no cloud LB). ADR-0028 labels.

## Why an on-prem WAF

There is **no Cloud Armor and no cloud LB** on owned hardware. This module provides the
WAF/rate-limit front for the serving edge over the Gateway API, with two backends:

| `gateway_backend` | What it uses | Rate-limit |
|-------------------|--------------|------------|
| `cilium` (default) | Cilium Gateway — one networking stack (Cilium is already the CNI) | `CiliumNetworkPolicy` L7 ingress |
| `envoy` | Envoy Gateway (reuse `apps/infra/envoy-gateway`) | Envoy `BackendTrafficPolicy` local rate-limit |

The model-serving Gateway/HTTPRoute themselves live in the `baremetal-inference-gateway`
ArgoCD app; this module is the **WAF/rate-limit + TLS-terminating front** in front of them.

## What it creates (when `enabled = true`)

| Resource | Purpose |
|----------|---------|
| `kubernetes_manifest.gateway` | HTTPS-terminating serving Gateway |
| `kubernetes_manifest.cilium_ratelimit` | (cilium backend) L7 rate-limit policy |
| `kubernetes_manifest.envoy_ratelimit` | (envoy backend) rate-limit policy |

TLS terminates with a secret from cert-manager/ESO (`tls_secret_name`) — never committed.

## Apply-gated

`var.enabled` defaults **false**. Provider mocked at plan time — no live cluster. No
`terraform apply` in this repo.

## ADR-0028 labeling

Dotted keys: `platform.system = ml-inference`, `platform.component = ingress-waf`,
`platform.managed-by = terragrunt`, plus `platform_labels` overrides.

## Testing

```bash
terraform init -backend=false
terraform test
```
