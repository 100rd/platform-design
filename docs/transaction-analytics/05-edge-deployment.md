# Edge deployment

The edge agent runs on client-operated hardware at client-chosen venues. We do not own the boxes; we own the software and the artefact supply chain. Two distribution formats are supported side-by-side: signed OCI image and raw binary.

---

## What the edge agent does

Exactly three things:

1. **Consume** the ingest Kafka topic for its (tenant, venue, domain) scope
2. **Score** each transaction through XGBoost fast-filter → LLM deep-analysis (as applicable per domain), backed by a local Redis feature cache
3. **Emit** results to the client's downstream system (the client's risk, compliance, auction, or underwriting pipeline) **and** emit telemetry + feedback to the reverse Kafka topics

It does not:
- Make outbound calls to our control plane for every transaction (everything is Kafka-mediated, asynchronous, at-most-once for ingest and at-least-once for telemetry)
- Store long-term data locally (local state is ephemeral Redis + a small WAL for in-flight telemetry buffering)
- Accept shell / SSH / admin access from our side (operational access is client-owned; we ship artefacts, they run them)

---

## Artefact formats

### OCI image (preferred)

- Distroless base, single statically-linked Go binary with CGo bindings to TRT-LLM runtime
- Includes the precompiled TRT-LLM engine for the target GPU family
- Includes the Triton FIL runtime for XGBoost
- Includes the templates bundle
- Signed with Cosign; clients verify via `cosign verify` with our public key before pulling into their runtime
- Published to our OCI registry (AWS ECR Public by default; we also support publishing to a client-chosen private registry mirror)

Why OCI first: client SREs know how to run containers. It is the lowest operational cost for us to support.

### Raw binary (fallback)

- Statically-linked ELF for Linux amd64 and arm64 (GoReleaser builds both)
- Tarball contains: the binary, the TRT-LLM engine file, the templates bundle, a systemd unit file, an example config file, a README for first-time install
- Signed via detached `.sig` file (Cosign blob signing)
- Installed at `/opt/edge-agent/` (default; configurable)
- Runs as a dedicated `edge-agent` user with `systemd` hardening (`NoNewPrivileges=true`, `ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`, `CapabilityBoundingSet=` minimal set)

Why raw binary second: some clients (particularly in HFT co-lo) have policies against running containers in production. We meet them where they are.

### What the two formats share

- Same source code, same build pipeline
- Same signing key, same release cadence, same version numbers
- Same configuration schema — a single YAML file drives both
- Same telemetry / feedback surface

Operational cost of supporting both is kept low by making the container essentially "the binary in a tiny wrapper image".

---

## Target hardware

| Tier | GPU | Memory | Typical deployment |
|------|-----|--------|--------------------|
| Default | NVIDIA L40S | 48 GB | Most RTB, Solana, insurance, and HFT tenants |
| High-throughput | NVIDIA H100 or H200 | 80 / 141 GB | HFT tenants with extreme throughput needs |
| CPU-only fallback | None | — | Clients refusing GPU deployment; XGBoost-only scoring |

The TRT-LLM engine is compiled per-hardware at the UK build farm. A single release produces (by default) L40S, H100, H200, and CPU-fallback variants. `promote_to_edge` in Airflow triggers all four builds in parallel.

---

## Kafka back-channel

### Why Kafka both ways

We already have Kafka as our ingest transport between edge and UK. For telemetry, feedback, and heartbeat, standing up a separate HTTP / gRPC observability channel would double the infrastructure surface on the client network. Reusing Kafka:

- Single outbound firewall rule on the client side (Kafka broker addresses, mTLS port)
- Same auth story (per-venue certs)
- Natural buffering under network partition — if UK is unreachable, messages queue locally in the agent's WAL and drain when connectivity returns
- Consistent ordering per (tenant, venue) partition key

### Topics the agent produces to

```
{tenant}.{domain}.telemetry
    - OTel metrics (scoring latency histograms, request rate, error rate, GPU util)
    - OTel logs (structured, one event per scored transaction in audit mode; sampled in perf mode)
    - OTel traces (sampled; full trace for flagged transactions)
    - Heartbeat: agent version, model version, template bundle version, config hash, uptime
    - Self-reported hardware state: GPU temp, memory pressure, thermal throttle events

{tenant}.{domain}.feedback
    - When the client plumbs outcomes back into the agent (opt-in, post-deployment integration), outcomes are forwarded onto this topic so they reach UK and feed the label pipeline
    - Clients who prefer to ship feedback via an out-of-band pipeline (their own Kafka, SFTP, etc.) are also supported; the agent itself does not require this feature
```

### Topics the agent consumes from (beyond ingest)

```
{tenant}.{domain}.templates
    - Log-compacted topic; most recent message per key is the current template bundle metadata
    - Agent polls on startup and listens for updates; on update, pulls the new template bundle from the artefact registry and swaps it in atomically

_platform.control.{tenant}.{venue}
    - Control-plane messages scoped to this exact edge instance
    - Used for: forced rollback to previous version, dynamic feature flags, cohort membership changes
```

### Security on the Kafka back-channel

- Per-venue client certs issued via cert-manager; short lifetime (30 days); rotated automatically via External Secrets Operator polling
- Kafka ACLs scoped so that a venue's credentials can only produce to its own telemetry / feedback topics and consume from its own ingest / templates / control topics
- mTLS required on all listeners; no plaintext ports exposed

---

## Rollout via Kargo

The existing Kargo deployment used for in-cluster progressive delivery is extended to cover the edge fleet. Kargo-for-edge treats each (tenant, venue) as a deployable target and orchestrates per-cohort rollouts.

### Stages

```
staging-synthetic     → UK-internal edge simulator, runs synthetic transactions 24h
tenant-canary         → one volunteer tenant, one venue, for 24h
tenant-batch-A        → 30% of that tenant's venues, for 24h
tenant-all            → remaining venues of that tenant
fleet-canary          → first venue of every remaining tenant, for 24h
fleet-batch-A         → 30% of fleet
fleet-all             → full rollout
```

### Auto-rollback signals

At every stage, Kargo consumes the `{tenant}.{domain}.telemetry` topic for the cohort and evaluates against SLO gates:

- Scoring latency p99 exceeds +15% vs pre-rollout baseline (2 min rolling)
- Error rate > 0.5% (2 min rolling)
- Heartbeat gap > 60 s for any venue in the cohort
- Model score distribution KL-divergence > threshold vs baseline (drift guard — catches the case where the new adapter starts emitting wildly different scores)

Breach ⇒ automatic rollback of that cohort to previous (adapter, templates) tuple. The rollback path is the same delivery mechanism — a new Kargo release pointing at the prior OCI digest — so the rollback itself is canary-guarded.

### Rollback mechanics on edge

- OCI case: Kargo pushes the previous image digest into the tenant's manifest; their k8s cluster (or Nomad, or whatever they run) rolls back via standard controller semantics.
- Raw binary case: the agent is a blue-green install on the client host. The systemd unit points at `/opt/edge-agent/current`, which is a symlink to either `/opt/edge-agent/versions/{old}` or `/opt/edge-agent/versions/{new}`. Rollback flips the symlink and restarts the unit. Both versions stay on disk until the next successful rollout, so rollback is a filesystem operation, not a download.

---

## Health model

### Graceful degradation

The agent must keep scoring even when its support dependencies are impaired. Degradation ladder:

1. **All green** — full pipeline: fast-filter → LLM deep-analysis when triggered → Redis cache hot
2. **Redis cold** — cache miss recomputes features inline; latency degrades but pipeline stays up
3. **Kafka telemetry topic unavailable** — local WAL buffers up to 1 GB of telemetry; when full, oldest-wins; scoring itself is not impacted
4. **Kafka ingest topic partition rebalance** — consumer reconnects with backoff; transactions missed during the window are replayed from the client's retained topic
5. **GPU failure / thermal throttle** — agent falls back to XGBoost-only scoring, emits a critical telemetry event, alerts UK control plane
6. **Template bundle corrupted or missing** — refuses to start, emits a critical event via local syslog + any available out-of-band channel; Kargo rollback triggered by control plane

### Self-update policy

The agent **does not self-update**. Updates are pulled by a separate agent-updater process (OCI case: standard registry pull by the client's orchestrator; raw binary case: a small `edge-agent-updater` systemd timer that polls our update endpoint, verifies Cosign signature, pre-stages the new bundle, waits for Kargo green-light, flips the symlink). This keeps the blast radius of a bad update isolated from the scoring hot path.

---

## Observability surface from AWS Grafana

Every edge instance is a first-class observable entity. The operator view includes:

- Fleet heatmap: per-tenant × per-venue × per-domain scoring latency p99
- Version-drift map: which adapter and template version is running in each venue; highlights anomalies (venues lagging rollout, unauthorised versions)
- Rollout status: current Kargo stage per tenant, time-in-stage, gate-evaluation status
- Per-venue deep-dive: scoring latency histograms, error rates, GPU temp, request rate, label-feedback rate
- Alert panels: venues with scoring latency breach, venues with heartbeat gap, venues with model-drift detection

Dashboards ship under `monitoring/dashboards/transaction-analytics/edge-*.json`. VMAlert / Alertmanager rules under `k8s/monitoring/alerts/edge-*.yaml`.

---

## Onboarding a new venue

Sequence when a tenant adds a new co-lo site (e.g., existing HFT client wants to add FR2):

1. Tenant provisions hardware (per our sizing doc shared out-of-band)
2. We issue per-venue Kafka client cert via External Secrets → cert-manager
3. We register the venue in Postgres `venues` (tenant, site, hardware profile, network details)
4. We publish the current production OCI image + templates to the tenant's venue-specific control topic
5. Tenant pulls and deploys (OCI via their orchestrator, or downloads + unpacks raw binary + systemd install)
6. Agent starts, identifies itself via cert, begins consuming ingest topic
7. UK control plane sees heartbeat on telemetry topic, registers venue as healthy
8. Kargo tracks this venue for future rollouts

End-to-end: same day for a known tenant, one to three days for a new tenant (cert issuance + network config usually dominates).
