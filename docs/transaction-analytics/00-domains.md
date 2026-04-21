# Domains

Four transaction-heavy domains, each a separate product line on the same platform. They share the base model (Qwen 2.5 3B), the data-plane components, and the edge deployment pattern — they differ in inputs, SLAs, and template shape.

---

## Domain matrix

| Property | HFT | Solana | Insurance exchange | RTB |
|----------|-----|--------|--------------------|-----|
| Transactions we execute? | No | No | No | No |
| Raw input at edge | Trade tape, quotes, order-book deltas | Program accounts, transaction instructions, slot updates | Quote/policy documents: PDF, XLS, JSON, XML | OpenRTB bid requests, win notifications |
| Edge scoring SLA (p99) | <20 ms | <30 ms | <500 ms (document-bound) | <20 ms |
| Template mining cadence | End-of-day + event-triggered | End-of-epoch + event-triggered | Per-document-class + event-triggered | End-of-day + event-triggered |
| Primary model shape | LLM (reasoning over tape patterns) + XGBoost (numeric signals) | LLM (program-level semantics) + similarity search (Qdrant) | LLM (document understanding after extraction) | XGBoost (bid-valuation) + small LLM (creative classification) |
| Feedback source | Traders, scoring engineers | On-chain outcome (success/revert, MEV extracted) + analyst review | Underwriters, claims adjusters | Campaign performance (CTR, conversion) + fraud analysts |
| Compliance sensitivity | High (market-abuse surveillance risk) | Medium (public chain data) | Medium (PII in documents, no cardholder data) | Low-to-medium (user data in bid stream, GDPR) |

---

## HFT — High-frequency trading session analysis

### What we do

Clients run their own trading engines at exchange co-locations. They ship us raw tape (every trade, every quote, every order-book delta) via a Kafka producer running alongside their engine. In their co-lo we also run our edge agent, which applies the current templates + model to score each transaction in real time — risk flagging, anomaly detection, strategy-alignment scoring. Post-session, their tape flows to the UK DCs where we mine algorithmic templates for next-session deployment.

**Important boundary**: we do not route, broker, or otherwise intermediate trades. The scoring agent runs on client hardware and its output goes to the client's own risk and compliance systems — not back to the exchange. Our exposure is purely analytic.

### Data contract

- Topic: `{tenant}.hft.ingest`
- Format: one message per market event, protobuf schema in `apps/chains/hft/protos/`
- Fields: venue, instrument, event_type (trade|quote|book_delta|cancel), timestamp_ns, price, size, side, order_id, counterparty_id (if disclosed by venue), session_id
- Throughput target: 2M events/sec per tenant peak, 200k sustained

### Template shape

JSON rule set per strategy, with three layers:
1. Fast filter (pure numeric thresholds over rolling windows) — evaluated in Rust or Go, not LLM
2. Pattern match (short natural-language descriptions of market microstructure events the strategy targets or avoids) — LLM input
3. Score aggregation weights learned per-strategy

### SLAs

- Edge scoring p99: <20 ms, p99.9: <50 ms
- Edge scoring availability: 99.99% during market hours (per venue)
- Template refresh: next trading session after end-of-day tape lands (usually 4-6 h window)
- Retraining trigger: 100k new labelled events per strategy or drift-detected regime change

### Not in scope

- Executing orders, hedging, any actual trading
- Market-making book-building (client's own engine)
- Regulatory reporting to FCA / SEC — output feeds client's reporting, we do not submit directly

---

## Solana — On-chain transaction analysis

### What we do

Ingest Solana slot-level data via a Geyser plugin on client-operated RPC nodes, or via a public/private RPC subscription where the client chooses. Analyse program-level behaviour — DEX interactions, lending-protocol positions, MEV opportunities, token-flow patterns. Edge agent scores new transactions within the 30 ms budget; UK DCs mine templates from epoch-level history.

### Data contract

- Topic: `{tenant}.solana.ingest`
- Format: Borsh-encoded transaction envelopes, plus parsed instruction streams for programs the tenant cares about
- Fields: slot, signature, fee_payer, instructions[], account_writes[], compute_units_consumed, pre/post balances per account of interest
- Throughput: 10-50k tx/sec per tenant depending on programs tracked

### Template shape

- Program-call graph patterns (sequences of instructions across composable programs)
- Account-state similarity clusters (Qdrant-backed) — "this transaction's pre-state looks like these 50 historical examples"
- Natural-language pattern descriptions for novel flows the LLM describes when it encounters an unfamiliar program interaction

### SLAs

- Edge scoring p99: <30 ms (slightly laxer than HFT because slot times are ~400 ms)
- Edge scoring availability: 99.9%
- Template refresh: per epoch (~2 days) and on-demand when novel program detected
- Retraining trigger: 100k new labelled transactions or new program deployment detected

### Not in scope

- Running validator nodes for clients
- Custody of keys or signing transactions
- MEV extraction or sandwiching (analytic detection only)

---

## Insurance exchange — Contract / quote scoring

### What we do

Our client is (or operates) an **insurance exchange** — a marketplace where underwriters and brokers post requests for insurance and counter-offers are made, similar in mechanism to RTB but with far longer cycle times and document-heavy payloads. Documents arrive as PDF, XLS, JSON, or XML depending on the counterparty. The edge agent (running at the exchange's co-lo) extracts structured content, scores for fraud markers, risk classification, and template-fit against historical policy archetypes.

### Data contract

- Topic: `{tenant}.insurance.ingest`
- Format: envelope with `document_type`, `bytes` or `payload` (base64 for binary, inline JSON/XML), `metadata` (counterparty, line-of-business, requested limits, dates)
- Throughput: 50-500 documents/sec (far lower than transactional feeds, but each document is much larger — up to a few MB)

### Template shape

- Per-line-of-business document schemas (what fields to extract)
- Risk archetype embeddings (Qdrant) — "this application looks like these historical underwriting decisions"
- Fraud markers (rule-set + numeric scoring)
- Natural-language flag explanations — edge agent emits short rationales that go into the underwriter's workflow

### SLAs

- Edge scoring p99: <500 ms (document-processing-bound — PDF OCR dominates for scanned submissions)
- Edge scoring p99 for structured inputs (JSON/XML): <100 ms
- Template refresh: per document class (auto, property, marine, cyber, etc.), refreshed when accumulated label count passes threshold
- Retraining trigger: 10k new labelled documents per class (lower than transaction domains because each document carries more signal)

### Note on payment data

Insurance documents in our scope contain **confirmations of payment receipt**, not cardholder data. Premium flows happen outside our view. This keeps the entire platform out of PCI-DSS scope — see [07-compliance-security.md](07-compliance-security.md).

---

## RTB — Real-time bidding analysis

### What we do

Our client operates an ad exchange or a bidder. Bid requests arrive over the OpenRTB protocol at exchange scale (hundreds of thousands per second at peak). The edge agent scores each request for bid worthiness — traffic quality, fraud likelihood, audience-fit — within the OpenRTB auction budget. Post-auction win/loss and subsequent campaign performance data flows back through the Kafka back-channel; this becomes the label stream for retraining.

### Data contract

- Topic: `{tenant}.rtb.ingest`
- Format: OpenRTB 2.6 bid request + bid response + win notice + (delayed) conversion signal
- Throughput: 200k-1M bid requests/sec per tenant at peak

### Template shape

- Numeric feature-vector templates per audience segment / campaign type — consumed by XGBoost primarily
- Small LLM path for creative classification and novel-format handling (short inputs, tight budget)
- Fraud-pattern rules (user-agent, IP reputation, session-behaviour anomalies)

### SLAs

- Edge scoring p99: <20 ms (hard limit — OpenRTB auction windows are ~100 ms and we are only one component)
- Edge scoring p99 for XGBoost-only path: <2 ms
- Template refresh: end-of-day + every 6 hours for high-volume tenants
- Retraining trigger: 1M new bid outcomes (high volume → high threshold)

### Not in scope

- Bidding itself (the client's bidder owns the auction participation)
- Ad creative storage or serving
- Attribution modelling (this is a separate ML product not in this platform)

---

## What is common across domains

Despite surface differences, every domain has the same pipeline shape:

```
[client transaction source]
    │
    ▼ Kafka {tenant}.{domain}.ingest
    │
    ├── Edge agent → scores in real-time → client's own risk / compliance / auction system
    │                            ▲
    │                            │ pulls signed OCI + templates
    │                            │
    │                            └── AWS control plane (Kargo rollout)
    │
    └── (parallel) landed in QuestDB (hot) + Iceberg (cold, UK DC)
                                │
                                ▼ Airflow: train_domain_adapter (triggered at 100k samples)
                                │
                                ▼ vLLM multi-LoRA + LLM-as-judge debate eval
                                │
                                ▼ TRT-LLM engine build + sign + publish
                                │
                                ▼ Kargo canary → batch → full fleet
```

Per-domain differences live inside the edge agent's scoring code paths and inside the template schema; the pipeline is uniform.
