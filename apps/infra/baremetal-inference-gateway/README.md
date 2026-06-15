# baremetal-inference-gateway (ArgoCD app)

**Model-/KV-cache-aware serving front** for vLLM on the bare-metal cluster — the Gateway API
inference extension (`Gateway` / `InferencePool` / `InferenceObjective` / `HTTPRoute`) on
**Cilium or Envoy Gateway**, **not** a cloud LB. The on-prem mirror of `gke-inference-gateway`.
Part of **WS-A**. System: `ml-inference`.

**ADR:** [ADR-0053](../../../docs/adrs/0053-baremetal-gpu-fabric-roce-infiniband.md) (serving
axis: on-prem Gateway API, no cloud LB). ADR-0028 labels.

## Why on-prem Gateway API

There is no cloud L7 LB on owned hardware. Requests route on **KV-cache utilisation + queue
depth + per-replica load** (not round-robin) via the Gateway API inference extension, over
Cilium or Envoy Gateway. This app sits **behind** the `baremetal-ingress-waf` WAF/rate-limit
front.

> **Gateway API inference v1 GA:** `InferenceModel` was renamed **`InferenceObjective`**;
> `InferencePool` / `HTTPRoute` are unchanged.

## Objects

| Object | Purpose |
|--------|---------|
| `Gateway` | HTTPS serving entrypoint (Cilium/Envoy GatewayClass) |
| `InferencePool` | the vLLM replica set (selector + target port) |
| `InferenceObjective` (per model) | per-model routing + criticality (multi-LoRA) |
| `HTTPRoute` | binds the Gateway to the InferencePool |

## Apply-gated / default-OFF

`enabled: false` — ArgoCD does not sync until a human enables the app. Nothing is applied to
real hardware in this repo.

## ADR-0028 labeling

`platform.system = ml-inference`, `platform.component = inference-gateway`,
`platform.managed-by = argocd`.
