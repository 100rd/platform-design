# Challenge 3 — Ninety-Nine Percent of What?

> The target is "the platform is 99% working". There are **150 microservices** and shared
> databases, queues and storage. Define the target, measure it, and defend it.

## Situation

From [`platform-design.excalidraw`](../../architecture/platform-design.excalidraw),
[SPEC-07](../../../specs/SPEC-07-observability.md) and
[SPEC-08](../../../specs/SPEC-08-resilience-data.md):

- **150 services** across ~20 teams, two active-active regions behind **AWS Global
  Accelerator** with **TCP/443** health checks.
- **Shared data plane:** PostgreSQL on RDS (Multi-AZ, **no cross-region replica**; regional loss =
  snapshot restore, ~1 h RTO), Redis (cache / feature store), RabbitMQ (eventing), QuestDB
  (time series), Iceberg on S3 (lake).
- **Observability:** Prometheus/Thanos + Loki + Tempo, VictoriaMetrics for GPU, Pyrra
  SLOs-as-code (`99.9%` availability and `p99 ≤ 500 ms @ 99%`, 28-day windows),
  Alertmanager → PagerDuty. The observability stack runs **inside the workload clusters**.
- **DNS failover:** a `failover-controller` swaps nameservers at the registrar using scores
  written by `dns-monitor` into a **shared PostgreSQL** database; at most **1 failover per day**,
  1-hour cooldown.
- **Delivery:** Kargo promotions gated by staging SLO queries; Argo Rollouts canaries in prod.

The failure-mode matrix in SPEC-08 §5.2 lists what is automated and what is manual. Read it.

## Your task

1. **Define "99% working".** Of what, measured where, over what window, as seen by whom?
   Make leadership's sentence into an SLI and SLO you'd put your name on.
2. **Compose it.** How do the SLOs of 150 services and 5 shared data stores relate to the
   platform number? Do the arithmetic. Is the target achievable with the current per-service
   targets?
3. **Detect it.** Design how you'd know — within minutes — that the platform has dropped below
   target, including when the thing that's broken is the observability stack itself.
4. **Defend it.** Pick the three changes to this architecture that buy the most availability per
   unit of effort. Show the reasoning, not just the list.

## Deliverable

- The SLI/SLO definition (one paragraph and one formula).
- The composition model with numbers.
- A detection design that names, for every signal, what it would **not** see.
- An allocation of the monthly error budget across its main consumers.
- Your top three changes, ranked, with the estimated gain for each.

## Things worth thinking about

- 150 services at 99.9% each — what do you get if a request touches all of them? Does any request?
- What does a TCP/443 health check say about a service returning 500s?
- When the region dies, who tells PagerDuty?
- A 28-day window at 99% allows ~6.7 hours of downtime. Is one 6-hour outage "meeting the SLO"?
