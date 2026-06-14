# ADR-0047: EKS inference serving front — Gateway API Inference Extension (InferencePool/InferenceObjective) on Envoy Gateway, with AWS WAF; ALB + VPC Lattice as alternatives

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — the greenfield `aws-eks-gpu-*` ML cluster
  has **no serving front defined**: no Gateway, no model-aware routing, no WAF on
  any inference endpoint. The repo already runs **Cilium Gateway API**
  ([ADR-0009](0009-cilium-gateway-api-ingress.md)) as the primary ingress, an
  **Envoy Gateway** secondary L7 ([ADR-0025](0025-envoy-gateway-secondary-l7.md)),
  **VPC Lattice** for resource connectivity ([ADR-0023](0023-vpc-lattice-resource-connectivity.md)),
  and a generic **`waf`** module; none is wired to a model-/cache-aware inference
  router, and the existing `gpu-inference-vllm` exposes a plain `ClusterIP`.
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: mirrors the **serving half** of
  [ADR-0042](0042-gpu-inference-networking-serving-uplift.md) (GKE Inference Gateway
  + Cloud Armor) for AWS; extends WS-A on the serving axis; consumes the EFA fabric
  ([ADR-0045](0045-aws-efa-gpu-fabric-placement-groups.md)); plan §7 OPEN DECISION
  "serving front (3 options)".
- Supersedes: (none)
- Superseded by: (none)

## Context

[ADR-0042](0042-gpu-inference-networking-serving-uplift.md) D4/D5 (the GKE etalon)
replaces the naive vLLM `ClusterIP` with the **GKE Inference Gateway**
(Gateway API inference extension: `InferencePool` + per-model routing objects +
KV-cache-aware endpoint picking) fronted by **Cloud Armor** (WAF/DDoS/rate
limit). This ADR is the **AWS mirror of that serving half**. The fabric half of
ADR-0042 already maps to [ADR-0045](0045-aws-efa-gpu-fabric-placement-groups.md);
together they cover all of ADR-0042 on AWS.

**The serving front is the throughput/latency lever for LLM inference.** A naive L4
`ClusterIP` / round-robin LB is **model-blind and cache-blind**: it cannot route on
KV-cache locality, queue depth, model identity, or per-replica GPU load — which is
the entire point of an inference-aware gateway. The win is the same one ADR-0042
documents: an **endpoint picker** that turns live model-server metrics
(KV-cache utilisation, queue length) into routing decisions.

The key enabling fact (current as of 2026): the **Gateway API Inference Extension**
(`kubernetes-sigs/gateway-api-inference-extension`) is **v1 GA** and
**vLLM-integrated via llm-d**. Its objects — **`InferencePool`** (a set of
model-server replicas sharing accelerator + base model; graduated to v1/stable),
**`InferenceObjective`** *(v1 GA renamed `InferenceModel` → `InferenceObjective`;
the per-workload routing/criticality object)*, and the **Endpoint Picker (EPP)**
(tracks KV-cache + queue-length per replica, routes to the optimal one) — are the
*exact* AWS-portable analog of the GKE Inference Gateway's
`InferencePool`/per-model-routing/body-based routing. **A `HTTPRoute` attaches the
`InferencePool` to the `Gateway`** as with any Gateway API backend. Crucially,
**the inference extension is implementation-agnostic**: it layers on top of *any*
Gateway API implementation. So the AWS decision is **not** "inference gateway
yes/no" (yes — same as GKE) but **which Gateway API data plane** hosts it, and
**which WAF**.

> **CRD-naming note for impl:** this ADR uses the **v1 GA** names. `InferenceModel`
> was **renamed to `InferenceObjective`** at v1 GA and `InferencePool` graduated to
> v1; an implementation must use the v1 CRDs (`InferencePool` + `InferenceObjective`,
> attached via `HTTPRoute`), following the project's
> [v1alpha2→v1 GA migration guide](https://gateway-api-inference-extension.sigs.k8s.io/guides/ga-migration/).
> Pin the extension/CRD version explicitly (no `main`).

AWS gives **three** viable Gateway API data planes, and the repo already runs the
machinery for all three — which is why the platform owner flagged this as an OPEN
DECISION (plan §7):

| Option | Data plane | In-repo today | Inference-extension support | WAF integration |
|---|---|---|---|---|
| **ALB + Gateway API** | AWS Load Balancer Controller → ALB | `waf` module; ALB ingress patterns | EPP via the LBC Gateway API (managed ALB L7) | **AWS WAF** native (WebACL → ALB) |
| **Envoy Gateway + Gateway API** | In-cluster Envoy (Gateway API) | **[ADR-0025](0025-envoy-gateway-secondary-l7.md)** Envoy Gateway secondary L7 already adopted | First-class — the inference extension's reference data plane is Envoy-based (EPP as ext-proc) | AWS WAF via an upstream ALB/NLB, or Envoy-native rules |
| **VPC Lattice + Gateway API** | AWS VPC Lattice (`application-networking` GW controller) | **[ADR-0023](0023-vpc-lattice-resource-connectivity.md)** VPC Lattice for resource connectivity | Limited — Lattice is service-networking, not an LLM endpoint picker | AWS WAF (WebACL → Lattice, where supported) |

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) labels are
mandatory on every Gateway, route, WAF WebACL, and inference object here, exactly as
Cloud Armor + the Inference Gateway carry them in ADR-0042.

## Decision

Adopt the **Gateway API Inference Extension** (`InferencePool` / `InferenceObjective`
/ Endpoint Picker) as the model-/cache-aware serving front — the AWS mirror of
ADR-0042 D4 — on **Envoy Gateway** as the default data plane, fronted by **AWS WAF**.
**ALB + Gateway API** is the documented fallback; **VPC Lattice** is explicitly
**not** the inference front. Five plan/validate-only sub-decisions.

### D1 — Serving front = Gateway API Inference Extension (not a plain LB) — locked, same as ADR-0042 D4

Replace any `ClusterIP` / round-robin front for vLLM with the **Gateway API
Inference Extension**:

- **`InferencePool`** = the set of vLLM replicas (same accelerator + base model)
  on the GPU pools (ADR-0044/0046), attached to the `Gateway` via an `HTTPRoute`.
- **`InferenceObjective`** *(v1 GA name; was `InferenceModel`)* = per-workload
  routing + criticality + LoRA-adapter traffic split (multi-LoRA → multiple
  `InferenceObjective`s, exactly as ADR-0042 D4 maps multi-LoRA to multiple per-model
  routing objects on GKE).
- **Endpoint Picker (EPP)** routes on **KV-cache utilisation + queue depth +
  per-replica load**, not round-robin — the throughput/latency win. The EPP is a
  **separately-deployed component** (see D2 / the module contract) — it is *not*
  installed automatically by the gateway.
- vLLM serving is an `InferencePool` member; its metrics scrape and DRA GPU claim
  (ADR-0044) are unchanged.

This decision is **locked** (the inference extension is v1 GA + vLLM-integrated and
is the only thing that delivers cache-aware routing); only the *data plane* (D2) and
*WAF* (D4) are the AWS-specific choices.

### D2 — Default data plane: Envoy Gateway (Gateway API) — reuse ADR-0025

Run the inference extension on **Envoy Gateway**, the in-cluster Gateway API data
plane the repo **already adopted** as its secondary L7
([ADR-0025](0025-envoy-gateway-secondary-l7.md)):

- The inference extension's **reference data plane is Envoy-based** — the EPP is an
  Envoy **ext-proc** external processor. Envoy Gateway is therefore the **lowest-
  friction, highest-fidelity** host for `InferencePool`/`InferenceObjective`/EPP,
  with the richest support for the extension's routing semantics.
- **The EPP must be explicitly deployed and wired.** It is a distinct workload (the
  endpoint-picker ext-proc Deployment + its Service) that Envoy Gateway is configured
  to call out to for the `InferencePool` — installing Envoy Gateway and the CRDs is
  **not** sufficient on its own. The `aws-eks-inference-gateway` module
  (Implementation notes) ships the EPP Deployment/Service and the
  Envoy-Gateway/`InferencePool` extension wiring as a named, first-class component so
  impl does not miss it.
- **Reuse, not new adoption:** ADR-0025 already brings Envoy Gateway into the
  estate; this ADR uses it for the inference front rather than introducing a new L7.
- It keeps the cache-aware routing logic **in-cluster** (close to the GPU pods and
  their metrics), avoiding a round-trip to a managed L7 for every routing decision —
  the AWS analog of the GKE Inference Gateway's in-cluster endpoint picker.

Chosen over **ALB + Gateway API** as the *default* because the inference extension
is Envoy-native; ALB's managed L7 supports the Gateway API but the endpoint-picker
integration is less direct. ALB remains the **fallback** (D3).

### D3 — Fallback data plane: ALB + Gateway API (AWS Load Balancer Controller)

Where a team needs a **managed, internet-facing L7 with native AWS WAF** and does
not need the deepest EPP integration (e.g. a simpler single-model endpoint, or an
org standard mandating ALB), use the **AWS Load Balancer Controller's Gateway API**
→ **ALB**, with the inference extension layered on where supported. This is the
pragmatic AWS-managed path and the **natural home for AWS WAF** (D4). It is the
fallback, not the default, because the EPP/Envoy integration (D2) is tighter for the
cache-aware routing that is the whole point.

### D4 — WAF on the inference frontend: AWS WAF (the Cloud Armor mirror) — reuse `waf`

Front the inference endpoint with **AWS WAF** (the AWS analog of ADR-0042 D5's Cloud
Armor), **reusing the existing `waf` module** (`aws_wafv2_web_acl`): WAF managed
rule groups + **per-client rate limiting** (the module's `rate_limit`, default
2000/5-min) + logging (the module's `log_retention_days`, default 365). The WebACL
binds to the serving front's load balancer:

- **ALB path (D3):** native — `aws_wafv2_web_acl_association` → ALB. The
  straightforward AWS WAF integration.
- **Envoy path (D2):** AWS WAF binds to the **upstream ALB/NLB** that fronts the
  Envoy Gateway (Envoy sits behind an LB for internet exposure), so WAF still
  guards the edge; Envoy-native rate-limit/auth can complement in-cluster.

This reuses the existing `waf` module rather than building a new one (the same
"reuse the native primitive" logic as ADR-0044 D4 reusing `budgets` instead of
cloning `gcp-billing-budget`). **Model-safety screening** (the AWS analog of
ADR-0042's optional Model Armor — e.g. Bedrock Guardrails or a safety ext-proc) is
kept **optional**, behind a confirmed safety requirement, to avoid hot-path latency
without a driver (mirrors ADR-0042 D5).

### D5 — Reaffirm scope guards (locked)

- **VPC Lattice is NOT the inference front.** [ADR-0023](0023-vpc-lattice-resource-connectivity.md)
  uses Lattice for **resource/service connectivity** (east-west service networking),
  not LLM endpoint picking — Lattice has no KV-cache-aware router. It stays in its
  ADR-0023 role; it is **not** an option for D1's model-aware front. (Recorded so the
  three-way OPEN DECISION resolves cleanly: Envoy default, ALB fallback, Lattice out.)
- **Heavyweight API management (e.g. full API Gateway monetisation/Apigee-equivalent)
  is out of scope** — AWS WAF covers WAF/DDoS/rate-limit, which is the actual gap
  (mirrors ADR-0042 A6). Revisit on a confirmed quota/monetisation requirement.
- **Disaggregated prefill/decode is deferred** to a follow-up ADR (depends on this +
  the EFA fabric landing). Mirrors ADR-0042 D6.
- **Serving cutover is staged + revertible:** keep the `ClusterIP` path behind a flag
  until the gateway is canary-proven under load (mirrors ADR-0042 D4/Risks).
- **[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) labels
  mandatory** on every Gateway, route, `InferencePool`/`InferenceObjective`, WAF
  WebACL.

A reviewer checks conformance by confirming: (a) vLLM is served via
`InferencePool`/`InferenceObjective` + EPP, not `ClusterIP` (D1); (b) the default
data plane is Envoy Gateway reusing ADR-0025 **with the EPP deployed and wired**
(D2); (c) ALB+GatewayAPI is wired as the documented fallback (D3); (d) an AWS WAF
WebACL (reusing `waf`) binds to the serving LB with rate limiting (D4); (e) VPC
Lattice is not used as the model front (D5); (f) every serving resource carries the
five ADR-0028 labels.

## Alternatives considered

### A1 — Plain ALB / NLB `ClusterIP` round-robin (no inference extension)
Add a generic L7/L4 LB but no inference-aware routing.
*Rejected because:* model-blind + cache-blind — it cannot route on KV-cache locality,
queue depth, or model identity, which is the entire throughput/latency win. The
inference extension's EPP is the mechanism that turns GPU/model metrics into routing.
(Direct mirror of ADR-0042 A4.)

### A2 — ALB + Gateway API as the *default* (managed L7 first)
Make the AWS-managed ALB the primary inference data plane.
*Rejected as default (kept as fallback, D3) because:* the inference extension is
**Envoy-native** (EPP = Envoy ext-proc), so Envoy Gateway hosts the cache-aware
routing with the highest fidelity and lowest friction, and the repo already runs
Envoy Gateway (ADR-0025). ALB's managed L7 supports Gateway API but the
endpoint-picker integration is less direct. ALB is the right **fallback** for
managed/WAF-native/simple-endpoint cases.

### A3 — VPC Lattice + Gateway API as the inference front
Use VPC Lattice (ADR-0023) for the model-aware serving front.
*Rejected because:* Lattice is **service-networking**, not an LLM endpoint picker —
it has no KV-cache/queue-aware routing and is not a data plane the inference
extension targets for cache-aware serving. It keeps its ADR-0023 east-west role. (D5
records this so the three-option decision closes.)

### A4 — Service mesh (Istio/Cilium mesh) model routing instead of the inference extension
Implement model-aware routing in a mesh.
*Rejected as the primary path because:* the **Gateway API Inference Extension** is
purpose-built for LLM serving (InferencePool/InferenceObjective + KV-cache-aware EPP
+ vLLM/llm-d integration) and is the v1 GA, vendor-neutral standard; a mesh would
re-implement this with more moving parts. (Cilium Gateway API, ADR-0009, remains the
*general* ingress; the inference front is the extension on Envoy.) Mirror of ADR-0042
A5.

### A5 — Build a new AWS WAF module to mirror `gcp-cloud-armor`
Create a fresh WAF module to mirror the GCP Cloud Armor module one-to-one.
*Rejected because:* the **`waf`** module already exists (`aws_wafv2_web_acl` +
rate-limit + logging) — reuse it (D4), exactly as ADR-0044 D4 reuses `budgets`
instead of cloning `gcp-billing-budget`. The correct mirror of Cloud Armor is the
**native AWS WAF primitive**, not a clone of the GCP module's name.

## Consequences

### Positive
- **Model-/cache-aware serving:** the EPP routes on KV-cache + queue depth, not
  round-robin — improved TTFT/throughput and clean multi-model (multi-LoRA →
  multi-`InferenceObjective`) routing, the same win ADR-0042 documents for GKE.
- **Reuses the in-repo L7 + WAF:** Envoy Gateway (ADR-0025) hosts the extension and
  `waf` (existing module) guards the edge — minimal net-new adoption.
- **Perimeter for inference:** AWS WAF brings WAF/DDoS/rate-limiting to an endpoint
  that has none today (the Cloud Armor mirror).
- **Vendor-neutral + portable:** the inference extension is the same standard GKE
  uses, so serving runbooks/dashboards stay diff-able across clouds.
- **Clean three-way decision closure:** Envoy default / ALB fallback / Lattice out —
  resolves the plan §7 OPEN DECISION with explicit rationale.

### Negative
- **Inference extension maturity:** the Gateway API inference extension is young
  (v1 GA but evolving — note the `InferenceModel`→`InferenceObjective` rename at GA);
  EPP behaviour must be validated under load before cutting prod traffic off
  `ClusterIP`, and the CRD version must be pinned (same caveat as ADR-0042).
- **Two-data-plane story:** Envoy (default) + ALB (fallback) means two serving
  paths to document/operate — mitigated by making Envoy the clear default and ALB
  the narrow fallback.
- **EPP is a separate moving part:** the endpoint-picker ext-proc must be deployed,
  wired to Envoy Gateway, and kept version-aligned with the CRDs/vLLM — an extra
  component to operate (named in D2 / the module contract so it is not missed).
- **WAF-on-Envoy indirection:** AWS WAF binds to the upstream LB in front of Envoy
  (not Envoy directly), so the edge guard and the in-cluster router are two hops —
  acceptable, but a topology to document.

### Risks
- **Endpoint-picker correctness under load.** A mis-tuned EPP routes poorly and
  hurts latency. *Mitigation:* stage behind a canary `InferencePool`; keep
  `ClusterIP` revertible until proven (D5; mirror of ADR-0042).
- **WAF false positives on inference payloads.** Aggressive WAF rules can block
  legitimate long prompts. *Mitigation:* start with rate-limit + managed rules in
  count mode, tune before block mode; the `waf` module's `rate_limit` is the first
  guard.
- **R1 cost (inherited).** The serving front itself is cheap; the GPU pods behind it
  dominate (ADR-0044/0046 guards apply). *Mitigation:* EPP improves GPU utilisation
  (better packing of cache-warm replicas), which *helps* R1.
- **Extension ↔ vLLM ↔ CRD version skew.** EPP/llm-d ↔ vLLM ↔ Gateway API inference
  CRD version (incl. the v1 GA rename) must be co-validated. *Mitigation:* pin
  versions; follow the GA migration guide; validate in CI plan (same discipline as
  ADR-0044/0045).

## Implementation notes

This ADR is **planning-only**: the PR that introduces it creates **no** Gateway, WAF
WebACL, or inference object, and changes **no** Service. Implementation is
**apply-gated** and lands as separate, plan/validate-only PRs.

**Conventions to match (verified against the repo):** `aws ~> 6.0`, Terraform
`~> 1.11`; reuse the `waf` module (`name`, `rate_limit`, `log_retention_days`,
`tags`) and the Envoy Gateway from ADR-0025; ADR-0009 (Cilium Gateway API) stays the
general ingress; every resource takes `tags`/labels with the five ADR-0028 keys. Use
the **v1 GA** inference CRDs (`InferencePool` + `InferenceObjective`, `HTTPRoute`
attach); pin the CRD/extension version (no `main`).

### Module / object contracts (for the parallel build)

**`aws-eks-inference-gateway` (new)** — the model-/cache-aware serving front (D1/D2).
- Inputs: `gateway_class` (Envoy Gateway class by default; ALB LBC class for the D3
  fallback), `inference_pool_selector` (vLLM replica selector / serving port),
  `inference_objectives` (list: `{ name, criticality, target_model }` →
  `InferenceObjective`s *(v1 GA; was `InferenceModel`)*, incl. LoRA adapters),
  `epp_image` + `epp_replicas` + `epp_config` (KV-cache/queue weights — the
  **Endpoint Picker is deployed by this module**, see below), `inference_crd_version`
  (pin), `waf_web_acl_arn` (from the `waf` module, D4), `data_plane`
  (`"envoy"` | `"alb"`), `labels`/`tags`.
- Outputs: `gateway_name`, `inference_pool_name`, `epp_service_name`,
  `gateway_address`.
- **EPP component (D2) — explicit, not automatic:** the module ships the
  **Endpoint-Picker (EPP) ext-proc Deployment + Service** and the Envoy-Gateway
  extension wiring that points the `InferencePool` at it. Installing Envoy Gateway +
  the CRDs alone does **not** stand up routing — the EPP is a named deliverable here.
- **vLLM coupling (D1):** the greenfield serving module exposes vLLM as an
  `InferencePool` member, not `ClusterIP`; metrics scrape + DRA GPU claim
  (ADR-0044) unchanged. Keep a `ClusterIP` path behind a feature flag until the
  gateway is canary-proven (revertible).

**`waf` (reuse, do not rebuild)** — AWS WAF WebACL on the inference LB (D4).
- Wire: `name`, `rate_limit` (per-IP/5-min), `log_retention_days`, `tags`; associate
  the WebACL with the serving ALB (D3) or the upstream LB fronting Envoy (D2).

**Multi-region wiring (ADR-0044 D5):** the inference gateway + EPP + WAF unit are
added to the **per-region `aws-gpu-analysis` Terragrunt stack**; the
`failover-controller` (ADR-0044 D5) fails serving over between regional gateways via
Route 53. Pin every chart/extension/CRD ref (`?ref=vX.Y.Z`, no `main`).

- Effort: **L** (an inference-gateway module on Envoy + the EPP component + ALB-fallback
  support + WAF reuse + the vLLM `ClusterIP`→`InferencePool` cutover + per-region
  wiring).
- Rollback: the serving cutover keeps `ClusterIP` until proven; WAF, the EPP, and the
  gateway are independently revertible; the GPU plane (ADR-0044) and existing estates
  remain authoritative.

## Revisit trigger

Re-open this decision if any of the following hold:
- **The inference extension proves insufficient under load** — revisit D2/A4
  (mesh-based routing) before widening prod traffic. (Mirror of ADR-0042's trigger.)
- **ALB's Gateway API gains first-class EPP integration** — promote ALB from
  fallback (D3) toward default for managed/WAF-native cases.
- **VPC Lattice adds inference-aware (KV-cache) routing** — re-evaluate D5/A3.
- **A confirmed safety / monetisation requirement appears** — promote model-safety
  screening (Bedrock Guardrails / safety ext-proc) to mandatory and/or add API
  management (mirror of ADR-0042 A6 trigger).
- **Disaggregated prefill/decode is prioritised** — open a follow-up ADR building on
  this serving front + the EFA fabric (ADR-0045).

## References

- Introducing Gateway API Inference Extension (Kubernetes blog):
  <https://kubernetes.io/blog/2025/06/05/introducing-gateway-api-inference-extension/>
- Gateway API Inference Extension v1 API reference + **v1alpha2→v1 GA migration guide**
  (`InferenceModel`→`InferenceObjective`; `InferencePool` graduated to v1):
  <https://gateway-api-inference-extension.sigs.k8s.io/reference/spec/>,
  <https://gateway-api-inference-extension.sigs.k8s.io/guides/ga-migration/>
- Gateway API Inference Extension (InferencePool/InferenceObjective/EPP; GA;
  implementation-agnostic): <https://github.com/kubernetes-sigs/gateway-api-inference-extension>,
  <https://gateway-api-inference-extension.sigs.k8s.io/api-types/inferencepool/>
- vLLM + Inference Gateway (llm-d, production-stack):
  <https://docs.vllm.ai/projects/production-stack/en/latest/deployment/gateway-inference-extension.html>
- AWS Load Balancer Controller — Gateway API:
  <https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/>
- AWS WAFv2 (`aws_wafv2_web_acl`, rate-based rules):
  <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl>
- In-repo: `terraform/modules/waf`, `terraform/modules/gpu-inference-vllm`
  (reference only).
- Related ADRs: [ADR-0042](0042-gpu-inference-networking-serving-uplift.md) (the GKE
  serving/fabric etalon — this mirrors its **serving half**);
  [ADR-0044](0044-aws-eks-gpu-ml-foundation-multiregion.md) (foundation);
  [ADR-0045](0045-aws-efa-gpu-fabric-placement-groups.md) (fabric — the other half);
  [ADR-0025](0025-envoy-gateway-secondary-l7.md) (Envoy Gateway — reused as the
  default data plane); [ADR-0009](0009-cilium-gateway-api-ingress.md) (Cilium Gateway
  API — general ingress); [ADR-0023](0023-vpc-lattice-resource-connectivity.md) (VPC
  Lattice — east-west, explicitly NOT the inference front);
  [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (taxonomy —
  mandatory).

---
*Doc-verified 2026-06-15 against the Gateway API Inference Extension (v1 GA — incl.
the `InferenceModel`→`InferenceObjective` rename + the GA migration guide), vLLM/llm-d
serving, AWS Load Balancer Controller Gateway API, and AWS WAFv2 documentation.
Greenfield AWS mirror of the serving half of the GKE etalon ADR-0042. Planning-only
ADR — proposed, not yet implemented in platform-design. Extends WS-A on the serving
axis; implementation apply-gated.*
