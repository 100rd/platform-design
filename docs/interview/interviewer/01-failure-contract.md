# Interviewer guide — Challenge 1: The Ten Ephemeral Apps

> Do not share with candidates. Candidate brief: [`../candidate/01-failure-contract.md`](../candidate/01-failure-contract.md).

## 1. What this challenge measures

Whether the candidate understands that **error handling in a distributed stack is a property
of the system, not of each app**, and whether they can turn a wish ("handle errors properly")
into rules that a machine can check. Ten individually "correct" apps can still produce a
broken system: restart storms, retry storms, double-posting, a green verifier over a broken
user journey.

The challenge sits on three real gaps in this repo:

1. [`developer-manifest.md`](../../developer-manifest.md) Rule 4 tells teams `/healthz` returns
   200 "when the app is functional". "Functional" is undefined, and most engineers read it as
   "my dependencies are up".
2. The manifest has no rule about timeouts, retries, idempotency, error format or start-up
   ordering. Ten apps from four teams therefore follow four opinions.
3. The preview's Conditions of Done
   ([ADR-0058](../../adrs/0058-precommitted-http-probe-evidence.md)) are three passing `GET`s
   per backend. That proves reachability, not failure behaviour.

## 2. The trap

Most candidates open with a best-practice list: circuit breakers, exponential backoff,
structured logs, health checks, a service mesh. Every item is fine and none is checkable. The
first turning point comes when you ask **"how would the platform know a team broke this rule?"**
Strong candidates have already asked themselves that question. Weak ones discover there is no
answer.

The second turning point is the health probe. Wiring dependencies into **liveness** turns a
dependency incident into a process incident on every replica at once (curveball C1). Wiring a
*shared* dependency into **readiness** is subtler and is the staff-level point: readiness is a
load-balancing signal *between replicas*. When every replica shares the cause, every replica
goes not-ready together. The Service then has zero endpoints, so readiness doesn't help, and
removing capacity for a soft dependency actively hurts.

## 3. Level calibration

| Level | What they produce unprompted |
|---|---|
| **Middle** | Correct per-app hygiene: separate liveness and readiness, timeouts on every call, SIGTERM drain, JSON errors. Struggles to say how any of it is enforced. |
| **Senior** | System effects: restart storms, retry amplification with arithmetic, at-least-once delivery → idempotency. Each rule gets a check, and fault injection runs in the preview. |
| **Staff** | Who owns what: teams *declare* deps and degraded behaviour, the platform *injects* and *verifies*. Thinks about rolling the contract out to four teams in three languages, versioning it, proving the checks themselves work, and what the contract costs. |

## 4. Reference answer

Not the only good answer. Use it to calibrate.

### 4.1 The contract (v2 of the manifest's error-handling section)

| # | Rule | Why | Checked where |
|---|---|---|---|
| 1 | **Liveness** reflects only whether the process can make progress (event loop not wedged, not deadlocked). It never checks a dependency. | A dependency blip must not become a fleet-wide restart. | Verifier: make Postgres unreachable for 60 s; assert restart count unchanged. |
| 2 | **Readiness** reflects the replica's own state: warming up, overloaded, draining. A *hard* dependency outage is reported per request (typed 503, rule 6), not by flipping readiness. | Readiness chooses between replicas; it can't help when all replicas share the cause. | Verifier: break a dep; EndpointSlice must keep the backends; edge must return a typed 503 within the deadline. |
| 3 | **Start-up** never requires a runtime dependency. The app starts, reports not-ready until warm, and connects in the background with jittered backoff. Ordering is allowed only for schema (`db-migrate` PreSync, ADR-0032). | Start order stops mattering, and nothing pays the kubelet back-off tax inside a 2 h TTL. | Verifier: deploy in reverse order; time-to-ready ≤ budget (e.g. 3 min). |
| 4 | **Every outbound call has a deadline.** The remaining deadline propagates (`grpc-timeout` or a deadline header) and each hop gets only what's left. No client is created with library defaults. | Go, Python and Node default to *no timeout*. Without propagation, inner work continues for callers who left long ago. | Telemetry: spans that end after their parent; CI lint for bare default clients. |
| 5 | **Exactly one layer retries** (the edge or an Envoy/Gateway policy), under a **retry budget** (e.g. retries ≤ 20% of requests), and only on errors marked `retryable`. Inner services fail fast. | Retries multiply per layer (C2). | Verifier: inject 503 at ledger; amplification ratio (calls at ledger ÷ calls at edge) ≤ 1.2. |
| 6 | Errors cross HTTP as a **typed envelope**: RFC 9457 `application/problem+json` with a stable `type`, `retryable`, `dependency` (if caused by one) and `trace_id`. Never return 2xx with an error body. | Edge, verifier, dashboards and error-budget attribution can classify errors without per-team parsers. | Verifier oracle: every non-2xx is valid problem+json; a 2xx body matching the error schema fails. |
| 7 | Overload is **shed early** with 429/503 + `Retry-After`. Queues are bounded. | Latency → timeout → retry is the classic death spiral. | Preview load step at 2× declared RPS; p99 bounded and errors typed. |
| 8 | Message consumers are **idempotent** on a producer-minted key, and **ack only after** the side effect is committed. | At-least-once + Spot + consolidation means redelivery is routine. | Verifier: kill the consumer between side effect and ack; exactly one ledger row. |
| 9 | Producers that write state *and* emit events use a **transactional outbox**, not "write then publish". | Otherwise you get phantom events or lost events on partial failure. | Verifier: fail the DB commit after publish; no orphan event. |
| 10 | Poison messages go to a **DLQ** after K attempts, with the error envelope attached. A non-empty DLQ fails the preview. | Prevents head-of-line blocking and makes async failures visible. | Verifier: publish a malformed message. |
| 11 | On **SIGTERM**: fail readiness, keep serving through the endpoint-propagation delay (≥ 5 s), stop accepting, drain, and exit before the grace period. Long work checkpoints or nacks. | The 30 s rule ignores propagation lag and in-flight messages. | Verifier: roll a deployment under load; zero 5xx at the edge, zero lost messages. |
| 12 | **Soft-dependency failures degrade, they don't fail.** Each app declares which deps are soft and what the degraded response looks like (header or field). | Turns "is Redis critical?" into a testable claim. | Verifier: break each soft dep; assert 2xx + degraded marker. |
| 13 | Each app **declares its dependencies** in the catalog: hard or soft, timeout, who retries. | Makes rules 3, 5 and 12 checkable by the platform. | CI: schema; runtime: undeclared egress denied by Cilium policy. |

### 4.2 Why this is provable in two hours

Long-lived environments prove **rates** (statistics over weeks). Ephemeral environments can
prove **behaviour under induced faults**, which is deterministic and repeatable. The preview's
Conditions of Done should therefore include platform-owned fault conditions, not only happy
`GET`s:

```
CoD-1  happy journey: place order → order settled (end state, not HTTP 200)
CoD-2  reverse-order start → ready within 3 min
CoD-3  Postgres unreachable 60 s → no restarts, typed 503 at edge, recovery < 30 s
CoD-4  ledger returns 503 → amplification ratio ≤ 1.2
CoD-5  kill settler mid-message → exactly one ledger row
CoD-6  Redis unreachable → journey 2xx with degraded marker
CoD-7  poison message → DLQ = 1, consumer keeps consuming
CoD-8  rolling restart under load → zero edge 5xx
```

Teams only declare deps and degraded behaviour. The platform owns the injector, the oracle
and the evidence, which matches the existing ADR-0058 model where the worker can't choose its
own oracle.

### 4.3 Proving the checks work

Every check runs nightly against a **known-bad reference stack**: one app per rule that
deliberately violates exactly that rule. The suite must fail on exactly those apps. A check
that has never caught anything is not known to work.

## 5. Curveballs — play one at a time

Each one has: the prompt, the walkthrough you should hear, follow-up probes, and what separates
weak from strong.

### C1. The restart storm

> "Team ledger followed today's rule literally: `/healthz` (also used as liveness) runs
> `SELECT 1` against Postgres. The shared preview RDS fails over and refuses connections for
> 40 seconds. 14 previews are alive. Walk me through the next five minutes, with numbers from
> the brief."

**Walkthrough you want to hear**

- `t = 0`: RDS refuses connections. Every ledger request fails, and so does every liveness probe
  (1 s timeout).
- `t ≈ 30 s`: 3 failures × 10 s period, so the kubelet kills **all 28 ledger pods** (14 × 2) at
  roughly the same moment. In-flight requests die mid-way, and callers retry them (see C2).
- `t ≈ 30–40 s`: pods restart, open their pools eagerly, RDS is still refusing, and the app
  exits on start-up. Back-off begins at 10 s.
- `t ≈ 40 s`: RDS is back, but pods are sitting in back-off. They start at ~50 s, then need
  readiness to pass and the pool to warm.
- **Result:** a 40 s database event becomes a ~60–90 s ledger outage. Restart counts also
  accumulate, and the kubelet back-off resets only after 10 minutes of healthy running. A
  second blip within 10 minutes therefore waits 20 s, 40 s, 80 s… The outage amplifies with
  every repeat.

**The numeric check.** Many candidates shout "connection exhaustion!". Ask them to compute it:
28 pods × 20 = **560 connections**, well under 1 700. Exhaustion is *not* what happens in
previews. What actually breaks is recovery time. It becomes exhaustion in prod, or when
reconnect loops have no jitter or back-off. A candidate who does the arithmetic and corrects
themselves is showing exactly the signal you want.

**Follow-up probes**
- "So whose fault is it, team ledger's or the platform's?" Best answer: the platform's. The
  manifest *told* them to do it.
- "Should readiness check Postgres instead?" This tests the staff-level point from §2.
- "These previews share one RDS. What does one preview's bad migration do to the other 13?"
  Shared-fate thinking: previews are not isolated from each other.

**Weak →** "Use a circuit breaker." **Strong →** rewrites rules 1–3, adds jittered reconnect,
and names the preview-to-preview blast radius.

### C2. Retry multiplication

> "edge-gw, web-bff, orders and pricing each make 3 attempts on a 5xx or timeout. ledger is
> slow. How many calls reach ledger for one user click? How long can that one click keep the
> system busy? Then make the rule enforceable without reading anyone's code."

**Walkthrough you want to hear**

- Calls: 3 attempts per layer, 4 layers, so 3⁴ = **81** calls at ledger per click. If "3
  retries" means 1 + 3, it's 4⁴ = **256**. Either way, a 10% slowdown at ledger becomes a
  self-inflicted DDoS.
- Time: suppose each hop has a 5 s timeout. pricing can then spend 3 × 5 = 15 s, orders 45 s,
  web-bff 135 s and the edge 405 s, while the user gave up after ~30 s. Most of that work is
  for nobody. With the default Go, Python and Node clients there is **no timeout at all**, so
  calls hang instead of retrying, and goroutines, sockets and threads pile up.
- Fix: one retry owner, a budget rather than a count, retry only on `retryable` errors, and
  propagated deadlines so an inner hop can't outlive its caller.
- Enforcement without reading code: (a) put retry policy at the Gateway/Envoy layer, which the
  platform owns; (b) **measure amplification** in the preview: inject 503 at ledger and count
  calls at ledger ÷ calls at the edge (Hubble flow counts or spans), failing above 1.2;
  (c) telemetry for spans that end after their parent.

**Follow-up probes**
- "Exponential backoff with jitter — does it fix this?" No. It spreads the 81 calls in time but
  doesn't reduce them.
- "Your single retry owner is the edge. A transient blip at ledger now costs the user a full
  round trip. Acceptable?" Wants a trade-off: slightly worse latency on rare transient errors in
  exchange for no storms.
- "What about non-idempotent POSTs?" Retries are only safe with idempotency keys (ties to C4).

### C3. Ten minutes of nothing

> "Apps start in random order. orders calls `os.Exit(1)` if RabbitMQ isn't reachable at start-up.
> RabbitMQ's vhost becomes ready 3 minutes after the preview starts. When is orders ready?
> And web-bff exits if orders isn't ready. Fix it without sync waves."

**Walkthrough you want to hear**

- orders starts at 0 s and fails, then restarts at 10 s, 30 s, 70 s, 150 s and **310 s**
  (back-off 10, 20, 40, 80, 160). RabbitMQ was ready at 180 s, but orders stays down until
  310 s. That is **130 s of pure back-off tax**.
- web-bff has the same pattern behind orders, so the delays **compound**: the preview can take
  8–12 minutes to come up, which is roughly 10% of a 2 h TTL, every time.
- Fix: rule 3. Start, report not-ready, connect in the background. Sync waves order *apply*,
  not *readiness of dependencies*, and they couple the apps' release mechanics together.
- Make it a Condition of Done: **time-to-ready ≤ 3 min from a reverse-order start**.

**Follow-up probes**
- "db-migrate still has to run before ledger. Contradiction?" No: ordering on **schema** is
  legitimate (PreSync, ADR-0032). Ordering on **runtime connectivity** is not.
- "Could the platform just raise the back-off cap?" It treats the symptom, and the cap is a
  kubelet setting, not a per-app one.

### C4. Double-posting

> "settler consumes `payment.captured`, calls ledger over HTTP, then acks. Karpenter
> consolidates the node between ledger's 200 and the ack. What happens? Whose job is it to make
> it right, the platform's or the team's?"

**Walkthrough you want to hear**

- The channel closes, the unacked message is redelivered (up to `prefetch = 50` messages at
  once), the second settler calls ledger again, and the payment is posted twice.
- The idempotency key must be **minted by the producer** at the business event (payment id). Not
  a consumer-generated UUID, which changes per delivery, and not a timestamp. ledger enforces
  uniqueness in the same transaction as the write (unique constraint, insert-or-return-existing).
- Ownership: the platform **guarantees at-least-once delivery and says so in the contract**,
  the team guarantees idempotency, and the platform **tests** it (CoD-5).

**Follow-up probes**
- "Could we just ack first, then call ledger?" That swaps duplicates for **loss**. Which one is
  worse for money? Duplicates can be reconciled, and losses are often invisible.
- "How long must ledger remember keys?" Longer than the maximum redelivery delay plus DLQ
  replay. In a preview that's trivial; in prod it's a storage and retention decision.
- "orders writes the order row and publishes `order.created` synchronously. The publish succeeds
  and the DB commit fails. Now what?" A phantom event. Answer: **transactional outbox**
  (rule 9).

**Red flag:** "Use exactly-once delivery" without explaining what is exactly-once *end to end*.

### C5. Green but wrong

> "The ADR-0058 verifier went green: three consecutive 200s on every backend. People using the
> preview still see 'Something went wrong'. Give me at least three ways that's possible here."

Expect several of:
- 200 with `{"error": …}` in the body. Teams return HTTP status inconsistently.
- The probed path is shallow (`/healthz`, `/version`) and touches no dependency.
- The verifier probes **each backend directly**. The user's path goes through edge-gw →
  web-bff, so it fails on routing, auth or CORS, which no backend probe sees.
- The failure is **async**: the order is accepted, settlement never happens, the DLQ fills.
  No `GET` touches it.
- A soft dependency silently degrades the result (empty catalog, stale prices).

Strong: a typed error envelope (rule 6), plus a **journey Condition of Done** that asserts an end
state (order `settled`, DLQ empty) rather than a status code.

### C6. The error budget that isn't

> "A colleague proposes: each preview gets a 99.9% availability SLO. Good idea?"

A 2 h preview with a few hundred requests can't support a 99.9% claim. One error fails it, and
zero errors proves little: with 300 requests and 0 errors, the 95% confidence upper bound on the
error rate is still ~1% (the "rule of three": 3 / n). Strong: ephemeral environments prove
behaviour under injected faults, and long-lived environments prove rates. Each answers a
different question. Bonus if the candidate computes the rule of three unprompted.

### C7. Where does each rule live?

> "Teams will violate every rule. Pick what goes into admission, CI, the preview verifier, and
> code review. What's the principle behind the split?"

Listen for a principle, not a list:

| Layer | What belongs there | Examples |
|---|---|---|
| **Admission** (Kyverno/VAP) | Static, declared facts in the manifest | probes defined; liveness path ≠ readiness path; liveness has no `exec` hitting a DB client; `terminationGracePeriodSeconds` ≥ declared drain; dependency declaration present |
| **CI** | Library-level behaviour that can be unit/contract tested | error envelope schema; no default HTTP clients (lint); idempotency-key handling in consumer tests |
| **Preview verifier** | Emergent, cross-app behaviour | amplification, restart storms, time-to-ready, redelivery, DLQ, degraded mode |
| **Code review** | Judgement only humans can make | is this dependency *really* soft? is this error *really* retryable? |

The principle: **check each rule at the earliest layer that can actually observe the
property.** Static facts are checked early and cheaply; emergent behaviour can only be checked
when the system runs. Strong: adds the known-bad reference stack (§4.3).

### C8. Rolling it out (staff-level)

> "Four teams, three languages, ten apps, and a release next week. How do you roll the contract
> out without stopping everyone? Do you ship a client library, rely on the network layer, or
> only test?"

Trade-offs to hear:
- **Per-language SDK** (timeouts, deadlines, envelope, idempotency helpers): highest fidelity,
  but three libraries to maintain and versions drift.
- **Network layer** (Gateway/Envoy retry budgets, timeouts): language-agnostic, but it can't
  enforce idempotency, error envelopes or degraded modes.
- **Contract tests + verifier only**: cheapest for the platform, but every team re-implements
  the same things.
- **Rollout:** ship the checks in *warn* mode, publish a per-app scorecard, then flip rules to
  *enforce* one at a time. Run the C1/C2-class rules first, because they cause cross-team damage.
  Use a versioned contract (`failure-contract/v2`) with a dated deprecation of v1.

## 6. If the candidate is stuck

Use these in order and stop at the first that unblocks them. Note in the scorecard how many
hints they needed.

1. "Who reads the result of `/healthz`, and what does it *do* with it?"
2. "Take one user click. Trace it hop by hop. What happens if the last hop is slow?"
3. "What does RabbitMQ do with a message whose consumer died before acking?"
4. "If I deployed an app that broke your rule tomorrow, which system would notice first?"

## 7. Signals

**Strong**
- Separates liveness, readiness and start-up by **who acts on the signal** (kubelet kills,
  EndpointSlice routes, nothing yet).
- Thinks in **amplification** and **shared fate**: across hops and across previews.
- Every rule comes with a falsification test, and the checks themselves are tested.
- Moves the burden: teams declare, the platform injects and verifies.
- Does the arithmetic (28 × 20 = 560 < 1 700; 3⁴ = 81; 310 s back-off) and lets the numbers
  change the conclusion.

**Weak**
- A list of best practices with no enforcement.
- "Add a service mesh" as the whole answer, without saying which rules it can and can't enforce.
- Treats the 2 h TTL as an inconvenience instead of a design input.

**Red flags**
- Keeps dependency checks in liveness after C1.
- "Exactly-once" as a magic property.
- Can't do the C2 arithmetic, or doesn't see why it matters.

## 8. Scoring anchors

| Dimension | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Framing | Writes style rules for one app | Sees cross-app issues when prompted | Treats error handling as a system property | Also designs ownership: declare / inject / verify |
| Mechanism | "It would fail" | Describes the failure qualitatively | Walks the storm, retry tree and redelivery step by step | Uses the brief's numbers and corrects their own first guess |
| Verifiability | No checks | Checks for some rules | Check + violation signal for every rule | Plus a known-bad reference stack proving the checks |
| Trade-offs | None named | Names costs when asked | Names costs unprompted (single retry owner, outbox complexity) | Chooses SDK vs network vs tests per rule with reasons |
| Altitude | Stays inside one pod | One preview | 14 previews on shared RDS and RabbitMQ | Plus rollout across teams and contract versioning |
