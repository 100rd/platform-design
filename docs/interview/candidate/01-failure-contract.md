# Challenge 1 — The Ten Ephemeral Apps

> Turn "handle errors properly" into a contract the platform can **check**, for a stack of ten
> short-lived apps written by different teams.

## Situation

Every pull request to the `checkout` product gets its own disposable preview environment:
a namespace `preview-<work-order-id>` (see the Realm and delivery-profile model in
[`platform-contracts/`](../../../platform-contracts/README.md) and
[ADR-0056](../../adrs/0056-machine-readable-platform-contracts.md)).
It lives for **at most 2 hours**, then compensation deletes it.

The preview stack has ten apps, owned by four teams, in Go, Node and Python:

```
                 ┌────────────┐
  user ─────────►│ edge-gw    │  Cilium Gateway API route
                 └─────┬──────┘
          ┌────────────┼──────────────┐
          ▼            ▼              ▼
     ┌────────┐   ┌─────────┐    ┌──────────┐
     │ web-bff│   │ auth    │    │ catalog  │──► Redis (shared, per-preview key prefix)
     └───┬────┘   └─────────┘    └──────────┘
         ▼
     ┌────────┐     ┌─────────┐     ┌─────────┐
     │ orders │────►│ pricing │────►│ ledger  │──► PostgreSQL (shared RDS, schema per preview)
     └───┬────┘     └─────────┘     └─────────┘
         │ publish                        ▲
         ▼                                │
   RabbitMQ (shared cluster, vhost per preview)
         │ consume
         ▼
     ┌──────────┐    ┌──────────┐    ┌───────────────────┐
     │ notifier │    │ settler  │───►│ ledger (via HTTP) │
     └──────────┘    └──────────┘    └───────────────────┘

  + db-migrate  (ArgoCD PreSync Job, ADR-0032)
```

Nodes are Karpenter-managed, partly Spot, and consolidate aggressively
([ADR-0046](../../adrs/0046-eks-node-strategy-karpenter-spot.md)).

## Facts and numbers you may use

Assume these are true. They exist so you can do arithmetic instead of guessing.

| Fact | Value |
|---|---|
| Concurrent previews at peak (working hours) | 14 |
| Replicas per app in a preview | 2 (db-migrate: one Job) |
| Postgres connection pool per `ledger` pod | 20, opened eagerly at start-up |
| Shared preview RDS `max_connections` | 1 700 |
| RDS Multi-AZ failover duration | 20–40 s of refused connections |
| Liveness probe defaults in the `helm/app` chart | `periodSeconds: 10`, `failureThreshold: 3`, timeout 1 s |
| Kubelet restart back-off | 10 s, 20 s, 40 s, 80 s, 160 s, then capped at 300 s |
| `terminationGracePeriodSeconds` default | 30 s |
| Endpoint removal → Gateway/Cilium stops routing | 1–5 s |
| Spot interruption notice | 2 min; consolidation evictions get only the grace period |
| Default HTTP client timeouts | Go `http.Client{}`: none · Python `requests`: none · Node `fetch`: none (until the socket dies) |
| RabbitMQ consumers | manual ack, `prefetch = 50`; unacked messages are redelivered when the channel closes |
| Typical sync path | `edge-gw → web-bff → orders → pricing → ledger` (4 hops below the edge) |
| Retry config found in the four teams' code today | "3 attempts on 5xx or timeout" in edge-gw, web-bff, orders and pricing |

## What the platform requires today

The entire error-handling contract is in [`developer-manifest.md`](../../developer-manifest.md):

- JSON logs to stdout; W3C Trace Context propagation.
- "Every service must expose `/api/health` or `/healthz` returning HTTP 200 when the app is
  functional."
- Handle `SIGTERM`, drain within 30 seconds, exit.

A preview counts as done when the platform's HTTP verifier gets three consecutive passing
`GET`s against every ready backend ([ADR-0058](../../adrs/0058-precommitted-http-probe-evidence.md)).

## Your task

Design the **failure contract** every app in this stack must meet — the error-handling part of
the developer manifest, version 2.

The contract must:

1. Say what each app must do when **a dependency fails, is slow, or isn't there yet** —
   at startup, while serving, and while shutting down.
2. Say how an error **crosses a hop** (HTTP and RabbitMQ) so that ten apps from four teams
   behave as one system instead of ten opinions.
3. Be **checkable without reading the code**. For each rule, say where it is enforced
   (admission, CI, the preview verifier, runtime telemetry, or code review) and what a
   violation looks like when it is caught.
4. Be **provable inside a 2-hour environment**. "It worked in prod last month" does not count.

## Deliverable

- The contract: 8–15 rules, each one sentence, each with a stated reason.
- An enforcement table: `rule → where checked → signal of violation → how you'd prove the
  check itself catches a deliberately broken app`.
- One paragraph: which rule you'd drop first if teams pushed back, and why that one.

## Things worth thinking about

- What does "functional" mean in `/healthz`, and who acts on the answer?
- If every layer is polite and retries, what does the bottom layer see?
- What happens to an in-flight message when its pod's node is consolidated?
- What does a 2-hour environment let you prove that a long-lived one doesn't — and the
  other way round?
