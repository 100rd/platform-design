# Data plane

Storage, streaming, and query infrastructure. ClickHouse is not used — this doc explains the alternative stack and why each piece was chosen.

---

## Component map

| Concern | Component | Tier | Why this over alternatives |
|---------|-----------|------|----------------------------|
| Transaction ingest + back-channel | **Apache Kafka** (KRaft mode) | UK | De facto standard, works bidirectionally with the same cluster, mature mTLS + ACL story, MirrorMaker 2 for DR replication |
| Tick hot storage | **QuestDB** | UK | Nanosecond timestamps, column-store time-series optimised for write-then-aggregate, SQL-compatible, tuned for exactly this workload |
| Cold archive + template warehouse + training datasets | **Apache Iceberg on MinIO** | UK | Open table format, schema evolution, time travel (useful for reproducible training), MinIO gives us S3 semantics on owned hardware |
| Batch analytics | **DuckDB** (embedded in Airflow jobs) + **Trino** (cluster) | UK | DuckDB for small-to-medium jobs running inside a DAG task; Trino when a query spans tens of TB or needs cross-tenant federation (rare) |
| Hot feature cache | **Redis Cluster** | Edge + UK | Sub-ms lookups, well-understood operational model; edge instance for scoring, UK instance for control plane |
| State: template registry, model registry, label store, tenant metadata | **PostgreSQL** (CloudNativePG on UK, existing RDS module on AWS for control plane) | UK + AWS | Transactions, referential integrity, no reason to reach for a specialised store |
| Vector similarity search | **Qdrant** | UK | Rust-native, performant, self-hostable, supports per-tenant collections with strict isolation |

---

## Why not ClickHouse?

ClickHouse is a defensible choice and does appear in the reference MLOps job description that inspired part of this platform's shape. We did not pick it because:

- Our hot-path workload is write-dominated tick ingestion with time-series aggregation queries — QuestDB is explicitly tuned for this shape and consistently outperforms ClickHouse by 3-5× on trade-tape benchmarks at the throughputs we target.
- Our analytical workload is batch over frozen partitions (end-of-day template mining) — Iceberg + DuckDB/Trino is more flexible for this than ClickHouse, because we get open table format (other readers, versioning) and cheaper storage via MinIO.
- Keeping two specialised stores (QuestDB hot, Iceberg cold) with a clean handoff is simpler to operate than one hybrid store that does both jobs adequately.

Nothing prevents adding ClickHouse later if a specific use case demands it; the architecture does not depend on the choice.

---

## Kafka topology

### Topic naming

```
{tenant}.{domain}.ingest       — transactions in
{tenant}.{domain}.telemetry    — edge → UK observability data
{tenant}.{domain}.feedback     — outcomes, labels, expert flags
{tenant}.{domain}.templates    — UK → edge template rollout notifications
```

- Keyed by `venue` + `instrument` (or domain-equivalent) so a single partition preserves causal order within a venue.
- Retention: `ingest` = 7 days (long enough for replay into QuestDB + Iceberg under failure); `telemetry` = 30 days; `feedback` = 7 years (label data for training lineage; confirm retention length with legal per jurisdiction); `templates` = log-compacted, key by template_id.

### Security

- mTLS on every listener. Client certificates issued per tenant + per edge venue via the existing cert-manager stack.
- SASL/SCRAM for internal service-to-service auth (Airflow, DAG tasks, vLLM, Argilla).
- ACLs strictly per-tenant. A tenant cert cannot list or consume topics outside its prefix.

### Replication between UK primary and standby

- MirrorMaker 2 runs bidirectionally but in "active-passive" logical mode: primary is the write side, standby's mirror is read-only.
- On failover, the mirror direction flips and consumer group offsets are translated via MM2's offset-sync topic.
- Target lag under normal load: <10 s; measured continuously by a synthetic probe that round-trips a watermark message.

---

## QuestDB

### What goes in

- Output of `Kafka Connect` with the QuestDB ILP sink — one table per `{tenant}.{domain}` combination.
- Column layout optimised for "filter by time range + aggregate by instrument/venue/counterparty" which is the 90% query.

### Retention

- 30 days hot. Older partitions detached and written to Iceberg as Parquet at end-of-day.
- Retention per tenant is configurable (some HFT tenants need 90 days hot for intraday pattern-mining windows — we handle this by expanding their hot window, not by changing the default).

### Access pattern

- Edge agent **does not read from QuestDB directly**. Ever. Edge only reads from its local Redis cache.
- Airflow DAGs read QuestDB for per-day feature computation.
- Grafana reads QuestDB for tenant-facing dashboards (query through a multi-tenant proxy that injects tenant-scoped filters).

---

## Iceberg + MinIO

### Why Iceberg

- Open table format means training code, Trino, DuckDB, Spark (if ever needed) can all read the same table without a tight coupling to a single engine.
- Schema evolution is built in — we change feature schemas continuously as we add new domain signals.
- Time-travel semantics give us exact reproducibility for training: a model was trained on version X of table Y at timestamp T, and we can read it back unchanged.

### Layout

```
s3://{tenant}/
    hft/
        ticks/                 (Parquet, partitioned by day)
        orderbook_snapshots/   (Parquet, partitioned by day)
        training/
            v20260101_01/      (frozen training snapshot)
    solana/
        transactions/
        program_calls/
    insurance/
        documents_structured/
        documents_raw/         (original files, retained for audit)
    rtb/
        bids/
        outcomes/

s3://_platform/
    templates/{domain}/{template_id}/
    models/{base_model}/{version}/
    adapters/{tenant}/{domain}/{adapter_id}/
    engines/{target_hardware}/{tenant}/{domain}/{engine_id}/
```

### Why MinIO

- S3-compatible API lets any S3 SDK work unchanged.
- Self-hosted means data stays on our UK hardware, no cloud egress fees.
- Site replication covers the primary → standby DR path natively.

---

## Batch analytics: DuckDB vs Trino

Rule of thumb, enforced in code review:

- Job reads <100 GB and runs inside one Airflow task → DuckDB embedded. No cluster to babysit, no query planner overhead, finishes in a single node's memory/disk.
- Job reads >100 GB, joins across tenants (rare), or is a long-running service-level query (Grafana, ad-hoc SQL from engineers) → Trino cluster.

Trino hits MinIO directly via the Iceberg connector; DuckDB reads Iceberg via the `iceberg` extension pointed at the REST catalog.

---

## Redis at the edge

- One Redis instance per edge agent process (colocated, not networked) — used for:
  - Last-seen state per venue / instrument (e.g., last order-book snapshot, last position)
  - Feature-vector cache (precomputed features that the agent otherwise would recompute per transaction)
  - Template rule cache (fast-path rule evaluation)
- Persistence: RDB snapshots every 5 min to local disk + AOF for strict modes (HFT, RTB). Redis is ephemeral state; losing it forces the agent to recompute, which is a few seconds of degraded performance — not data loss.

A separate central Redis runs in the UK DC for:
- Cross-venue state aggregation where applicable
- Kargo cohort membership (which edge instances are in which rollout wave)

---

## Postgres state

Single logical Postgres cluster per UK DC (CloudNativePG). Schema split:

- `templates` — id, domain, tenant, version, created_at, created_by, provenance (what labels it was mined from), binary blob reference in Iceberg
- `models` — base model registry, version, weights URI in Iceberg
- `adapters` — LoRA adapter registry, base_model_id, tenant, domain, training_run_id, eval_results_id
- `engines` — compiled TRT-LLM engine per (adapter, target_hardware), OCI reference, cosign signature, cosign key_id
- `labels` — label store (denormalised view of what's in Argilla), per-tenant scoped
- `tenants` — tenant metadata, KMS key references, contact info, compliance attestations
- `runs` — training run metadata, hyperparameters, metrics, LLM-as-judge outcomes

Schemas are per-tenant (`tenant_{id}.*`) for the data-bearing tables (labels, templates, adapters); platform-level tables (models, base infra) are in `public` and `platform`.

---

## Qdrant

Per-tenant collection per domain. Used for:

- Similarity search over historical transaction embeddings — "show me the 50 transactions most similar to this one"
- RAG for LLM-as-judge debate evaluation — judge has access to reference examples with known-correct labels
- (Future) Omniscience product uses the same Qdrant deployment with a `_platform.omniscience.*` collection namespace, but that is outside the scope of this document

Embeddings are produced by a small embedding model (not Qwen — we use a dedicated 100M-parameter embedder for cost) running on CPU pool, generated on ingest via a Kafka consumer that reads `{tenant}.{domain}.ingest`.

---

## End-to-end trace of one tick

To make the data flow concrete, here is what happens when tenant-A's HFT engine emits a single trade event at venue LHR:

```
1. Client engine at LHR writes the event to its local Kafka producer
   → message lands in Kafka topic tenant-a.hft.ingest, partition keyed by (LHR, instrument=XYZ)

2. Edge agent (also at LHR co-lo) consumes the same partition
   → decodes protobuf → computes features → Redis lookup for last-seen state
   → runs XGBoost (Triton FIL) fast-filter scoring (<2 ms p99)
   → if fast-filter triggers "deeper analysis", runs Qwen 2.5 3B + LoRA on TRT-LLM engine (<15 ms p99)
   → aggregates score → emits to client's risk system
   → emits telemetry + scoring result to tenant-a.hft.telemetry

3. In parallel, a Kafka Connect sink at UK primary consumes tenant-a.hft.ingest
   → writes one row to QuestDB table tenant_a.hft.ticks (<2 s end-to-end)

4. A second Kafka consumer at UK primary reads the same topic
   → computes embedding → upserts into Qdrant collection tenant_a_hft (<5 s)

5. At midnight UTC, an Airflow DAG "hft_end_of_day" runs for tenant-a
   → detaches QuestDB partition for the day, writes to Iceberg s3://tenant-a/hft/ticks/dt=2026-04-21/
   → computes aggregate stats, writes to Iceberg s3://tenant-a/hft/session_summaries/
   → if label count for tenant-a.hft has crossed 100k since last training, triggers train_domain_adapter DAG

6. train_domain_adapter:
   → reads s3://tenant-a/hft/training/vYYYYMMDD_NN/ (frozen snapshot of labelled data)
   → fine-tunes Qwen 2.5 3B with LoRA on H100 pool using DeepSpeed ZeRO-3
   → output adapter registered in Postgres adapters table

7. eval_adapter_debate:
   → loads new adapter into vLLM multi-LoRA on H200 pool
   → runs debate eval against teacher model and independent judge
   → results written to Postgres runs table
   → if pass: triggers promote_to_edge

8. promote_to_edge:
   → merges LoRA into base, quantizes to fp8, compiles TRT-LLM engine on H200 pool
   → builds edge OCI image with engine + new templates bundle
   → signs with Cosign, publishes to OCI registry
   → notifies Kargo of new release candidate

9. Kargo rolls out: canary (1 edge instance) → batch A → full fleet
   → at each stage, telemetry from the rollout cohort is compared against baseline
   → auto-rollback on SLO breach
```

Every arrow in this trace has telemetry; the SRE view in AWS Grafana shows the flow end-to-end per tenant, per domain.
