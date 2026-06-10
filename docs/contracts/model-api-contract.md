# Model API Contract

**Version:** 1.0.0
**Status:** Ratified — enforced as a pre-staging-promotion gate (see
`docs/golden-paths/RACI-and-handoffs.md` §Handoffs, Handoff H3).
**Owners:** ML Engineering (spec author), Backend (consumer), Data Engineering
(feature schema), Platform/SRE (observability alignment).

All four personas must sign off on a new model's contract instance before the model
is promoted beyond staging. See `docs/contracts/example-domain-adapter-contract.yaml`
for a worked example and `templates/golden-paths/new-model-service/README.md` Step 5
for the sign-off checklist.

---

## 1. Versioning policy

- The contract version follows **semver** (`MAJOR.MINOR.PATCH`).
- A breaking change to request or response schema (removing a field, changing a type,
  narrowing an enum) increments `MAJOR`.
- A backward-compatible addition (new optional field, wider enum) increments `MINOR`.
- Documentation-only corrections increment `PATCH`.
- Each model's contract instance records the spec version it was written against.

---

## 2. Model request schema

All model-serving endpoints accept `application/json` conforming to:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12",
  "title": "ModelRequest",
  "type": "object",
  "required": ["model_name", "tenant", "domain", "features"],
  "additionalProperties": false,
  "properties": {
    "model_name": {
      "type": "string",
      "description": "MLflow registered model name (lower-kebab). Must match ADR-0037 registry entry.",
      "example": "domain-adapter-hft"
    },
    "tenant": {
      "type": "string",
      "description": "Tenant identifier (ADR-0038 multi-tenant label). Must match ml_monitoring metric labels.",
      "example": "tenant-acme"
    },
    "domain": {
      "type": "string",
      "enum": ["hft", "solana", "insurance", "rtb"],
      "description": "ML domain. Must match the Airflow DAG param enum."
    },
    "features": {
      "type": "object",
      "description": "Feature vector. Schema is model-specific; see §3.",
      "additionalProperties": true
    },
    "request_id": {
      "type": "string",
      "description": "Optional idempotency key. Used for OTel distributed tracing.",
      "example": "req-7f3a1b2c"
    },
    "model_version": {
      "type": "string",
      "description": "Optional MLflow model version. Omit to use the Production alias.",
      "example": "42"
    }
  }
}
```

### Request contract rules

1. `model_name` + `tenant` + `domain` must match the values registered in MLflow
   and the WS-C Evidently drift-exporter label set.
2. `features` must contain all fields listed in §3 for the given domain.
3. Backend services must set `request_id` to a value traceable via OTel/Tempo.

---

## 3. Feature schema

Feature schemas are domain-specific. The canonical source of truth for feature
definitions is the Iceberg schema in `docs/transaction-analytics/03-ml-inference.md`.

### 3.1 Common fields (all domains)

| Field | Type | Description |
|-------|------|-------------|
| `transaction_id` | string | Unique transaction identifier |
| `timestamp_utc` | string (ISO 8601) | Transaction timestamp. Format: `YYYY-MM-DDTHH:MM:SSZ` |
| `amount_usd` | number (float64) | Transaction amount in USD |
| `currency_code` | string | ISO 4217 three-letter currency code |
| `merchant_category` | string | MCC code string |

### 3.2 Domain-specific fields

#### hft (High-Frequency Trading)

| Field | Type | Description |
|-------|------|-------------|
| `bid_ask_spread` | number (float64) | Bid-ask spread at time of transaction |
| `order_book_depth` | integer | Number of price levels in order book |
| `venue_id` | string | Trading venue identifier |
| `latency_microseconds` | integer | Round-trip latency in microseconds |

#### rtb (Real-Time Bidding)

| Field | Type | Description |
|-------|------|-------------|
| `bid_floor_usd` | number (float64) | Auction floor price |
| `ad_slot_size` | string | Slot dimensions, e.g., "300x250" |
| `user_segment` | string | Anonymised user segment ID |
| `supply_type` | string | One of: `web`, `app`, `ctv` |

#### insurance

| Field | Type | Description |
|-------|------|-------------|
| `policy_id` | string | Policy identifier |
| `claim_type` | string | One of: `auto`, `home`, `health`, `commercial` |
| `risk_score` | number (float64, 0.0–1.0) | Pre-computed risk score |
| `days_since_last_claim` | integer | Days since last claim event |

#### solana

| Field | Type | Description |
|-------|------|-------------|
| `slot_number` | integer | Solana slot number |
| `transaction_type` | string | One of: `transfer`, `stake`, `swap`, `program_call` |
| `program_id` | string | Solana program address |
| `lamports` | integer | Transaction amount in lamports |

---

## 4. Model response schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12",
  "title": "ModelResponse",
  "type": "object",
  "required": ["model_name", "model_version", "tenant", "domain", "prediction", "latency_ms"],
  "additionalProperties": false,
  "properties": {
    "model_name": {
      "type": "string",
      "description": "Echo of the requested model_name."
    },
    "model_version": {
      "type": "string",
      "description": "Resolved MLflow model version that served this prediction."
    },
    "tenant": {
      "type": "string",
      "description": "Echo of the requested tenant."
    },
    "domain": {
      "type": "string",
      "description": "Echo of the requested domain."
    },
    "prediction": {
      "type": "object",
      "description": "Domain-specific prediction output. See §4.1.",
      "additionalProperties": true
    },
    "confidence": {
      "type": "number",
      "minimum": 0.0,
      "maximum": 1.0,
      "description": "Optional model confidence score."
    },
    "latency_ms": {
      "type": "number",
      "description": "Server-side inference latency in milliseconds."
    },
    "mlflow_run_id": {
      "type": "string",
      "description": "MLflow run ID of the training run that produced this model version. Enables full reproducibility audit (SOC2 / ADR-0040)."
    },
    "request_id": {
      "type": "string",
      "description": "Echo of the request_id if provided."
    }
  }
}
```

### 4.1 Prediction output (domain-specific)

Each domain's `prediction` object must contain at minimum:

| Domain | Required fields |
|--------|----------------|
| `hft` | `signal: string` (one of: `buy`, `sell`, `hold`), `edge_usd: number` |
| `rtb` | `bid_usd: number`, `win_probability: number` |
| `insurance` | `fraud_probability: number`, `risk_tier: string` |
| `solana` | `anomaly_score: number`, `anomaly_type: string` |

---

## 5. SLO targets

These are the minimum SLOs a model service must satisfy before production promotion.
Backend and ML leads jointly own these numbers.

| SLO | Target | Measurement |
|-----|--------|-------------|
| p50 latency | < 50ms | OTel Tempo, Prometheus histogram |
| p99 latency | < 200ms | OTel Tempo, Prometheus histogram |
| Error rate (5xx) | < 0.5% | Prometheus `http_requests_total` |
| Model accuracy | > 85% | Evidently drift-exporter (WS-C, ADR-0038) |
| Drift score | < 0.2 | Evidently/whylogs (WS-C, ADR-0038) |
| Availability | 99.9% | Alertmanager PrometheusRule (WS-D, ADR-0039) |

---

## 6. Observability alignment

To satisfy the WS-C (ADR-0038) monitoring contract, every model service must:

1. Emit `ml_monitoring_model_accuracy` and `ml_monitoring_dataset_drift_score`
   Prometheus metrics with labels `{model_name, tenant, domain}`.
2. Use the OTel Collector for distributed traces — set `request_id` in the
   `tracestate` header or as the OTel span ID correlation.
3. Log structured JSON with `model_name`, `tenant`, `domain`, `request_id`,
   `latency_ms`, and `model_version` on every inference request.

---

## 7. Changelog

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 1.0.0 | 2026-06-10 | platform-team (WS-F ADR-0041) | Initial contract |
