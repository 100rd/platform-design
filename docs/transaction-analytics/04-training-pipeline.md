# Training pipeline

How labelled data becomes a new LoRA adapter, a new template bundle, and ultimately a signed edge artefact. All of this runs in the UK DC on the H100 training pool.

---

## Overall shape

```
[labels accumulate in Postgres]
          │
          ▼
[threshold crossed OR drift detected OR manual trigger]
          │
          ▼
[Airflow: train_domain_adapter]
   ├── freeze training snapshot in Iceberg (versioned)
   ├── SFT + LoRA on Qwen 2.5 3B (DeepSpeed ZeRO-3, 8× H100)
   └── register adapter in Postgres
          │
          ▼
[Airflow: eval_adapter_debate]
   ├── load candidate adapter into vLLM multi-LoRA (H200 pool)
   ├── load teacher (Qwen 2.5 72B) and judge (independent-family model)
   ├── run debate on held-out eval set per tenant/domain
   └── write eval report to Postgres
          │
          ▼ [if eval passes gate]
[Airflow: mine_templates]
   ├── run batch template mining over same training window
   ├── output: JSON rules + numeric vectors + NL descriptions
   └── register template bundle in Postgres
          │
          ▼
[Airflow: promote_to_edge]
   ├── merge LoRA into base weights
   ├── quantize to fp8
   ├── compile TRT-LLM engine per target_hardware
   ├── build OCI image and raw binary with engine + templates
   ├── sign with Cosign
   ├── publish to OCI registry
   └── register release candidate in Kargo
          │
          ▼
[Kargo progressive rollout to edge fleet]
```

---

## Label sources

Three streams feed the label store:

### 1. Historical strategy outcomes

For HFT and RTB, every scored transaction eventually has a realised outcome the client tells us about over the feedback topic — trade P&L, bid win + conversion, etc. This is the largest-volume label source.

Pipeline:
- `{tenant}.{domain}.feedback` Kafka topic consumed continuously
- Outcomes joined (by transaction id) with the original ingest record and the score we emitted at the time
- Joined row written to Iceberg `labels.{domain}.outcome` and reflected in Postgres for quick query

### 2. Expert annotations

Traders, scoring engineers, underwriters, claims adjusters — whoever the domain expert is — review suspicious or novel transactions in **Argilla**, our hosted labelling UI.

Pipeline:
- `suspicious_picker` DAG selects candidates nightly: high-score outliers, high-uncertainty predictions, drift-segment members, novel-feature detections
- Candidates pushed into Argilla dataset per tenant per domain
- Experts review, accept / reject / correct
- Argilla webhook writes accepted labels to Iceberg `labels.{domain}.curated` and mirrors to Postgres

### 3. Synthetic labels (optional, opt-in per domain)

For label-sparse domains, we run a larger teacher model (Qwen 2.5 72B or similar) on unlabelled data to produce initial labels that then go through expert review at a reduced sampling rate.

This is not enabled by default. It is the escape hatch for bootstrapping a new domain where we have lots of raw data but no outcomes or annotations yet.

---

## Retraining triggers

Three kinds of triggers, any of which wakes up `train_domain_adapter`:

### Threshold trigger (default)

- 100k new labels accumulated since last training for a given (tenant, domain) pair
- Lower for insurance (10k) because each document carries more signal; higher for RTB (1M) because volume is enormous and labels are noisy
- Configurable per-tenant via Postgres `tenants.retrain_thresholds` JSON column

### Drift trigger

- Distributional drift monitor runs as a scheduled Airflow DAG hourly
- For each (tenant, domain), compute a reference distribution over key features from the last training window and compare against the current rolling window
- On KL divergence > configurable threshold, or on appearance of previously-unseen feature values at a material rate, trigger retraining immediately

### Manual trigger

- On-call engineer or tenant representative can trigger retraining via `kubectl create job --from=cronjob/train-domain-adapter-<tenant>-<domain> ...`
- Used for: tenant onboarding completion, major label-correction batches after Argilla cleanup, suspected training bug where a rerun is warranted

---

## Training job internals

**Base + adapter**
- Base: Qwen 2.5 3B, pinned at a specific HF revision, stored in Iceberg `_platform.models.qwen-2.5-3b/`
- Adapter: LoRA, rank 16, targets all attention + MLP projections, dropout 0.05

**Compute**
- DeepSpeed ZeRO-3 across 8× H100 in a Volcano gang job
- fp16 training, bf16 inference-time evaluation
- Activation checkpointing enabled; gradient accumulation sized to fit 100k tokens / effective batch

**Data**
- Training snapshot is a **frozen** Iceberg table version, recorded in Postgres `runs` table with the exact Iceberg version id
- 90/10 train/eval split at snapshot time, deterministic splitter seeded by snapshot id
- Sequence length cap per domain: HFT 2k (tape windows), Solana 4k (program-call chains can be long), insurance 8k (document context), RTB 1k (compact bid requests)

**Hyperparameters**
- Learning rate 1e-4, cosine decay, 3% warmup
- Epochs: 3 for tenant-initial run, 1 for incremental retrains with recent labels
- Early stopping on eval loss plateau

Actual hyperparameters live in `training/configs/{domain}.yaml` and are evolved over time; above is the default starting point.

**Output**
- LoRA adapter files written to Iceberg `_platform.adapters.{tenant}.{domain}.{adapter_id}/`
- Training metrics written to Postgres `runs`: loss curves, eval perplexity, wall time, GPU hours
- W&B logging (optional, can be disabled for tenants that don't want external observability)

---

## LLM-as-judge debate evaluation

This is the **gate** between "we trained an adapter" and "we ship it to production". Replaces traditional single-metric eval (perplexity, accuracy) with a structured debate.

### Participants

- **Candidate**: the newly-trained adapter running on vLLM multi-LoRA
- **Incumbent**: the currently-deployed adapter for the same (tenant, domain) — what the candidate would replace
- **Teacher**: Qwen 2.5 72B (same family, but much larger) — represents "what an unconstrained reasoner would conclude"
- **Judge**: an independent-family model (Llama 3.3 70B or DeepSeek-V3 — see [PLAN.md](../../PLAN.md) Phase 3 open question). Critical that the judge is not same-family as candidate and teacher, to reduce self-preference bias.

### Protocol per eval item

1. Eval item = one transaction + its ground-truth label from the held-out set
2. Candidate and incumbent each produce a score + short rationale
3. Teacher produces its own score + rationale as reference
4. Judge sees all three rationales (not the scores) and the ground truth, ranks which rationale best explains the outcome
5. Record: which rationale won, how much the candidate diverges from the teacher on the score, whether candidate improves vs incumbent on ground-truth-distance

### Aggregate gate

To promote candidate:
- Candidate wins against incumbent in >55% of items (i.e., improvement over status quo)
- Candidate's score distance from ground truth is not worse than incumbent's at p95
- Judge's rationale preference for candidate is not worse than incumbent's
- No category of eval items (sliced by domain-specific strata: by strategy, by venue, by document class, etc.) shows significant degradation

Thresholds are configurable per tenant. Conservative tenants can set 60/65% thresholds.

### Why debate rather than scalar metrics

- A pure scalar metric (accuracy, F1) is easy to game and hard to reason about when it moves. The rationale-based preference captures "the candidate is making better-justified decisions", which is closer to what a trader or underwriter actually cares about.
- LLM-as-judge with debate also gives us interpretable failure modes: when candidate loses, we get the judge's reasoning for why, which is directly useful for the next training iteration.

### Cost

- Debate eval is expensive — easily hours of GPU time on H200 pool per promotion.
- Budgeted as a first-class workload in the Volcano queue; takes priority over internal LiteLLM traffic.
- Amortised by only running eval on promotion candidates, not on every training step.

---

## Template mining

Parallel to adapter training, and equally important. Templates are what the edge agent applies directly as rules or as LLM-context.

### Inputs

- Same training window as the adapter
- Plus the adapter's own predictions on that window (we mine templates from "what the model does", not only from "what happened")

### Mining strategies per domain

- **HFT**: frequent-pattern mining over event sequences (PrefixSpan-style) + clustering in embedding space to identify strategy archetypes. Output: ~50-200 patterns per strategy, each with numeric feature gates and a short natural-language description generated by the LLM.
- **Solana**: program-call graph mining using a custom DAG mining algorithm; similarity clusters of accounts via Qdrant. Output: per-program template library.
- **Insurance**: document-class-specific schemas learned from Iceberg `documents_structured` using heuristics + an LLM pass; fraud-marker rules refined by expert feedback. Output: per-line-of-business template set.
- **RTB**: audience-segment feature vectors + rule sets from decision-tree surrogate models trained on XGBoost predictions. Output: segment-wise scoring rules.

### Versioning

Each template bundle is content-hashed and stored in Iceberg `_platform.templates.{domain}.{bundle_id}/`. The edge agent records which bundle it is running and reports this via the heartbeat topic, so the control plane always knows the template version running in every venue.

### Relationship to adapters

Adapters and templates are versioned together. A given edge OCI image contains one adapter (merged into a TRT-LLM engine) and one template bundle that was mined from the same training window. They are promoted together — never mixed across training windows.

---

## Airflow DAG catalogue

| DAG | Schedule | Inputs | Outputs |
|-----|----------|--------|---------|
| `collect_feedback` | continuous (Kafka consumer) | `{tenant}.{domain}.feedback` | Iceberg labels.outcome, Postgres labels |
| `suspicious_picker` | nightly | QuestDB hot data + recent predictions | Argilla dataset items |
| `drift_monitor` | hourly | Recent QuestDB slice vs reference distribution | Triggers retraining or fires alert |
| `train_domain_adapter` | triggered | Iceberg labels, base model | LoRA adapter (Iceberg + Postgres registry) |
| `mine_templates` | triggered (after train) | Iceberg training window + adapter | Template bundle |
| `eval_adapter_debate` | triggered (after train) | Candidate, incumbent, held-out set | Debate result in Postgres |
| `promote_to_edge` | triggered (after eval pass) | Adapter + templates | Signed OCI + raw binary + Kargo release candidate |
| `post_deployment_smoke` | 30 min after edge canary starts | Telemetry from canary cohort | Pass/fail flag to Kargo |
| `nightly_iceberg_compaction` | daily 03:00 UTC | Iceberg warehouse | Compacted files, deleted manifests |
| `warehouse_dq` | daily | Iceberg tables | Data-quality report (nullability, range, cardinality) |

All DAGs are in `training/dags/` and deployed via the `apps/infra/airflow/` Helm chart.

---

## Reproducibility invariants

Every production adapter must have an auditable provenance chain:

1. Iceberg snapshot version for the training data
2. Base model weight hash
3. Training config hash
4. Training run id (Postgres `runs.id`)
5. Eval run id (Postgres `runs.id`)
6. Template bundle id
7. Cosign signature + key id used for edge artefact

Given any deployed adapter id, we can reconstruct the exact training data, rerun the training (same seed, same config) and verify the adapter reproduces within tolerance. This is a hard requirement for the SOC2 change-management control and for any regulated tenant (surveillance use cases in HFT).
