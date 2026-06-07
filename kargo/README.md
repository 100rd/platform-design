# kargo/

Kargo environment-promotion configuration for the platform.

## Provenance

Implemented per **ADR-0021** (Kargo as the GitOps environment-promotion layer).
Chart bumped 1.2 -> 1.9 (`apps/infra/kargo/`); Prometheus `AnalysisTemplate`s
added to replace job-probe verification gates.

Argo Rollouts is **not** deployed in this repo. Kargo promotes **Argo CD
Applications directly** across environments. A future ADR may introduce Argo
Rollouts canary _below_ Kargo (within a single environment); that is explicitly
out of scope for ADR-0021.

## Structure

```
kargo/
├── analysis-templates/
│   ├── health-check.yaml            # job-probe: ArgoCD sync/health check
│   ├── smoke-test.yaml              # job-probe: HTTP probe
│   ├── integration-test.yaml        # job-probe: /health + /ready probes
│   ├── prometheus-5xx-error-rate.yaml  # Prometheus: 5xx error-rate gate (ADR-0021)
│   └── prometheus-p95-latency.yaml     # Prometheus: p95 latency gate (ADR-0021)
├── projects/                        # Kargo Project CRDs (5 projects)
├── stages/                          # Stage CRDs per project x environment
│   └── <project>/
│       ├── dev.yaml                 # auto-promote, health-check only
│       ├── integration.yaml         # auto-promote, health-check + integration-test
│       ├── staging.yaml             # manual ok, + prometheus gates
│       └── prod.yaml                # manual/digest-pinned, + prometheus gates
└── warehouses/                      # Warehouse CRDs (image sources)
```

## Promotion graph

```
dev (auto) -> integration (auto) -> staging -> prod (manual, digest-pinned)
```

Dev and integration auto-promote. Staging and prod require the
Prometheus gates (`prometheus-5xx-error-rate`, `prometheus-p95-latency`) to pass,
in addition to the existing job-probe checks.

## Prometheus gates (ADR-0021)

Metrics are sourced from **Tempo metrics-generator RED metrics** (requires
ADR-0019 — Tempo wiring). Without ADR-0019, the gates fail open/closed with no
data. Sequencing: activate ADR-0019 before flipping gates from job-probe to metric.

| Template | Metric | Threshold |
|---|---|---|
| `prometheus-5xx-error-rate` | `http_server_request_errors_total` / `http_server_requests_total` | < 1 % error rate |
| `prometheus-p95-latency` | `http_server_request_duration_seconds_bucket` p95 | < 500 ms (tunable) |

Both templates accept `service`, `namespace`, `prometheus-address` args
(and `latency-threshold-ms` for the latency gate) that can be overridden
per-Stage if needed.
