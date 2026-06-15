# aws-eks-inference-gateway (ArgoCD app)

> **ADR:** [0047](../../../docs/adrs/0047-eks-inference-serving-front-waf.md) (serving front), reusing Envoy Gateway ([0025](../../../docs/adrs/0025-envoy-gateway-secondary-l7.md)) and the `waf` module. **WS-A — ml-platform.**
> **Status:** GitOps delivery, **default-OFF** (`enabled: false`). Apply-gated — ArgoCD does not sync this until a human enables it on `main`.

The in-cluster (GitOps) companion to `terraform/modules/aws-eks-inference-gateway`. The Terraform module owns the `InferencePool` / `InferenceObjective` / EPP plumbing at plan time; this ArgoCD app owns the day-2 delivery + values onto the greenfield `aws-eks-gpu` cluster.

## What it renders (when `enabled: true`)

- **Gateway** (Envoy Gateway class by default, ADR-0047 D2; ALB class for the D3 fallback) + **HTTPRoute** binding it to the InferencePool.
- **InferencePool** (the vLLM replica set) + **InferenceObjective** *(v1 GA; was `InferenceModel`)* per workload/criticality — multi-LoRA → multiple objectives (ADR-0047 D1).
- **Endpoint Picker (EPP)** ConfigMap + Deployment + Service — deployed **explicitly** (ADR-0047 D2; not automatic). Routes on KV-cache + queue depth.
- **AWS WAF** (ADR-0047 D4): the reused `waf` module's WebACL ARN is annotated onto the Gateway (binds to the upstream LB). Start in `count` mode, then `block`.

## ADR-0028 taxonomy

Every object carries the dotted `platform.*` labels from `.Values.platformLabels` (`platform.system = ml-platform`, `platform.component = inference-gateway`).

## Pinning

The inference-extension CRD/EPP versions are pinned (`v1.0.0`) — no `latest`/`main` (ADR-0047 D1/Risks: CRD skew). Keep the cutover staged behind a canary; the vLLM `ClusterIP` path stays revertible (ADR-0047 D5).
