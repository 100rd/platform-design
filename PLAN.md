# Platform Roadmap

Phased build plan for the transaction analytics layer on top of the existing AWS EKS + GPU inference foundation.

**Scope**: Four transaction domains (HFT, Solana, insurance exchange, RTB), three deployment tiers (edge co-lo, UK bare-metal, AWS control plane), Qwen 2.5 3B + LoRA scoring with XGBoost fallback, event-triggered template mining, signed artefact rollout.

**Out of scope**: HFT transaction execution (we analyse, we do not trade). PCI-DSS (no cardholder data). Omniscience (separate product, same infrastructure).

---

## Phase status legend

- ✅ Done — landed on `main`, has tests and runbook
- 🚧 In progress — branch exists, CI green on at least one slice
- 📋 Planned — scoped but not started
- ❓ Open question — blocker before scoping

---

## Phase 0 — Foundation (✅ done, recap only)

Already in the repo, feeds into everything below.

| Item | Location |
|------|----------|
| AWS multi-account, SCPs, SSO | `terragrunt/_org/`, `terraform/modules/{organization,scps,sso}/` |
| EKS 1.34 + Karpenter across 4 EU regions | `terraform/modules/{eks,karpenter,karpenter-nodepools}/` |
| GPU inference cluster (H100, NVSwitch, NCCL, WireGuard, Volcano, DRA) | `docs/gpu-inference-dod.md`, `terraform/modules/gpu-inference-validation/` |
| ArgoCD ApplicationSets + Kargo | `argocd/`, `kargo/` |
| Observability (Prom, Grafana, Loki, Tempo, OTel, Pyroscope, DCGM) | `apps/infra/observability/` |
| DNS failover controllers (Go) | `dns-monitor/`, `failover-controller/` |

---

## Phase 1 — UK bare-metal data centres (📋 planned)

Two Talos-managed clusters in the UK (primary + standby). All post-analysis, template mining, training, and LLM-as-judge run here. Primary takes live load; standby is hot-standby with async Iceberg/Postgres replication.

**Deliverables**

- `terraform/modules/talos-cluster/` — Cluster API bootstrap, `ClusterClass` with H100 training pool and H200 inference pool as separate machine deployments
- `ansible/roles/{bare-metal-firmware,nic-tuning,kernel-rt,numa-pinning}/` — low-level host config Talos can't express declaratively (BIOS settings, MTU 9000 on 100G NICs, CPU pinning for Kafka brokers, HugePages, IRQ affinity)
- `terragrunt/uk/{primary,standby}/platform/` — live config, mirroring the AWS `terragrunt/{dev,prod}/` layout
- `docs/transaction-analytics/06-uk-datacenters.md` — detailed build doc
- Runbook: `docs/runbooks/uk-dc-bootstrap.md`

**Acceptance**
- Both clusters reachable via ArgoCD from AWS control plane via Cloudflare Tunnel or site-to-site IPsec
- `kubectl get nodes` shows H100 pool (training) and H200 pool (inference) with correct taints/labels
- Cilium WireGuard enabled on all nodes (same bar as `gpu-inference-dod.md` §6)
- Standby replicates Iceberg warehouse + Postgres WAL within 60 s RPO

**Open questions**
- ❓ IPsec vs Cloudflare Tunnel vs DirectConnect equivalent for AWS ↔ UK connectivity. Latency from UK DC → `eu-west-2` (London) should be <5 ms — pick cheapest that hits that.

---

## Phase 2 — Data plane (📋 planned)

Storage, ingestion, streaming. Replaces the vacancy's ClickHouse shape with a stack tuned for tick-heavy writes + batch template mining.

**Deliverables**

- Kafka cluster on UK primary (`apps/infra/kafka/`) — KRaft mode, 3 brokers per DC, cross-DC MirrorMaker 2 to standby; dedicated topic families: `{tenant}.{domain}.ingest`, `{tenant}.{domain}.telemetry`, `{tenant}.{domain}.feedback`
- QuestDB cluster (`apps/infra/questdb/`) — tick hot store, nanosecond-precision timestamps, ILP ingress from Kafka Connect, 30-day retention then tiered to Iceberg
- MinIO + Apache Iceberg (`apps/infra/minio/`, `apps/infra/iceberg-rest/`) — cold archive, template warehouse, training snapshots; REST catalog for DuckDB/Trino
- DuckDB jobs (embedded in Airflow) + Trino cluster (`apps/infra/trino/`) for larger batch passes
- Redis Cluster (`apps/infra/redis/`) deployed at edge (Phase 4) for hot feature cache; plus a small central Redis in UK for control-plane state
- Qdrant (`apps/infra/qdrant/`) — vector store for similarity search over historical transaction embeddings (also used by Omniscience later)
- Postgres (`terraform/modules/rds/` extended to on-prem via CloudNativePG on UK clusters) — template registry, model registry, label store, tenant metadata

**Acceptance**
- End-to-end: a synthetic tick published to `tenant-a.hft.ingest` lands in QuestDB within 2 s p99, is archived to Iceberg at end-of-day, is queryable via DuckDB and Trino
- Tenant isolation verified: tenant A cannot read tenant B's Kafka topics, QuestDB tables, Iceberg namespaces, or Qdrant collections
- MirrorMaker 2 lag from primary to standby < 10 s under 500k msg/s load

**Open questions**
- ❓ Retention on `telemetry` and `feedback` topics — compliance may require 7 years for feedback (training labels); confirm with legal.

---

## Phase 3 — ML training & inference core (📋 planned)

Model selection, serving, evaluation. See [docs/transaction-analytics/03-ml-inference.md](docs/transaction-analytics/03-ml-inference.md) and [docs/transaction-analytics/04-training-pipeline.md](docs/transaction-analytics/04-training-pipeline.md).

**Deliverables**

- Base model: Qwen 2.5 3B pinned in model registry (Postgres + MinIO artefact store)
- `training/` repo module: SFT + LoRA training scripts (peft + trl), DeepSpeed ZeRO-3 config for H100 training pool
- `serving/vllm-multilora/` — Helm chart for vLLM with multi-LoRA hot-swap; deployed on H200 pool in UK (used for batch + eval, not edge)
- `serving/triton-fil/` — Helm chart for Triton Inference Server with FIL backend for XGBoost/LightGBM
- `serving/trt-llm-engine/` — build pipeline that takes a LoRA adapter + base weights, merges, quantizes to fp8, compiles to TRT-LLM engine, ships as OCI artefact (edge uses these)
- LiteLLM gateway (`apps/infra/litellm/`) deployed on AWS — single endpoint for internal teams, routes to vLLM in UK, with fallback to AWS-hosted Qwen if UK unreachable
- Airflow DAGs:
  - `train_domain_adapter` — triggered when labels accumulate past threshold (default 100k per domain)
  - `eval_adapter_debate` — LLM-as-judge evaluation (teacher vs student vs independent judge)
  - `promote_to_edge` — on eval pass, build TRT-LLM engine and register as release candidate

**Acceptance**
- `train_domain_adapter` produces a LoRA adapter in <6 h for 100k-sample dataset on 8× H100
- vLLM multi-LoRA serving handles 4 concurrent adapters at >1000 tokens/sec/GPU
- Triton FIL serves XGBoost at <2 ms p99
- LLM-as-judge debate converges (judge agreement >80%) on held-out set

**Open questions**
- ❓ Judge model choice — do we use Qwen 2.5 72B as judge (self-family risk) or swap in Llama 3.3 70B / DeepSeek-V3 for independence?

---

## Phase 4 — Edge agent (📋 planned)

Signed scoring artefact that runs on client co-lo hardware. Both OCI and raw binary supported.

**Deliverables**

- `edge-agent/` (Go + CGo bindings to TRT-LLM runtime) — single-binary scoring service with Redis feature cache, Kafka producer for telemetry, Kafka consumer for incoming transactions
- `edge-agent/Dockerfile` — distroless OCI image, signed with Cosign, published to AWS ECR Public (or client-chosen registry)
- `edge-agent/packaging/` — GoReleaser config producing static-linked Linux amd64 + arm64 binaries, tarball with templates bundle, systemd unit file
- `edge-agent/templates/` — schema for the templates bundle (JSON rules + numeric feature vectors + small natural-language pattern descriptions, depending on domain)
- Kargo stages extended: `edge-canary` (1 client, 1 venue) → `edge-batch-A` (30%) → `edge-all` (100%), each with automated rollback on telemetry-driven SLO breach

**Acceptance**
- Scoring latency <20 ms p99 (measured via reverse-topic telemetry) on Qwen 2.5 3B + LoRA with fp8 TRT-LLM engine
- XGBoost-only scoring path <2 ms p99
- Agent survives 24 h chaos run: Kafka disconnect, disk full on `/var/log`, Redis crash — all with graceful degradation
- Cosign signature verified by client-side admission before first run

**Open questions**
- ❓ How does a client without Docker run the binary as a non-root service? — document systemd hardening template (`NoNewPrivileges`, `ProtectSystem=strict`, dedicated user).

---

## Phase 5 — Back-channel & observability (📋 planned)

Kafka reverse topics carry metrics, logs, heartbeat, template/model version reports from edge to UK, then into the central observability stack.

**Deliverables**

- `apps/infra/otel-collector-edge/` — OTel collector sidecar/embed inside the edge agent (or as a standalone binary for the raw-binary deployment)
- Kafka topics `{tenant}.{domain}.telemetry` consumed by a central OTel collector in UK → Prometheus + Loki + Tempo
- Grafana dashboards: per-tenant, per-domain, per-edge-instance — latency, error rate, model version, template version, GPU util (if edge has GPU), Kafka lag
- VMAlert rules: scoring latency p99 > 20 ms (2 min), XGBoost latency p99 > 2 ms (2 min), model version drift across fleet, telemetry gap > 60 s
- DCGM exporter on UK H100/H200 pools following the `gpu-inference-dod.md` bar

**Acceptance**
- From AWS-side Grafana, operator can see real-time per-client-venue scoring latency distribution
- Alerts fire within 2 min of SLO breach and page the on-call rotation
- No plaintext telemetry — all reverse-topic traffic goes through mTLS Kafka listener

---

## Phase 6 — Expert feedback loop (📋 planned)

Traders and scoring engineers flag suspicious transactions (new types, new countries, new counterparties). Flags become labels, labels drive retraining.

**Deliverables**

- Argilla (`apps/infra/argilla/`) deployed on UK primary, backed by Postgres — dataset-per-tenant-per-domain, role-based access
- Suspicious-transaction picker: a periodic job selects candidates for review (high-score outliers, model-uncertainty peaks, drift-detected segments) and queues them in Argilla
- Export pipeline: Argilla dataset → Iceberg table `labels.{domain}.curated` → consumed by `train_domain_adapter` DAG
- Audit log: every label has user, timestamp, pre-label prediction, expert decision — stored in Postgres with WORM-style immutability

**Acceptance**
- Trader can label 100 suspicious transactions in one Argilla session, results are in the next training run
- Labels traceable end-to-end: given a model version, you can enumerate exactly which labels went into training it

---

## Phase 7 — DR for UK primary (📋 planned)

Primary + hot-standby model. RPO < 60 s, RTO < 15 min on planned failover, < 30 min on unplanned.

**Deliverables**

- Iceberg replication via MinIO site replication (or S3-compatible equivalent)
- Kafka MirrorMaker 2 bidirectional topic mirroring (already in Phase 2, extended here with consumer group offset sync)
- Postgres streaming replication + WAL shipping
- Qdrant cluster replication (native snapshot replication)
- `failover-controller/uk-dc/` — extends the existing failover-controller with UK-DC-specific state machine: detect primary unreachable → freeze writes on standby → promote → update DNS (internal + edge-facing) → unfreeze
- Runbook: `docs/runbooks/uk-dc-failover.md`

**Acceptance**
- Quarterly DR drill: primary is cordoned, standby takes over, all Airflow DAGs resume, all edge agents re-route telemetry, no data loss
- RPO measured < 60 s on drill
- RTO measured < 15 min on drill

---

## Phase 8 — Multi-tenant hardening (📋 planned)

Namespace-per-tenant isolation across all shared components. Parallel track with Phases 2-7 — every component added must be tenant-aware from day one.

**Deliverables**

- `charts/tenant-bootstrap/` — Helm chart that provisions for a new tenant: Kubernetes namespace, NetworkPolicy (deny-all + explicit allow), ResourceQuota, LimitRange, Kafka ACLs, QuestDB database, Iceberg namespace, Qdrant collection, Postgres schema, tenant KMS key (AWS KMS for AWS-resident state, Vault for UK-resident)
- Per-tenant encryption-at-rest keys — each tenant's QuestDB, Iceberg, Postgres data encrypted with a distinct key; key rotation quarterly
- Per-tenant Kafka listener with SASL/SCRAM + mTLS; tenant credentials rotated via External Secrets Operator
- Gatekeeper constraint templates: deny cross-tenant service accounts, enforce tenant label on every namespaced resource, deny pods without a tenant-scoped service account
- Tenant offboarding procedure + automated purge (configurable grace period before Iceberg cold data is actually deleted)

**Acceptance**
- Security review passes: red-team attempt to read tenant B's data from tenant A's pod blocked at every layer (network, storage, IAM)
- Tenant lifecycle runbook tested end-to-end: onboard → use → offboard → data purge verified

---

## Cross-cutting: SOC2 readiness (📋 planned, parallel)

No PCI-DSS scope (no cardholder data in any domain). SOC2 Type 2 is the target.

- Audit logging: all control-plane actions (ArgoCD, Kargo, Airflow, Argilla) → Loki → 400-day retention per SOC2 CC-series
- Access review: IAM / RBAC / Argilla / Kafka ACL quarterly review, automated reporting
- Change management: every prod change via ArgoCD + Kargo (already the case), signed commits enforced via branch protection + Gitleaks
- Vendor management: register for MinIO, Qdrant, Argilla, LiteLLM, Talos — SOC2 attestations collected
- Incident response: extend `docs/sre-runbook.md` with tenant-data-exposure scenario

See [docs/transaction-analytics/07-compliance-security.md](docs/transaction-analytics/07-compliance-security.md).

---

## Dependency graph

```
Phase 0 (done)
    ├─→ Phase 1 (UK DCs) ─→ Phase 2 (data plane) ─→ Phase 3 (ML core) ─→ Phase 4 (edge agent)
    │                                                      ├─→ Phase 5 (back-channel + obs)
    │                                                      └─→ Phase 6 (feedback loop)
    └─→ Phase 8 (multi-tenant) — parallel, gates every other phase
                                                                          Phase 7 (DR) ← after Phase 2-6 stable
```

Phase 8 is not a sequential phase — it is an acceptance criterion applied to every other phase. Nothing ships to production without tenant isolation verified.

---

## Definition of Done (platform-wide)

A release is production-ready when:

1. All critical rows in [`docs/gpu-inference-dod.md`](docs/gpu-inference-dod.md) pass (GPU + network + scheduling bar)
2. Edge scoring SLA met per domain: HFT < 20 ms p99, RTB < 20 ms p99, Solana < 30 ms p99, insurance < 500 ms p99 (document-bound)
3. Multi-tenant isolation red-team verified
4. DR drill completed within target RPO/RTO in the last quarter
5. SOC2 control mapping reviewed and signed off by security
6. LLM-as-judge evaluation shows no regression vs previous deployed adapter on held-out per-domain eval sets
