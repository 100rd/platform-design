# Transaction Analytics — Architecture Documentation

Deep-dive documentation for the transaction analytics layer of the platform. Read top-down: domains → architecture → data plane → ML → training → edge → UK DCs → compliance.

For the phased build plan, see [`PLAN.md`](../../PLAN.md) at the repo root.
For the high-level framing, see [`README.md`](../../README.md).

---

## Reading order

| # | Document | Audience |
|---|----------|----------|
| 00 | [Domains](00-domains.md) | Product, engineering — what each of HFT / Solana / insurance / RTB actually looks like as a data contract and SLA |
| 01 | [Three-tier architecture](01-architecture.md) | All engineering — how edge / UK / AWS fit together, what crosses each boundary |
| 02 | [Data plane](02-data-plane.md) | Data / platform engineering — Kafka, QuestDB, Iceberg, Redis, Postgres, Qdrant choices and why ClickHouse was not used |
| 03 | [ML inference](03-ml-inference.md) | ML engineering — Qwen 2.5 3B + LoRA, TRT-LLM on edge, vLLM multi-LoRA in UK, Triton FIL for XGBoost |
| 04 | [Training pipeline](04-training-pipeline.md) | ML engineering — labels, retraining triggers (100k sample threshold), LLM-as-judge debate evaluation, Airflow DAGs |
| 05 | [Edge deployment](05-edge-deployment.md) | Platform + ML engineering — signed OCI and raw-binary agent, Kafka reverse topic for telemetry, Kargo-driven rollouts |
| 06 | [UK data centres](06-uk-datacenters.md) | Platform engineering — Talos + Cluster API + Ansible, namespace-per-tenant isolation, primary + standby DR |
| 07 | [Compliance & security](07-compliance-security.md) | Security, legal — SOC2 control mapping, why PCI-DSS is out of scope, tenant isolation model |

---

## Quick reference

**What the platform does**: analyses transactions from four domains, mines algorithmic templates and trains small domain-specific models on historical sessions in UK bare-metal data centres, ships signed scoring artefacts to client co-located hardware for real-time inference.

**What the platform does not do**: execute transactions (no trading, no bidding, no policy issuance), process cardholder data (no PCI-DSS), replace the client's own risk systems (we augment, we do not replace).

**Core model**: Qwen 2.5 3B base + per-domain LoRA adapter, served as fp8 TRT-LLM engine on edge for low-latency inference, served as vLLM multi-LoRA in UK for batch and LLM-as-judge eval.

**Fallback path**: XGBoost/LightGBM via Triton FIL for pure-numeric scoring problems (HFT features, RTB bid valuations) — <2 ms p99, often higher accuracy than an LLM on tabular data.

**Data path**: edge → Kafka → QuestDB hot (30-day) + Iceberg on MinIO cold (long-term) → Airflow trains on Iceberg → new LoRA adapter → LLM-as-judge eval → TRT-LLM engine build → signed OCI published → Kargo rollout to edge fleet.

---

## Conventions used in this doc set

- **Tenant** — one client organisation. Each tenant gets its own namespace, Kafka topic family, QuestDB database, Iceberg namespace, Qdrant collection, Postgres schema, KMS key.
- **Domain** — one of HFT / Solana / insurance / RTB. A tenant may be active in multiple domains.
- **Venue** — one physical deployment location of an edge agent. For an HFT tenant, typical venues are LHR (LSE), FR2 (Frankfurt, Eurex), NY4 (NYSE/NASDAQ). For RTB, one venue per ad exchange region.
- **Template** — the output of batch template mining. Format varies by domain: JSON rule set, numeric feature vector(s), short natural-language pattern description, or a combination. Consumed by the edge agent at scoring time.
- **Adapter** — a LoRA adapter trained for a specific tenant × domain combination. Multiple adapters share the same Qwen 2.5 3B base weights via vLLM multi-LoRA in UK and are merged into the base for per-edge TRT-LLM builds.
