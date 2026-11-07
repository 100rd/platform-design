# Interviewer guide — Challenge 1: The Ten Ephemeral Apps

> Do not share with candidates. Candidate brief: [`../candidate/01-failure-contract.md`](../candidate/01-failure-contract.md).

## The trap

The current manifest says `/healthz` returns 200 "when the app is functional". Most candidates
read "functional" as "my dependencies are up" and wire database and broker checks into the
probe. Behind that sits the real question: **error handling in a distributed stack is a property
of the system, not of each app.** Ten "correct" apps can make a broken system (retry storms,
restart storms, double-posting). A good candidate notices early that per-app rules need
system-level invariants, and that a rule nobody can check is just a wish.

## Reference shape of a strong answer

Not the only good answer — use it to calibrate.

| # | Rule | Why | Checked where |
|---|---|---|---|
| 1 | Liveness reflects **only the process's own ability to make progress**; it never checks a dependency. | A dependency blip must not become a fleet-wide restart. | Preview verifier: break Postgres, assert zero restarts. |
| 2 | Readiness reflects **ability to serve its own contract**, may include *hard* deps, and must flip to not-ready within N s of a hard-dep loss and back within N s of recovery. | Takes the pod out of endpoints without killing it. | Verifier: break dep, watch EndpointSlice. |
| 3 | Startup does not require dependencies; the app starts, reports not-ready, and connects with jittered backoff. No ordering via init-container chains or sync waves for *runtime* deps. | Start order becomes irrelevant; no CrashLoopBackOff back-off tax on a 2 h TTL. | Verifier: deploy in reverse/random order, time-to-ready budget. |
| 4 | Every outbound call has a **deadline**; the deadline is propagated (header / gRPC deadline) and each hop only gets what's left. | Stops work for callers who already left. | Telemetry: spans that outlive their parent. |
| 5 | **Only one layer retries** (the edge, or a mesh/Envoy policy), with a retry *budget* (e.g. ≤ 10–20% extra load), not a per-call count; inner services fail fast. | Retries multiply per layer. | Fault-injection: count calls arriving at the bottom per user request. |
| 6 | Errors cross HTTP as a **typed envelope** (e.g. RFC 9457 `application/problem+json`) with a stable `type`, `retryable` flag and trace id; never 200 with an error body. | Lets the verifier, the edge and dashboards classify errors without per-team parsers. | Verifier oracle: schema check on non-2xx; reject 2xx bodies with an error shape. |
| 7 | Overload sheds early with 429/503 + `Retry-After`; it doesn't queue without bound. | Latency → timeout → retry is the classic death spiral. | Load test in preview at 2× expected RPS. |
| 8 | Message consumers are **idempotent** on a producer-assigned key; ack happens **after** the side effect commits. | At-least-once delivery + Spot/consolidation = redelivery is normal, not exceptional. | Kill consumer mid-message; assert exactly one ledger row. |
| 9 | Poison messages go to a DLQ after K attempts with the error envelope attached; a DLQ depth > 0 fails the preview. | Prevents head-of-line blocking; makes failures visible. | Verifier: publish a malformed message. |
| 10 | On SIGTERM: go not-ready, keep serving for the endpoint-propagation delay, stop accepting, drain, exit before `terminationGracePeriodSeconds`. | The 30 s rule ignores endpoint propagation lag. | Rollout during load; zero 5xx at the edge. |
| 11 | Soft-dependency failures **degrade**, they don't fail: each app declares which deps are soft and what the degraded response is. | Turns "is Redis critical?" into a testable claim. | Verifier: break each soft dep, assert 2xx + degraded marker. |
| 12 | The app's dependency list (hard/soft, timeout, retry owner) is **declared in the manifest/catalog**, not discovered. | Makes 3, 5, 11 checkable by the platform. | CI: schema validation; runtime: undeclared egress denied by Cilium policy. |

The thing that makes it **provable in 2 hours**: the preview's Conditions of Done include
**fault-injection conditions** (kill a dep, kill a pod mid-message, start in random order,
publish poison) — not just three happy `GET`s. The platform owns the injector; teams only
declare deps and degraded behaviour.

## Curveballs — play one at a time

### C1. The restart storm
> "Team ledger followed the current rule literally: `/healthz` pings Postgres. The shared RDS
> had a 20-second failover. There were 14 previews alive. What happened in the next 5 minutes?"

Listen for: liveness fails → every ledger pod in every preview restarts at once → all
reconnect at once → connection-limit exhaustion on RDS → failover becomes a longer outage, and
prod (same RDS? if they ask — no, but same *pattern*) would do the same. Strong: rewrites the
rule (liveness ≠ dependency), adds jittered reconnect, and notices the **shared** RDS makes
previews a blast-radius problem for each other. Probe: "Is it the app's fault or the rule's?"
— best answer: the rule's, because it was the platform's instruction.

### C2. Retry multiplication
> "edge-gw, web-bff, orders and pricing each retry 3 times on 5xx. ledger is slow. How many
> calls reach ledger for one user click? Now make the rule enforceable without reading code."

Arithmetic: 3 attempts × 4 layers = 3⁴ = **81** (or 4⁴ = 256 if "retry 3 times" means 1+3).
Strong: one retry owner + budget; deadline propagation so inner retries can't exceed the
outer deadline; enforcement at the network layer (Envoy/Gateway retry policy, mesh) or by
**measuring** amplification in the preview (calls at ledger ÷ calls at edge under injected
5xx). Weak: "teams should use exponential backoff" — backoff spreads load in time but doesn't
remove the multiplication.

### C3. Ten minutes of nothing
> "Apps start in random order. orders exits if RabbitMQ isn't reachable. CrashLoopBackOff
> caps at 5 minutes. The preview takes 12 minutes to get ready out of a 2-hour TTL. Fix it
> without sync waves."

Listen for: the back-off is the kubelet punishing exit-on-missing-dep; fix is rule 3 (start
not-ready, connect in background). Strong: sets a **time-to-ready SLO** for previews and makes
it a Condition of Done; notices sync waves only order *apply*, not *readiness of
dependencies*. Bonus: db-migrate is the one legitimate ordering (PreSync, ADR-0032) — data
schema, not runtime connectivity.

### C4. Double-posting
> "settler consumes `payment.captured`, calls ledger over HTTP, then acks. Karpenter
> consolidates the node between the HTTP 200 and the ack. What happens, and whose job is it
> to make it right — platform or team?"

Listen for: redelivery → second ledger call → double post. Fix: idempotency key minted by the
**producer** (not the consumer, not a timestamp), ledger enforces uniqueness transactionally.
Strong: "platform guarantees at-least-once and *tells you so*; the team guarantees idempotency;
the platform *tests* it" (kill-mid-message condition). Deeper: dedupe window must outlive
redelivery delay; in a 2 h preview it's trivial, in prod it's a storage decision. Red flag:
"use exactly-once delivery" without saying what's exactly-once *end-to-end*.

### C5. Green but wrong
> "The ADR-0058 verifier went green: three consecutive 200s on every backend. Users of the
> preview still see 'Something went wrong'. How?"

Listen for: 200 with an error body; probe hits a shallow path; the verifier tests reachability
of each backend, not the user journey; failures only on the async path (RabbitMQ) which no
`GET` touches. Strong: typed error envelope + a **journey probe** (e.g. place an order, wait
for `settled`) as a Condition of Done; async correctness asserted via an observable end state
(ledger row, DLQ empty).

### C6. The budget that isn't
> "A colleague proposes: each preview gets an error budget of 99.9%. Good idea?"

In 2 hours with a few hundred requests, 99.9% is statistically meaningless (one error = fail;
zero errors proves little). Strong: ephemeral environments prove **behaviour under induced
faults** (deterministic, repeatable), long-lived ones prove **rates** (statistical). Each
answers a different question; the contract needs both, in the right place.

### C7. Where does each rule live?
> "Teams will violate every rule. Pick three for admission, three for CI, three for the preview
> verifier, and say which you leave to code review. Why that split?"

Listen for a principle, not a list: admission for **static, declared** facts (probes defined,
liveness path ≠ readiness path, declared deps present, terminationGracePeriod ≥ drain); CI for
**library-level** behaviour (contract tests on the error envelope); verifier for **emergent**
behaviour (amplification, restart storms, idempotency); review for things only humans can
judge (is this dependency really soft?). Strong: "and I'd prove each check catches a broken
app by keeping a deliberately bad reference app in the suite" — a check that has never failed
is not known to work.

## Signals

**Strong**
- Separates liveness / readiness / startup by **who acts on the signal** (kubelet kills,
  EndpointSlice routes, nothing yet).
- Thinks in **amplification** and **shared fate** across previews, not just within one.
- Every rule comes with a falsification test.
- Moves the burden: teams declare, platform injects and checks.

**Weak**
- A list of best practices (circuit breakers! backoff! structured logs!) with no enforcement.
- "Add a service mesh" as the whole answer, without saying which rule it enforces and which
  it can't (idempotency, error envelope, degraded mode).
- Treats the 2 h TTL as an inconvenience instead of a design input.

**Red flags**
- Liveness checks dependencies, after C1.
- "Exactly-once" as a magic property.
- Cannot do the C2 arithmetic or doesn't see why it matters.

## Scoring anchors

| Dimension | 1 | 4 |
|---|---|---|
| Framing | Writes style rules for one app | Treats error handling as a system property with a contract and an enforcer |
| Mechanism | "It would fail" | Walks the restart storm / retry tree / redelivery step by step with numbers |
| Verifiability | No checks | Every rule has a check, a violation signal, and a known-bad app proving the check |
| Trade-offs | None named | Knows what a single retry owner costs (latency on transient errors) and when to accept it |
| Altitude | Stays inside one pod | Moves from one handler to 14 concurrent previews on one shared RDS |
