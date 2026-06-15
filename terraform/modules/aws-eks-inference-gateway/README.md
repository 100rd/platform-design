# aws-eks-inference-gateway

> **ADR:** [0047](../../../docs/adrs/0047-eks-inference-serving-front-waf.md) D1 (Inference Extension), D2 (Envoy + EPP), D3 (ALB fallback), D4 (AWS WAF). Reuses Envoy Gateway ([0025](../../../docs/adrs/0025-envoy-gateway-secondary-l7.md)) + `waf`. **WS-A.**
> **Status:** plan/validate-only, **default-OFF** (`enabled = false`). Apply-gated.

Model-/KV-cache-aware serving front for vLLM on EKS — the AWS mirror of the GKE `gke-inference-gateway`, using the **v1 GA** Gateway API Inference Extension CRDs.

## What it does

- **Gateway** on **Envoy Gateway** (default, ADR-0047 D2 — the inference-extension reference plane; reuses ADR-0025) or **ALB** (fallback, D3).
- **InferencePool** (the vLLM replica set) + **InferenceObjective** *(v1 GA; was `InferenceModel`)* per workload/criticality (multi-LoRA → multiple objectives) + **HTTPRoute** binding the Gateway to the pool (ADR-0047 D1).
- **Endpoint Picker (EPP)** ext-proc Deployment + Service — deployed **explicitly** (the gateway does NOT install it; ADR-0047 D2). Routes on KV-cache utilisation + queue depth, not round-robin.
- **AWS WAF** (ADR-0047 D4): the reused `waf` module's WebACL ARN is wired onto the Gateway (binds to the upstream LB fronting Envoy). VPC Lattice is explicitly **not** the inference front (D5).
- Default-OFF keeps the vLLM `ClusterIP` path until the gateway is canary-proven (ADR-0047 D5, revertible).

## ADR-0028 taxonomy

Kubernetes-plane labels (dotted keys): `platform.system = ml-platform`, `platform.component = inference-gateway`, plus caller keys (on every serving object).

## Tests

`terraform test` (kubernetes mocked) asserts default-OFF, the Gateway/Pool/Route/EPP set, one v1-GA InferenceObjective per entry, the WAF annotation, and the EPP toggle.
