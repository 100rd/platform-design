# ML inference

Model selection, serving stack, and the two inference paths (edge real-time and UK batch). See [04-training-pipeline.md](04-training-pipeline.md) for how models get produced.

---

## Model choices

### Base model: Qwen 2.5 3B

Picked for:

- Size sweet spot: 3B parameters fits in a single H200 (141 GB HBM) with room for tens of concurrent LoRA adapters in vLLM multi-LoRA, and fits in the 80 GB of an H100 at fp16 for training. Fp8 quantized it fits in modest GPUs at the edge (16-24 GB HBM suffices).
- Instruction-following quality at 3B is strong enough that SFT on domain-specific labels produces usable scoring models without needing to go to 7B.
- Permissive license (Apache 2.0), base weights open-weight with no per-request upstream dependency.

We do not use distillation from a larger teacher as a separate pipeline step. The reasoning from the design discussion: we have **labels** — outcomes of historical strategies (P&L, hit-ratio), expert annotations from traders and scoring engineers — and a base model of reasonable size. Direct SFT + LoRA on this label stream hits the target accuracy more cheaply than a teacher-student distillation, and gives us more direct control over what the small model learns.

If we ever encounter a domain where labels are sparse or noisy, distillation from Qwen 2.5 72B or similar becomes a reasonable path. The architecture does not preclude it; the training DAGs would add a "synthetic label generation" step upstream of `train_domain_adapter`.

### Per-domain adapters: LoRA

One LoRA adapter per (tenant, domain) pair. Rank 16 default, tuned per domain during initial onboarding.

- Small enough (tens of MB) that every adapter can be versioned and shipped independently of the base weights.
- vLLM supports hot-swapping adapters at inference time, which means one vLLM deployment serves every tenant at batch time without reloading weights.
- At edge, the adapter is merged into the base weights before TRT-LLM compilation (simpler runtime, slightly better latency, fewer moving parts than multi-LoRA on edge).

### Tabular fallback: XGBoost / LightGBM via Triton FIL

For domains where the scoring problem is fundamentally tabular (HFT numeric signals, RTB bid valuation, insurance structured fields after extraction), an LLM is the wrong tool. Trained XGBoost models:

- <2 ms p99 inference via Triton FIL backend
- Often higher accuracy than an LLM on the tabular portion of the problem
- Interpretable (feature importance, SHAP on-request) which matters for regulated clients

The edge agent routes transactions through either or both paths depending on the domain and the transaction content. HFT fast-filter is XGBoost-only; HFT deep-analysis is LLM. RTB is XGBoost-first, LLM only for novel creatives. Insurance is LLM-first (document understanding), with XGBoost on extracted structured features for the final numerical scores.

---

## The two inference paths

### Path 1: Edge real-time (TRT-LLM + Triton)

Everything client-facing, SLA <20-30 ms depending on domain.

**Stack**
- NVIDIA TensorRT-LLM compiled engine per (tenant, domain, target_hardware)
- Fp8 quantization (weight + activation), speculative decoding with a draft model for short outputs
- Triton Inference Server (FIL backend) for XGBoost/LightGBM models
- Redis for feature cache
- All colocated in one process on client hardware (or one container + sidecar in the OCI-deployed case)

**Why TRT-LLM over vLLM at edge**
- vLLM is throughput-optimised (multi-LoRA, continuous batching, PagedAttention). At the edge we have one small model, one request at a time, and we want the lowest possible latency. TRT-LLM compiled as a standalone engine has a shorter critical path and smaller memory footprint.
- Multi-LoRA value proposition is moot — each edge instance only serves one tenant (its own co-lo's transactions).
- TRT-LLM also better supports fp8 with speculative decoding out of the box.

**Why not ONNX runtime**
- ONNX runtime is fine for the XGBoost path (we use Triton FIL which wraps it), but for LLMs at low latency, TRT-LLM beats it on H100/H200/L40S class hardware by 2-3×.

**Target hardware**
- Default: NVIDIA L40S (48 GB HBM, lower power, cheaper — fits in client 1U rack space; runs fp8 3B comfortably). This is what most clients deploy.
- High-throughput tenants: H100/H200 per venue (client-funded, when throughput demands it).
- CPU-only fallback: if a client refuses GPU deployment, we ship an XGBoost-only agent. They accept degraded capabilities for HFT deep-analysis and insurance document LLM path; RTB and Solana can largely work without the LLM path.

### Path 2: UK batch and eval (vLLM multi-LoRA)

**Stack**
- vLLM with multi-LoRA serving, 4-16 adapters loaded concurrently per replica
- Served on H200 pool in UK DC (primary + standby)
- Consumed by:
  - Airflow DAGs for batch scoring (e.g., re-scoring a historical window after adapter update, for evaluation)
  - LLM-as-judge debate eval (see [04-training-pipeline.md](04-training-pipeline.md))
  - Internal engineer workflows via LiteLLM gateway

**Why vLLM here**
- Multi-LoRA: we have dozens of adapters (multiple tenants × multiple domains × multiple versions for eval comparison). Loading them into a single vLLM process and swapping by request header is far more efficient than spinning up a separate engine per adapter.
- PagedAttention + continuous batching: batch and internal workloads are throughput-sensitive, not latency-critical.
- Mature in the Kubernetes deployment story (there is an official Helm chart; we package it under `apps/infra/vllm-multilora/`).

**SLA**
- Batch scoring: >1000 tokens/sec/GPU sustained, no hard latency SLA per request
- LLM-as-judge eval: each debate round <5 s (we want eval runs to finish within hours, not days)
- Internal queries via LiteLLM: best-effort, advertised <2 s p95 TTFT but not guaranteed

---

## LiteLLM gateway

Deployed in AWS control plane as the single entry point for internal engineers and internal tools that want to use our models (code review bots, SRE tooling, documentation Q&A). **Not in the client-facing scoring path** — clients talk to their edge agent, not to LiteLLM.

### Responsibilities

- Per-team API key issuance and quota enforcement
- Routing: primary route to vLLM in UK; emergency fallback to AWS-hosted Qwen 2.5 7B instance (small deployment, always-on, for when UK is unreachable)
- Request logging to Loki for audit
- Cost attribution per team / per project
- Model aliasing: teams reference `scoring-hft-default` or `omniscience-rag-primary` as logical names; LiteLLM resolves to the concrete deployed version, decoupling teams from our internal versioning

### Why LiteLLM over raw vLLM endpoints

- Multi-tenant auth and quota are non-trivial to add to vLLM directly.
- We need request-level fallback logic (primary UK → fallback AWS) that lives naturally at the gateway.
- Log-and-observe at the gateway means we have one place to audit "who asked which model what" instead of instrumenting every service.

### Integration with Omniscience (related product)

Omniscience — the internal-engineer RAG / platform intelligence product — will reuse the same LiteLLM gateway rather than standing up its own. It talks to the same vLLM deployments in UK for its RAG pipeline. This is the main reason LiteLLM is in scope at all: it is the shared front door across both product lines.

---

## Inference SLAs (summary)

| Path | Component | p50 | p95 | p99 |
|------|-----------|-----|-----|-----|
| Edge LLM (Qwen 2.5 3B fp8 + LoRA, TRT-LLM, L40S) | TTFT | 5 ms | 10 ms | 15 ms |
| Edge LLM (end-to-end 64-token output) | Total latency | 12 ms | 18 ms | 25 ms |
| Edge XGBoost (Triton FIL) | Total latency | 0.5 ms | 1 ms | 2 ms |
| UK vLLM multi-LoRA batch | Throughput | — | — | >1000 tok/s/GPU |
| UK LLM-as-judge debate round | Per-round latency | 2 s | 4 s | 6 s |

These are design targets, validated in Phase 3 against synthetic benchmarks before going to production. See `tests/gpu-inference/` for how we will extend the existing validation suite.

---

## What is not here (deliberate exclusions)

- **Streaming inference** (token-by-token to client). Scoring outputs are small (a score + short rationale); there is no user waiting for a streamed response. Batched decode is simpler and faster.
- **Multi-model ensembles at edge.** We ran the numbers; two models in series at 20 ms each breaks the SLA. Ensembling happens in the UK eval pipeline, which produces a single distilled adapter to ship.
- **Online fine-tuning / federated learning at edge.** Training happens exclusively in UK. Edge agents are stateless with respect to model weights — they run what was shipped to them and nothing more.
- **Distillation as a mandatory step.** As discussed above: we have labels. SFT + LoRA on domain data is the default path; distillation is an optional branch for label-sparse domains.
