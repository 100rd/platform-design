# Interviewer guide — Challenge 3: Ninety-Nine Percent of What?

> Do not share with candidates. Candidate brief: [`../candidate/03-ninety-nine-percent.md`](../candidate/03-ninety-nine-percent.md).

## 1. What this challenge measures

Whether the candidate can turn a vague target into a measurable one, **compose** reliability
across many services and shared dependencies, notice where the composition assumptions break
(correlation, shared fate), and **rank** improvements by evidence rather than instinct.

It sits on real properties of this repo:

1. Pyrra SLOs are per service ([SPEC-07 §4.8](../../../specs/SPEC-07-observability.md)). No
   journey-level SLI exists.
2. Global Accelerator health checks are **TCP/443**. SPEC-08 §5.2 itself lists "app-level
   degradation (5xx, healthy TCP)" as **manual**.
3. The observability stack runs **inside** the clusters it watches.
4. `failover-controller` and `dns-monitor` share **one PostgreSQL**, and the health score's
   `consistency` term is a hard-coded `1.0` placeholder.
5. RDS has **no cross-region replica**. A regional loss means a ~1 h snapshot restore.

## 2. The trap

"99% working" sounds like a low bar. It is also undefined. Typical first answers:

- **Average the 150 SLOs.** Meaningless; nobody experiences an average.
- **Multiply them**: 0.999¹⁵⁰ ≈ 0.861, so "impossible". But no request touches all 150
  services, and services fail in **correlated** ways, so independence is wrong in both directions.

The answer is built from **user journeys**: a few critical paths, each with its own dependency
set, measured **from outside**, composed with **shared dependencies counted once**, because the
shared data plane dominates.

The second, subtler trap is in the brief's incident table. Run the numbers and the platform is
already at **~99.95% on average**. "99%" is not too ambitious; it's **too lax** for checkout
(7.2 h a month!) while still saying nothing about the **worst month** or the **longest
incident**. A strong candidate discovers this and pushes back on the target itself.

## 3. Level calibration

| Level | What they produce unprompted |
|---|---|
| **Middle** | Knows SLI/SLO/error budget vocabulary, does the 0.999ⁿ arithmetic, proposes better alerting. |
| **Senior** | Journey SLIs at the edge, external probes, burn-rate alerts. Finds the shared-fate paths (monitoring in-cluster, shared DNS-failover DB). Uses the incident table to compute real availability. |
| **Staff** | Challenges the target itself (too lax on average, silent on the tail). Separates target composition from observed availability. Ranks levers by minutes saved per effort. Designs dependency-aware budgets and release gates that can't block their own fix. |

## 4. Worked numbers

### 4.1 Budget table

| Target | per 30 days | per 28 days |
|---|---|---|
| 99% | 7.2 h | 6.72 h |
| 99.5% | 3.6 h | 3.36 h |
| 99.9% | 43.2 min | 40.3 min |
| 99.95% | 21.6 min | 20.2 min |

### 4.2 Composing the **targets**: what the SLOs promise

Assume shared-component targets: RDS 99.95%, Redis 99.9%, RabbitMQ 99.9%, edge + GA + DNS
99.99%. Assume independence for now.

- Checkout: 11 services at 99.9% × shared deps
  = 0.999¹¹ × 0.9995 × 0.999 × 0.999 × 0.9999 ≈ **98.65%**. That's **below 99%**.
- To reach 99% with those shared deps, the 11 checkout-path services would each need
  ≈ **99.93%**, not 99.9%.
- Login: 0.999⁴ × 0.9995 × 0.999 ≈ 99.45%.

The conclusion is not "the platform is at 98.65%". It is: **the per-service SLOs are
inconsistent with the platform target.** If every service spent its budget, checkout would miss
99%. Targets are budgets, not predictions.

### 4.3 Composing the **observations**: what actually happened (from the brief)

Bad minutes for checkout, weighted by the share of requests failing:

| Incident class | Per year | Bad min / year |
|---|---|---|
| Bad deploys: 36 × 10 min × 30% | 36 | **108** |
| Region 5xx with healthy TCP: 4 × 35 min × 50% | 4 | **70** |
| RabbitMQ partition: 2 × 25 min × 100% (sync publish) | 2 | **50** |
| Redis eviction storm: 1 × 50 min × 40% | 1 | **20** |
| DNS provider failover: ~15 min (tail unknown) | 1 | **~15** |
| RDS Multi-AZ failover: 4 × 1 min | 4 | **4** |
| **Total** | | **≈ 267 min / year ≈ 22 min / month ≈ 99.95%** |

Worst plausible month (one of each big event plus the usual deploys): 9 + 25 + 20 + 17.5 + 15 +
1 ≈ **88 min ≈ 99.80%**.

What this tells you:
- 99% is met **every month** by a wide margin. As a target it constrains nothing.
- 99.9% is met **on average** but **not in the worst month**.
- The dominant controllable term is **bad deploys** (108), then the **TCP-only health check**
  (70), then **synchronous RabbitMQ publish** (50).
- The regional RDS loss **never happened** in the sample, yet it would cost ~60 min in one go.
  That's a **tail risk**, invisible in a 12-month average. Strong candidates name the tension
  between "rank by observed minutes" and "rank by tail".
- Caveat: these numbers come from **server-side** incident records. DNS tails, client timeouts
  and anything the TCP health check hides are under-counted. The measurement itself is a
  finding (C9).

### 4.4 Ranking the levers (example)

| Lever | Estimated minutes saved per year | Effort | Notes |
|---|---|---|---|
| Canary auto-rollback on journey burn rate (detect in ~2 min instead of ~10) | ~85 of 108 | Low/medium; Argo Rollouts analysis already exists | Largest and cheapest |
| Journey-level HTTP health driving the GA traffic dial automatically (35 min → ~3 min) | ~64 of 70 | Medium | Turns a manual SPEC-08 row into an automated one |
| Transactional outbox in `orders` (RabbitMQ off the sync path) | ~50 of 50 for checkout | Medium; one team | Settlement is delayed instead of checkout failing |
| Redis degraded mode for login/checkout | ~15 of 20 | Medium; several teams | Needs the soft-dependency contract from Challenge 1 |
| RDS cross-region replica | 0 observed, ~60 tail per event | High | Justified by tail risk and regulatory needs, not by the average |

## 5. Reference answer (shape)

**SLI.** "Share of valid journey attempts that complete correctly (business outcome reached)
within the latency threshold, measured at the edge and by external synthetic probes, per
critical journey." The platform figure is the **worst critical journey** (or revenue-weighted),
not an average of services.

**SLO.** Per journey: e.g. checkout 99.9% over 28 days, **and** no single incident longer than
30 minutes, **and** at most N bad 5-minute windows per month. Login 99.95%. Settlement is
measured as **freshness** ("99% of payouts settled within 15 min"), not availability.

**Detection.** External synthetic journeys from outside AWS and both regions. Edge-level
journey SLIs. Multi-window burn-rate alerts. A dead-man's switch from in-cluster Alertmanager to
an external receiver. Each signal is paired with what it can't see.

**Top three changes.** Argued from §4.4, with the tail-risk caveat.

## 6. Curveballs — play one at a time

### C1. Everything is green

> "All 150 Pyrra dashboards are green. Customers can't check out. Give me at least four
> mechanisms in *this* architecture that make that possible, then the signal that would have
> caught it."

Expect four or more:
- GA health is **TCP/443**: a region serving 500s stays in rotation (SPEC-08 §5.2).
- SLIs are **server-side**: requests that never arrive (DNS, edge, TLS, client timeouts) aren't
  counted.
- Errors are returned as **200 with an error body**.
- The failure is **async**: orders are accepted, RabbitMQ backlog grows, settlement never
  happens. No request errors.
- **Low-traffic** services: small denominators, or the failing step has no SLO at all.
- A **soft dependency silently degrades** the result (stale prices from Redis): "successful" but
  wrong.
- **Edge retries** hide errors from the user-facing SLI while burning backends.
- Each service is within its own budget, but the **combination** is not (§4.2).

Signal: an **end-to-end journey probe** from outside that asserts the business outcome (order
settled), plus edge-level journey SLIs.

**Probe:** "Your synthetic probe places real orders. Problems?" Test merchants and accounts,
excluding them from revenue, not tripping fraud scoring, the cost of probes, and the probe as a
dependency that can itself fail and page falsely.

### C2. Who tells PagerDuty?

> "The observability stack runs inside the workload clusters. The region goes dark. Who pages?
> Now look at DNS failover: `failover-controller` and `dns-monitor` share one Postgres. What
> does that do?"

**Walkthrough**
- Shared fate: the monitor dies with what it monitors. Fixes: a **dead-man's switch** (an
  always-firing alert to an external service that pages on **absence**), and **external
  probes** in a different provider.
- DNS failover: detector and actuator share a database, so a Postgres outage blinds both.
  SPEC-08 lists this as manual. The independence of a guard must be **designed and tested**.
- Bonus: the health score's `consistency` term is a hard-coded `1.0`, so 10% of the score is
  fiction. Ask: "what does that do to the threshold at 0.5?" It shifts it. A provider with a
  0.45 real score reads as 0.55 and stays "healthy".
- Bonus: `MaxDailyFailovers = 1` means a second DNS incident the same day is manual.

**Probe:** "Your external probe runs in another cloud. What does it share with you?" DNS, the
registrar, the certificate authority, the probe vendor's own availability. Independence is never
total. Name what's shared.

### C3. Soft or hard?

> "Teams swear Redis is a soft dependency for 120 of the 150 services. The Redis eviction storm
> in the brief failed 40% of login and checkout. How do you find out the truth before the next
> incident?"

**Walkthrough**
- The incident already **falsified** the claim for at least login and checkout. Start there.
- Controlled fault injection with: a **hypothesis** ("checkout returns 2xx with the degraded
  marker when Redis is unreachable"), a **blast radius** (one AZ, 1% of traffic, one journey),
  an **abort condition** tied to journey burn rate, and a **result that changes something**
  (fix it, or reclassify it as hard).
- Progression: previews (Challenge 1's fault conditions) → staging → prod with traffic limits.

**Red flag:** "Switch off Redis in prod on Friday and see."

### C4. The independence lie

> "Your math assumed independent failures. 40 services share one RDS cluster, and every journey
> touches RabbitMQ. Redo the reasoning. What's the dominant term, and what's the cheapest change
> that moves the number most?"

**Walkthrough**
- Shared components act as **one** serial dependency for every journey that touches them, with
  **correlated** failure. When RDS is down, checkout *and* login *and* settlement fail together.
  Treating 40 RDS-backed services as 40 independent 99.9% terms over-counts small failures and
  under-counts the big one.
- The platform floor is therefore set by RDS, RabbitMQ, the edge and DNS, not by the long tail of
  services.
- Cheapest lever: usually make the shared dependency **soft for the critical journey** (outbox,
  degraded reads, cache) rather than raise 150 SLOs. §4.3 shows RabbitMQ's 50 min/year disappear
  for checkout with an outbox.
- Period matters: one regional RDS event a year at ~1 h ≈ 99.99% annualised, but ≈ 99.86% in
  *that* month, already over a 99.95% monthly budget from one event.

### C5. Whose budget is it?

> "Service X burned its error budget. 80% of its errors were Redis timeouts, a platform
> component. Kargo now blocks X's releases because the staging SLO gate fails. Fair?"

**Walkthrough**
- **Dependency-aware attribution**: tag each error with its cause, own or dependency (the
  `dependency` field in the Challenge 1 error envelope, or span attributes). Platform components
  need their **own** SLOs and budgets.
- The release gate should ask "did **this change** make things worse?" (canary vs baseline),
  not "is the budget empty?".
- Sharpest point: a budget-based freeze can **block the fix** for the very problem burning the
  budget. Strong candidates notice it unprompted.

### C6. Six hours inside the budget

> "With 99% over 28 days, a single 6-hour checkout outage leaves you 'within SLO'. Acceptable?"

**Walkthrough**
- No. A monthly ratio hides incidents.
- Multi-window, multi-burn-rate alerting: a full outage burns a 99% budget at 100× and pages
  within minutes, whatever the remaining budget.
- Add an explicit objective on **incident duration** or **bad windows in a row** for critical
  journeys.
- "An SLO is a planning tool, not the incident trigger."

### C7. Losing an AZ costs capacity, not just pods

> "An AZ goes down. A third of capacity must come back within minutes, mostly Spot, in a region
> where everyone else is scrambling too. Is that inside your 99%? How do you know you have the
> headroom **without** failing an AZ?"

**Walkthrough**
- Headroom is a **continuously measured requirement**: N+1 per AZ for critical journeys, an
  on-demand floor for critical pools, PDBs, topology spread.
- Verify without failure: a scheduler what-if (current requests against capacity minus one AZ),
  on-demand capacity reservations for the critical tier, and occasional real AZ-evacuation drills.
- Insufficient-capacity errors (ICE) are a **correlated** failure. Spot percentages in SPEC-03
  matter here: a 50% Spot pool losing an AZ during a regional capacity crunch can't come back.

### C8. Allocate the budget

> "Pick a target per journey. Then allocate that month's budget across deploys, platform
> upgrades, dependency incidents, DNS failover, regional events and 'unknown'."

Look for a table built from the incident data (§4.3) and some humility. Example for checkout at
99.9% (≈ 43 min / 30 days):

| Consumer | Allocation | Basis |
|---|---|---|
| Deploys | 10 min | Today 9 min/month; must fall after canary auto-rollback |
| Shared dependencies (RDS/Redis/RabbitMQ) | 8 min | Observed ~6 min/month average |
| Region-level (5xx with healthy TCP) | 6 min | Observed ~6 min/month; falls after automation |
| DNS | 2 min | ~1.25 min/month average, unknown tail |
| Platform upgrades | 5 min | Planned |
| **Unknown** | **12 min** | The thing you didn't predict |

Strong: says what happens when one category overspends (freeze **that** category, e.g. only
risky deploys, not everything).

### C9. How would you know you're at 99%?

> "Your dashboard says 99.3%. How sure are you it isn't 98.5% or 99.8%?"

**Walkthrough**
- Sources of measurement error: synthetic sample size; server-side vs edge; "invalid" requests
  excluded; low-traffic journeys; window boundaries; whether retries count; incidents where
  telemetry itself was down (blind minutes count as what?).
- Cross-check **independent sources**: edge logs vs synthetics vs **business events** (orders
  settled per minute against a seasonal baseline). Business events are the hardest signal to
  fool.
- Strong: states that **blind minutes count as bad**, not as missing.

## 7. If the candidate is stuck

1. "Which customer action matters most here? Trace it through the system."
2. "Which components does every journey touch?"
3. "Take the incident table. How many bad minutes did checkout have last year?"
4. "If the monitoring itself is down, what does your SLI say?"

## 8. Signals

**Strong**
- Defines the target by user journeys measured from outside.
- Does the arithmetic, then breaks its own independence assumption.
- Separates **target composition** (98.65%) from **observed availability** (99.95%) and explains
  why both matter.
- Finds the shared-fate paths (monitoring in-cluster, shared Postgres for DNS failover, shared RDS).
- Every detection signal is paired with its blind spot.
- Ranks changes by minutes saved per effort, and names the tail-risk exception.

**Weak**
- Raises all SLOs to 99.99%.
- Treats 150 dashboards as 150 independent truths.
- Answers only with tools (Chaos Mesh! Thanos! more alerts!).
- Never uses the incident table.

**Red flags**
- Averages service SLOs into a platform number.
- No external vantage point after C2.
- Accepts a 6-hour outage as "within budget" after C6.

## 9. Scoring anchors

| Dimension | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Framing | Takes "99%" literally | Asks "of what?" | Defines journeys, vantage point, window | Pushes back: too lax on average, silent on the tail |
| Mechanism | Lists outages | Multiplies availabilities | Explains correlated failure and shared deps | Separates target composition from observed availability with numbers |
| Verifiability | Dashboards | Burn-rate alerts | External journeys + dead-man's switch + blind spots | Plus measurement error and business-event cross-checks |
| Trade-offs | "More redundancy" | Lists options | Ranks levers by gain | Ranks by minutes saved per effort *and* handles tail risk |
| Altitude | One service | One journey | Platform figure from journeys | Plus budgets, release gates and leadership's target |
