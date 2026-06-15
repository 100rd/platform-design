# gke-inference-gateway

Model-/KV-cache-aware serving front for vLLM using the **GKE Inference Gateway**
(Gateway API inference extension) — ADR-0042 D4.

Replaces the plain `ClusterIP` front (`gpu-inference-vllm`) so requests route on **KV-cache
utilisation, queue depth, and per-replica load** instead of round-robin, and so multiple
models / LoRA adapters route cleanly by name.

## What it creates

| Object | Purpose |
|--------|---------|
| `Gateway` | GKE inference GatewayClass entrypoint (+ Body-Based Router annotation) |
| `InferencePool` | the set of vLLM replicas (selector + target port + endpoint-picker ref) |
| `InferenceObjective` (per entry) | external model name → served target model + criticality |
| `HTTPRoute` | binds the Gateway to the InferencePool |
| `GCPBackendPolicy` | attaches the Cloud Armor policy (when `cloud_armor_policy_id` is set) |

## vLLM coupling

vLLM keeps its existing pod labels (`inference_pool_selector`, default `app=vllm`),
VictoriaMetrics scrape, and DRA GPU claim. Cut over by pointing clients at the Gateway;
keep the `ClusterIP` Service until the gateway is canary-proven (revertible — `enabled=false`).

## Usage

```hcl
module "inference_gateway" {
  source = "../../modules/gke-inference-gateway"

  namespace = "gpu-inference"
  inference_models = [
    { name = "domain-adapter", model_name = "domain-adapter", target_model = "domain-adapter-v3", criticality = "Critical" },
  ]
  cloud_armor_policy_id = module.inference_armor.security_policy_id # ADR-0042 D5
  platform_labels       = local.platform_labels
}
```

## Testing

`terraform test` mocks the kubernetes provider — no cluster needed. Against a real
cluster, `kubernetes_manifest` requires the Gateway API + inference CRDs to exist at plan
time (install the GKE Inference Gateway CRDs first).

## References

- ADR-0042 §D4 — GKE Inference Gateway.
- <https://cloud.google.com/kubernetes-engine/docs/concepts/about-gke-inference-gateway>
- <https://docs.cloud.google.com/architecture/networking-for-ai-inference>
