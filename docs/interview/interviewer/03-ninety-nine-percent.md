# Interviewer guide — Challenge 3: Ninety-Nine Percent of What?

> Do not share with candidates. Candidate brief: [`../candidate/03-ninety-nine-percent.md`](../candidate/03-ninety-nine-percent.md).

## The trap

"99% working" sounds like a low bar. It isn't, and it is also undefined. Typical first answers:

- **Average the 150 SLOs** — meaningless; nobody experiences an average.
- **Multiply them** — `0.999^150 ≈ 0.861`, so "impossible" — but no request touches all 150
  services, and services fail in correlated ways, so the independence assumption is wrong in
  both directions.

The real answer is built from **user journeys**: a small set of critical paths (checkout,
login, settlement…), each with its own dependency set, measured **from the outside**, and
composed with **shared dependencies counted once** — because the shared data plane dominates
the math.

## Useful numbers

| Target | per 30 days | per 28 days |
|---|---|---|
| 99% | 7.2 h | 6.72 h |
| 99.5% | 3.6 h | 3.36 h |
| 99.9% | 43.2 min | 40.3 min |
| 99.95% | 21.6 min | 20.2 min |

- `0.999^150 ≈ 0.861`; `0.999^10 ≈ 0.990`; `0.9999^150 ≈ 0.985`.
- A journey with 10 independent serial services at 99.9% each ≈ 99.0% — **already at the
  target with no margin** before counting the data plane, the edge, or DNS.
- One shared RDS at 99.95% used by all journeys caps *every* journey at 99.95% and, worse,
  **fails them together** — correlated loss, not independent.

## Reference shape of a strong answer

**SLI.** "Share of valid user-journey attempts that complete correctly within the latency
threshold, measured at the edge (or by synthetic probes outside the platform), per journey,
weighted by business importance." The platform number = the worst (or weighted) critical
journey, not an average of services. Optionally: **time-based** ("minutes in which journey
success ≥ X%") to stop a 6-hour outage hiding in a monthly ratio.

**Composition.** Journey availability ≈ edge × DNS × (∏ independent services on the path) ×
(shared deps counted once). The dominant terms are the shared ones: RDS (no cross-region
replica → regional loss = ~1 h restore = **most of a 99.9% monthly budget in one event**),
RabbitMQ, Redis, DNS failover limits. Service-level 99.9% SLOs are internally reasonable but
**do not add up** to a 99% platform without either fewer serial hops, soft dependencies, or
higher targets for shared components.

**Detection.** External synthetic journeys from outside both regions and outside AWS;
edge-level journey SLIs; multi-window burn-rate alerts (fast + slow); dead-man's switch from
inside to an external heartbeat receiver; each signal paired with what it can't see.

**Top changes (example ranking, candidate should argue their own).**
1. Journey SLIs at the edge + external synthetics — cheap, and without it nothing else is measurable.
2. Application-level health for Global Accelerator (HTTP journey check or traffic-dial
   automation on burn rate) — turns the manual "5xx with healthy TCP" row of SPEC-08 §5.2 into an automated one.
3. Break the RDS single-region dependency for the top journey (cross-region replica or
   journey-level degraded mode) — the largest single correlated term.

## Curveballs — play one at a time

### C1. Everything is green
> "All 150 Pyrra dashboards are green. Customers cannot check out. Give me at least four
> mechanisms in *this* architecture that make that possible, then the signal that would have caught it."

Good mechanisms (expect ≥ 4):
- Global Accelerator health is **TCP/443** — a region returning 500s stays in rotation (SPEC-08 §5.2 says so).
- SLIs measured **server-side**: requests that never arrive (DNS, edge, TLS, client timeouts) aren't counted.
- Errors returned as **200 with an error body** count as success.
- The failure is **async**: orders accepted, RabbitMQ backlog grows, settlement never happens — no request errors.
- Low-traffic service: SLO ratio with tiny denominators; or the error is in a journey step whose service has no SLO.
- A soft dependency silently degrading the result (empty recommendations, stale prices from Redis) — "successful" but wrong.
- Retries at the edge hide errors from the user-facing SLI but burn backends.

Signal: an **end-to-end journey probe** asserting the business outcome (order settled), from outside.

### C2. Who tells PagerDuty?
> "The observability stack runs inside the workload clusters. The region goes dark. Who pages?
> And look at the DNS failover: `failover-controller` and `dns-monitor` share one Postgres. What does that do?"

Listen for: shared fate — the monitor dies with the monitored. Fix: dead-man's switch (an
always-firing alert to an external receiver that pages on **absence**), external probes in a
different provider. On DNS: the detector and actuator share a database, so a Postgres outage
blinds both (SPEC-08 lists it as manual). Strong: "independence is a property you have to
design and *test* — every guard must not share a failure domain with what it guards."
Bonus: notices `consistency` is a hard-coded `1.0` placeholder in the health score, so 10% of
the score is fiction.

### C3. Soft or hard?
> "Teams swear Redis is a soft dependency for 120 of the 150 services. How do you find out
> it isn't — without waiting for the incident?"

Listen for: controlled fault injection (game days → continuous chaos) with a **hypothesis**,
a **blast radius** (one AZ, one % of traffic, one journey), an **abort condition** tied to
burn rate, and a **result that changes something** (fix or re-classify as hard). Strong: start
in previews (Challenge 1's fault conditions), then staging, then prod with traffic-%
limits. Red flag: "turn off Redis in prod on Friday and see".

### C4. The independence lie
> "Your math assumed independent failures. 40 services share one RDS cluster; all journeys
> go through RabbitMQ. Redo the estimate. What's the dominant term, and what's the cheapest
> change that moves the number most?"

Listen for: shared components act as **one** serial dependency for every journey that touches
them, with correlated failure — so the platform's floor is set by RDS/RabbitMQ/DNS
availability, not by the long tail of services. Cheapest lever is usually **making the shared
dep soft for the critical journey** (queue writes locally, degrade reads, cache) or **adding
redundancy only there**, not raising 150 SLOs. Ask for numbers: e.g. RDS regional event once a
year at ~1 h RTO ≈ 99.99% annualised, but ≈ 99.86% in *that* month — already over a 99.95%
monthly budget from one event. "Per month" vs "per year" changes the answer.

### C5. Whose budget is it?
> "Service X burned its error budget. 80% of its errors were Redis timeouts — a platform
> component. Kargo now blocks X's releases because the staging SLO gate fails. Fair?"

Listen for: dependency-aware attribution (tag errors by cause: own vs dependency, via the error
envelope `type` / span attributes); platform components need their own SLOs and budgets; the
release gate should ask "did *this change* make things worse?" (canary vs baseline), not "is
the budget empty?". Strong: notices a budget-gated release freeze can **block the fix** for the
very problem burning the budget.

### C6. Six hours inside the budget
> "With 99% over 28 days, a single 6-hour checkout outage leaves you 'within SLO'. Acceptable?"

No — monthly ratios hide incidents. Expect: multi-window, multi-burn-rate alerting (a 6-hour
outage at 100% error rate burns budget at ~100× and pages in minutes); plus a separate
**max-incident-duration** or "bad minutes in a row" objective for critical journeys. Strong:
"an SLO is a planning tool; it isn't the incident trigger".

### C7. Losing an AZ costs capacity, not just pods
> "An AZ goes down. 33% of capacity must come back within minutes — mostly Spot, in a region
> where every other customer is scrambling too. Is this part of your 99%? How do you know you
> have the headroom **without** failing an AZ?"

Listen for: headroom is a **continuously measured requirement** (N+1 per AZ for critical
journeys, on-demand floor for critical pools, PDBs, topology spread); verify by
simulation/what-if (scheduler dry-run against capacity minus one AZ), on-demand capacity
reservations for the critical tier, and occasional real AZ-evacuation drills. Insufficient
capacity errors (ICE) are a correlated failure — Spot percentages in SPEC-03 matter here.

### C8. Allocate the budget
> "You have ~7 hours a month. Allocate it: deployments, platform upgrades, dependency incidents,
> DNS failover, regional events, unknown."

Look for a table and humility. DNS failover alone: detection ~90 s + NS propagation (TTL-bound,
can be hours for resolvers that cache NS) + `MaxDailyFailovers = 1` → a second incident the same
day is manual. A regional RDS event ~1 h. Strong: keeps a large "unknown" reserve, and says what
they'd do when one category overspends (freeze that category, not everything).

### C9. How would you know you're at 99%?
> "Your dashboard says 99.3%. How confident are you that it isn't 98.5% or 99.8%?"

Listen for: measurement error — synthetic sample size, server-side vs edge, excluded "invalid"
requests, low-traffic journeys, clock windows, retries counted or not. Strong: states the
**measurement's own failure modes** and cross-checks two independent sources (edge logs vs
synthetics vs business events like orders settled per minute).

## Signals

**Strong**
- Defines the target by user journeys measured from outside.
- Does the arithmetic and then breaks its own independence assumption.
- Finds the shared-fate paths (monitoring-in-cluster, shared Postgres for DNS failover, shared RDS).
- Every detection signal is paired with its blind spot.
- Ranks changes by availability gained per effort, with numbers.

**Weak**
- Raises all SLOs to 99.99%.
- Treats 150 dashboards as 150 independent truths.
- Answers only with tools (Chaos Mesh! Thanos! more alerts!).

**Red flags**
- Averages service SLOs into a platform number.
- No external vantage point after C2.
- Accepts a 6-hour outage as "within budget" after C6.

## Scoring anchors

| Dimension | 1 | 4 |
|---|---|---|
| Framing | Takes "99%" literally | Defines journeys, vantage point, window and weighting before computing |
| Mechanism | Lists outages | Explains correlated failure and why the shared data plane dominates |
| Verifiability | Dashboards | External journeys + dead-man's switch + each signal's blind spot |
| Trade-offs | "More redundancy" | Cost-ranked levers; knows when a degraded mode beats a replica |
| Altitude | One service | Moves between a Redis timeout, a release gate and the monthly platform number |
