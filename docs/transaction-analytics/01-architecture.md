# Three-tier architecture

The platform runs in three deployment tiers with different failure modes, security postures, and update velocities. This doc covers what each tier owns, what crosses each boundary, and why.

---

## Tiers at a glance

| Tier | Where it runs | What it owns | Update cadence | Owner |
|------|---------------|--------------|----------------|-------|
| **Edge** | Client co-location hardware, near trading venues / ad exchanges / insurance marketplaces | Real-time transaction scoring | Model+templates: daily to weekly per domain; agent binary: monthly; canary-driven via Kargo | Client operates hardware, we operate the agent via signed artefacts |
| **UK bare-metal** | Two owned data centres in England (primary + standby) | Post-analysis, template mining, model training, LLM-as-judge eval, label storage, long-term data archive | Continuous on platform components; training runs on cron + event triggers | Us |
| **AWS control plane** | AWS multi-account across 4 EU regions (eu-central-1, eu-west-1, eu-west-2, eu-west-3) | GitOps orchestration, observability, CI/CD, model registry front-end, LiteLLM gateway, DNS, public-facing APIs | Continuous via ArgoCD + Kargo | Us |

---

## Diagram

```
                      Client co-location sites (LHR, FR2, NY4, ...)
                      ┌──────────────────────────────────────────────────────────┐
                      │                                                          │
                      │   ┌─────────────────────────────────────────────┐        │
                      │   │ Edge agent (per venue, per tenant)          │        │
                      │   │  ├─ TRT-LLM engine (Qwen 2.5 3B + LoRA,fp8) │        │
                      │   │  ├─ Triton FIL runtime (XGBoost/LightGBM)   │        │
                      │   │  ├─ Templates bundle (JSON + vectors + NL)  │        │
                      │   │  ├─ Redis hot feature cache                 │        │
                      │   │  └─ OTel + Kafka producer (telemetry out)   │        │
                      │   └────────────┬─────────────────┬──────────────┘        │
                      │                │                 │                       │
                      │  ingest in ────┘                 └─── telemetry/feedback │
                      │  (transactions)                        out (reverse)     │
                      └──────┬────────────────────────────────────────┬──────────┘
                             │ Kafka over mTLS                        │
                             ▼                                        │
    ┌────────────────────── UK bare-metal DC (primary) ───────────────┼──────────┐
    │                                                                 │          │
    │   Kafka (KRaft, 3 brokers) ◄──────── telemetry / feedback ──────┘          │
    │   │                                                                        │
    │   ├─→ QuestDB  (30-day hot, nanosecond timestamps)                         │
    │   └─→ Iceberg on MinIO (cold archive, template warehouse, training sets)   │
    │                                                                            │
    │   Talos Linux k8s cluster                                                  │
    │     ├─ H100 pool  → training (DeepSpeed ZeRO-3, Volcano gang scheduling)   │
    │     ├─ H200 pool  → batch inference (vLLM multi-LoRA), LLM-as-judge,       │
    │     │                TRT-LLM engine build farm                             │
    │     └─ CPU pool   → Airflow, DuckDB, Trino, Argilla, Qdrant, Postgres,     │
    │                      Kafka, MinIO, QuestDB, OTel collectors                │
    │                                                                            │
    │   Per-tenant namespaces + NetworkPolicy + tenant-scoped KMS keys           │
    │                                                                            │
    └──────────────┬────────────────────────────────────────┬────────────────────┘
                   │ Iceberg site replication               │ ArgoCD pull
                   │ Kafka MirrorMaker 2                    │ telemetry fanout
                   │ Postgres streaming replication         │ (Loki, Tempo, Prom)
                   ▼                                        │
    ┌────── UK bare-metal DC (standby) ──────┐              │
    │   Hot-standby: same shape, replicated  │              │
    │   data, read-only during normal ops,   │              │
    │   promoted on failover                 │              │
    └────────────────────────────────────────┘              │
                                                            │
    ┌──────────────── AWS control plane (existing) ─────────┼────────────────────┐
    │                                                       ▼                    │
    │   EKS + Karpenter — eu-central-1, eu-west-1, eu-west-2, eu-west-3          │
    │   ArgoCD (ApplicationSets) + Kargo (progressive delivery + edge rollouts)  │
    │   LiteLLM gateway → internal teams → vLLM in UK (with AWS-hosted fallback) │
    │   Observability: Prometheus, Grafana, Loki, Tempo, OTel, Pyroscope, DCGM   │
    │   Model registry UI, CI (GitHub Actions), OCI registry (ECR), Cosign       │
    │   DNS failover controllers, external-secrets, cert-manager                 │
    │                                                                            │
    └────────────────────────────────────────────────────────────────────────────┘
```

---

## What crosses each boundary

### Edge ↔ UK

**Inbound to UK** (from edge)
- Transaction ingest: `{tenant}.{domain}.ingest` over mTLS Kafka. Format per domain (see [00-domains.md](00-domains.md))
- Telemetry: `{tenant}.{domain}.telemetry` — OTel metrics, traces, logs, model/template version heartbeat, scoring latency distribution
- Feedback: `{tenant}.{domain}.feedback` — downstream labels when the client system has outcome data (trade P&L, bid conversion, policy binding result)

**Outbound from UK** (to edge)
- Signed OCI images + raw binaries, published to OCI registry (pulled by edge, not pushed to edge)
- Templates bundles, versioned alongside the engine
- Configuration: feature flags per tenant, routing weights, canary cohort membership

All edge ↔ UK traffic is mTLS Kafka or HTTPS with Cosign-verified artefacts. No persistent shell or SSH access from UK into client co-lo.

### UK ↔ AWS

**UK-to-AWS**
- Observability push: OTel collectors in UK forward aggregates to AWS Prometheus / Loki / Tempo for the unified SRE view
- Model registry metadata: new adapter releases registered in the AWS-hosted registry front-end
- LLM gateway fallback: LiteLLM in AWS holds an emergency-only AWS-hosted Qwen instance that internal teams can fall back on when UK is unreachable (not for production scoring — used for platform-engineering workflows)

**AWS-to-UK**
- ArgoCD syncs (pull-based from UK clusters against AWS-hosted Git and config repos)
- Kargo promotion events (new stage, new cohort, rollback signals)

Connectivity is site-to-site IPsec or Cloudflare Tunnel (decision pending in Phase 1). Target latency UK DC ↔ `eu-west-2` (London): <5 ms.

### Edge ↔ AWS (direct)

Deliberately minimal. The only direct edge ↔ AWS path is the OCI image pull, which goes through a public registry (ECR or client-chosen mirror). Everything else routes through UK.

Rationale: fewer exposed surfaces on client hardware, and UK is the canonical source of truth for everything model- and data-related.

---

## Why this shape

### Why a separate UK bare-metal tier at all?

- GPU economics: running continuous training + batch inference on cloud H100/H200 instances is 4-6× the TCO of owned hardware at our utilisation pattern (24/7, high-duty-cycle).
- Data residency: clients prefer their tape to live on our own hardware in a jurisdiction they approve, not in a public cloud.
- Latency to clients: most of our target clients co-locate at UK venues; a UK DC gives us sub-10 ms round-trip for synchronous operations we do want (e.g. admin-plane), while keeping the edge tier free of cross-ocean dependencies.
- NIC / kernel tuning that matters for Kafka and QuestDB throughput is hard to express on cloud instance types.

### Why keep the AWS control plane?

- ArgoCD / Kargo / observability stack already works there, adds no operational risk.
- Public-facing DNS, TLS, SSO, and vendor integrations (Datadog equivalents for internal tooling, GitHub, Cloudflare) live in AWS naturally.
- CI build minutes, container registry, and artefact storage are cheap on AWS; no reason to replicate on bare metal.
- Failover of control plane itself: if one UK DC is down and the other is being promoted, we still want ArgoCD / observability to see the transition from outside both DCs.

### Why not put the ML serving in AWS?

- We tried the napkin math: vLLM multi-LoRA on 8× H200 instances in AWS at continuous utilisation is roughly 2× the annual cost of owning + racking equivalent H200 nodes in a UK DC. Over a 3-year horizon, bare metal wins on both cost and per-query latency to UK clients.
- Also: TRT-LLM engine builds run on H100/H200 and produce per-tenant-per-domain-per-target-hardware engines. That is a continuous batch workload — bare metal's best case.

### Why is primary+standby sufficient? Why not active-active?

- RPO < 60 s, RTO < 15 min are acceptable to clients given the nature of the workload (post-analysis is not latency-critical in the same way as scoring; scoring happens at edge and degrades gracefully when UK is unreachable — last-known-good templates continue to run).
- Active-active adds operational complexity (bidirectional consistency, split-brain risk) that we do not need for this failure budget.
- Cost savings: standby can run on reduced power when healthy, ~40% of primary's steady-state cost.

See [06-uk-datacenters.md](06-uk-datacenters.md) for the DR mechanics.

---

## Failure modes and blast radius

| Failure | Blast radius | Observable effect |
|---------|--------------|-------------------|
| Single edge agent dies | One venue for one tenant | Client sees no scoring for that venue; their system falls back to its own defaults; our Kargo auto-rollback disables the bad cohort within minutes |
| UK primary DC loses connectivity | Template updates and telemetry visibility | Edge continues running with last-known-good model+templates; training pauses; standby promotes within RTO |
| UK primary DC loses a rack | Training slows, batch inference slows | Automatic reschedule across remaining nodes; no client-visible impact unless sustained |
| AWS control-plane region down | GitOps and observability degraded | Other AWS regions take over for ArgoCD / Kargo via existing multi-region failover; edge and UK continue operating against last-synced state |
| Full UK outage (both DCs) | No new models, no training, no LLM-as-judge eval | Edge continues on last-known-good; we have hours to restore before client-side drift becomes material |
| Cosign key compromise | New adapter rollouts blocked | Kargo rollback to last-known-good, re-issue keys, re-sign current production artefacts |

The key architectural property: **edge does not require UK to be up.** UK failing degrades the platform to "static scoring against last-known-good" — not to outage.
