# Interviewer guide — Challenge 2: Prove It's the Cluster We Declared

> Do not share with candidates. Candidate brief: [`../candidate/02-provable-clusters.md`](../candidate/02-provable-clusters.md).

## 1. What this challenge measures

Whether the candidate can reason about **evidence**: what a check actually proves, how fresh
that proof is, who produced it, and how it could be wrong. It also tests whether they can say
something honest and useful to leadership instead of "100% is impossible" or "we'll add more
tests".

It sits on real gaps in this repo:

1. [SPEC-03 §8](../../../specs/SPEC-03-compute-clusters.md) is a hand-run checklist of
   `kubectl get` / `cilium status` lines, executed once after a rebuild.
2. Most of those lines assert that **configuration is present**, not that the **property holds**.
3. "Plan is clean" is accepted with `mock_outputs`, which can make policy pass on values that
   will never exist.
4. The diagram shows **Kyverno and Gatekeeper** (and ADR-0020 adds VAP): three admission
   engines and no stated authority.
5. Requirements live in prose ADRs. Nothing says which clusters a requirement applies to or how
   old its evidence may be.

## 2. The trap

"100% sure" invites one of two bad answers: **"impossible"** (and stop), or **"more tests"**
(without ever asking what a test proves). The honest promise is narrower and stronger:

> For every cluster and every declared requirement, we hold **fresh, independently produced
> evidence** that it held at time *t*, within a known maximum age. A cluster without that
> evidence is treated as non-compliant and loses the right to receive change.

The certainty moves from "the cluster is compliant", which is unknowable, to "we know exactly
what we've proven, when, and by whom", which is achievable. Watch for the candidate who makes
that move unprompted.

The second trap is **configuration vs behaviour vs capacity**:

| Kind | Example | What proves it |
|---|---|---|
| Configuration | "WireGuard is enabled" | Reading config (weakest) |
| Behaviour | "Node-to-node packets are encrypted" | Observing the property on every unit |
| Capacity | "Enough IPs to double the cluster" | Continuous measurement of headroom against a number |

## 3. Level calibration

| Level | What they produce unprompted |
|---|---|
| **Middle** | Automates SPEC-03 §8 in CI and adds OPA/checkov on plans. Doesn't separate config from behaviour, and doesn't think about drift. |
| **Senior** | Continuous conformance, behavioural checks, per-node evidence, drift. A different response per requirement. Asks "how do I know my checks work?" |
| **Staff** | Requirements as versioned data with scope and freshness. The verifier is outside the blast radius and signs its evidence. Compliance gates delivery. Scale and capacity requirements are proven progressively in prod. A real promise to leadership. |

## 4. Reference answer

### 4.1 The promise to leadership (three sentences)

> We can't promise a cluster never deviates from its requirements. We can promise that every
> deviation is detected within a stated time per requirement, by a verifier the cluster can't
> influence, and that a cluster without current evidence can't receive changes. We'll report
> compliance per requirement, including how old each piece of evidence is, never as a single
> percentage.

### 4.2 A requirement as data

```yaml
id: R3-node-transit-encryption
version: 2
statement: Pod-to-pod traffic between nodes is encrypted in transit.
kind: behaviour            # configuration | behaviour | capacity
scope:
  families: [eks-workload, eks-gpu, baremetal-talos]   # GKE: separate requirement R3-gke
evidence:
  eks-workload:
    adapter: cilium-per-node-encryption-status   # per node, cardinality = node count
    corroboration: hubble-plaintext-flow-sample  # behavioural spot check
  baremetal-talos:
    adapter: cilium-per-node-encryption-status
maxEvidenceAge: 15m
triggers: [node-join, cilium-config-change, cilium-upgrade]
onFail:
  prod: { page: security-oncall, blockPromotion: true }
  nonprod: { ticket: platform, blockPromotion: true }
exceptions: []             # each: owner, reason, expiry; expired = fail
source: SPEC-03 §2.2
```

The ADRs remain the *why*; the requirement file is the *what*, the same pattern as
`platform-contracts/` (versioned, digested, indexed).

### 4.3 The verification pipeline

```
  declare            pre-apply             apply           post-apply            continuous                 retire
 ─────────►  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐  ┌────────────────────────┐
 requirement │ static policy on │  │ plan with    │  │ behavioural      │  │ scheduled + event-     │
 files (git) │ plan JSON        │─►│ REAL outputs │─►│ conformance      │─►│ driven re-verification │──► evidence
             │ (OPA / checkov)  │  │ (no mocks    │  │ (deny-tests,     │  │ max age per req        │    store
             └──────────────────┘  │ in policy)   │  │ probes, per-node)│  └───────────┬────────────┘    (signed,
                                   └──────────────┘  └──────────────────┘              │                 immutable)
                                                                               fail ──► gate: Kargo/Argo
                                                                                        refuse promotion
  + nightly: run the whole suite against a KNOWN-BAD canary cluster → must fail exactly the planted violations
```

What each stage can and can't prove:

| Stage | Proves | Cannot prove |
|---|---|---|
| Static policy on plan | The *intent* violates nothing we can express statically | Mocked values, chart defaults, AWS-managed defaults, drift |
| Plan with real outputs | The delta we're about to make | Anything IaC doesn't manage (console changes, controllers) |
| Post-apply behavioural | The property held right after creation | That it still holds tomorrow |
| Continuous | The property holds now, within max age | Anything between two samples (bounded by triggers) |
| Known-bad canary | That checks aren't vacuous | — |

### 4.4 Evidence matrix R1–R8

| Req | Strongest evidence | How it could lie | How to detect the lie |
|---|---|---|---|
| R1 private endpoint | **External** probe from a non-allow-listed vantage point fails, plus an AWS API read of `endpointPublicAccess` and CIDRs | API read is config only; a probe from an allow-listed IP gives a false pass | Probe from several known-not-allowed points; the two sources must agree |
| R2 Cilium only | No `aws-node` DaemonSet, no `vpc-cni` add-on, **every** pod IP allocated by Cilium IPAM | Add-on re-added via console or EKS default during upgrade | EKS add-on list via API in the continuous loop; IPAM audit per node |
| R3 encryption | Per-node encryption status for **every** node (count = node count), plus a sampled behavioural check that no plaintext pod-to-pod flows cross nodes | Cluster-wide flag ≠ every node; excluded CIDRs; agent fallback on one node | Cardinality check; trigger on node join |
| R4 immutable OS | Per node: OS image and AMI ID matched against an allow-list, **read from the cloud API**, not from the node | Node-reported fields can be spoofed by whoever controls the node | Cross-check the cloud API against node self-report |
| R5 default-deny | **Behavioural**: a probe pod in a fresh namespace can't reach a canary service, and *can* reach DNS and the apiserver | The policy object exists but a higher-priority allow-all shadows it | The probe is the evidence, not the object |
| R6 signed images | Admission **denies an unsigned test image** (attempted on purpose), plus an inventory of *running* digests verified against signatures | Policy in Audit mode; excluded namespaces; webhook `failurePolicy: Ignore`; images admitted before the policy existed | Periodic deny-test; running-inventory scan |
| R7 Pod Identity | SA inventory: none with both an IRSA annotation and an association; IRSA only on the versioned exception list | "Bootstrap only" IRSA grows quietly | Exception list with owner and expiry; anything outside it fails |
| R8 no creator admin | Access-entry listing via the EKS API from **outside**, plus SubjectAccessReview for known principals | Break-glass entries added during an incident are never removed | Break-glass entries carry an expiry; expired = non-compliant |

### 4.5 Response matrix at 03:00 on a prod cluster

| Req | Response | Why |
|---|---|---|
| R1 endpoint public | Page security + block promotions | Active exposure |
| R2 vpc-cni present | Block promotions, page platform in working hours | Breaks networking assumptions; no immediate exposure |
| R3 plaintext node | Page + cordon **that node only** | Exposure, limited to one unit; cordoning one node is cheap |
| R4 unknown AMI | Block promotions, ticket; Karpenter drift replaces it | Not urgent if the AMI is a newer official build |
| R5 default-deny broken | Page security + block promotions | Lateral-movement exposure |
| R6 unsigned image running | Page + block promotions; **don't** auto-kill pods | Killing prod pods at 03:00 can cause the outage you're avoiding |
| R7 dual identity SA | Ticket + block promotions | Low immediate risk |
| R8 expired break-glass | Auto-remediate (remove entry) with audit log | Safe, reversible, well-scoped |

Principle: **blocking change is the universal safe lever.** Auto-remediation is allowed only
where the fix is reversible and has a smaller blast radius than the problem.

## 5. Curveballs — play one at a time

### C1. What did the plan prove?

> "`terragrunt stack plan` is clean, with `mock_outputs` for dependencies. Name two of R1–R8 that
> a clean plan can **never** prove, and one it can."

**Walkthrough**
- Can never prove: R3 (runtime, per node), R5 (behavioural), R6 for images that are already
  running, R2 if an EKS default re-adds an add-on, anything set by Helm chart defaults outside
  Terraform.
- Can prove (intent only): R1's CIDR list isn't `0.0.0.0/0`, **if** that value isn't mocked.
- The sharp point: a mock can make policy pass on a value reality will never have. So policy
  must run on plans with **real** dependency outputs, or mocks must be policy-valid by
  construction (lint the mocks).

**Probe:** "Then why run plan-time policy at all?" Because it's the cheapest place to stop
*intent* violations, which are most of them. It is just not evidence about the running cluster.

### C2. The node that didn't get the memo

> "`cilium status` says Encryption: Wireguard. One node joined from an older AMI and its agent
> runs with encryption off. Does your R3 check catch it? Generalise the lesson."

**Walkthrough**
- A config assertion samples the **control plane's belief**. The property lives on **every
  node and every packet**.
- Evidence must be **per unit with a cardinality check**: 300 nodes means 300 pieces of
  evidence. Evidence from 299 of 300 nodes is a fail, not 99.7%.
- Timing matters. With ~8% node churn per day, a 300-node cluster gets ~24 new nodes a day.
  Random sampling of *k* nodes per hour would take a long time to land on the one bad node
  (probability *k*/300 per hour). **Trigger on node join** instead.

**Probe:** "Packet capture on every node is expensive. What's your cheaper corroboration?"
Hubble flow sampling for unencrypted pod-to-pod flows across nodes; per-node status from the
agent; and a periodic cross-node probe pair.

### C3. Six months of green

> "Your conformance suite has passed on every cluster for six months. Good news or bad news?"

**Walkthrough**
- Best answer: "Unknown, and that's the problem." A check that has never failed may be vacuous:
  a wrong label selector, an always-true query, or an error treated as skip.
- Fix: **mutation testing for infrastructure.** Keep a permanent known-bad canary cluster (or
  namespace) with planted violations, one per requirement. The suite must report exactly those.
- Checks that **error out count as failures**, never skips.

**Red flag:** "Good, it means we're compliant."

### C4. Day 40

> "Day 0 everything passes. By day 40: break-glass was used three times from the console, the
> `EC2NodeClass` AMI alias rolled to a new Bottlerocket release, and an Argo-synced chart bump
> changed a default. Design for this."

**Walkthrough**
- Day-0 evidence is worthless by day 40. Every requirement needs a **max evidence age** and
  **event triggers**.
- The AMI roll is gradual: at ~8% churn per day, about 0.92^d of nodes are still old after
  *d* days. Half the fleet turns over in ~8 days. A new AMI therefore **spreads silently** unless
  node join triggers R4.
- Chart bumps change defaults that nobody wrote in git. Evidence must come from the **running
  state**, not from the values file.
- Break-glass from the console: an R8 entry with no expiry. The process fix is break-glass
  through a tool that stamps an expiry; the check fix is "unknown or expired entry = fail".

### C5. Three admission engines

> "Kyverno, Gatekeeper and VAP are all installed. A pod is admitted by one and flagged by
> another's audit. Which is the source of truth for R6? How do you prove the policy set on a
> cluster is the one you declared?"

**Walkthrough**
- Three engines means three truths. Pick **one authority per requirement** (ADR-0020 names
  Kyverno + VAP), and make the others non-authoritative or remove them.
- Proof is twofold: (a) the policy bundle digest is part of the cluster's evidence;
  (b) a **deny-test**: actually submit a violating object and watch it be refused. The presence
  of a CR proves nothing.
- The sharpest point: a webhook with `failurePolicy: Ignore` **fails open**. If the engine is
  down, the requirement silently disappears. Strong candidates ask about this unprompted, and
  about namespace exclusions.

**Probe:** "Why not fail closed everywhere?" Then an admission engine outage blocks *all*
deploys, including the fix for it. The trade-off: fail closed for prod workload namespaces,
with a documented break-glass path.

### C6. One requirement, three worlds

> "R4 'immutable OS' means Bottlerocket on EKS, Talos on bare metal, COS on GKE. How do you keep
> one requirement with three evidence methods, without someone marking it 'N/A' to pass?"

**Walkthrough**
- Stable requirement ID; one **evidence adapter** per family; **scope declared in the
  requirement**, not chosen by the cluster.
- "N/A" exists only as a **versioned exception** with an owner, a reason and an expiry.
- Evidence from **outside** the node is stronger than self-report: the EC2 API for the AMI, the
  Talos machine-config API, the GKE node-pool API.

### C7. Who watches the watcher?

> "Your conformance job runs inside the cluster as cluster-admin. Problems?"

**Walkthrough**
- A compromised or misconfigured cluster can lie to an in-cluster verifier.
- A cluster-admin verifier is itself a violation of R8 and of least privilege. The brief says
  nothing may have cluster-admin in prod.
- Better: the verifier runs **outside** (management plane), reads cloud APIs, uses a narrow
  read-only identity, and **signs** results with a key the cluster can't reach. That is the
  [ADR-0059](../../adrs/0059-independent-observer-attestor-profiles.md) pattern (KMS-held
  Ed25519, separate identity, bounded validity).
- Deep follow-up: "Can you prove nobody else has cluster-admin from a principal that doesn't
  have it?" Yes: list RBAC bindings and run SubjectAccessReview for known principals. But reading
  RBAC is itself a sensitive grant. Watch how they bound it (read-only on RBAC kinds only,
  no Secrets).

### C8. It passed in staging

> "1.34 → 1.35 passed conformance in dev and staging. The prod GPU cluster at 4 800 nodes fails:
> pods stuck in `ContainerCreating`. Which requirements depend on scale, and how do you verify
> them before prod?"

**Walkthrough**
- Scale-dependent: IP addresses (ENI IPAM), apiserver/etcd load, Cilium identity count,
  Karpenter launch rate, EC2 capacity (ICE), DNS QPS.
- Run the arithmetic on IPs: 4 800 nodes × ~30 pods ≈ 144 000 IPs, more than a `/16` (65 536).
  You don't need 4 800 staging nodes to see that. You need **capacity requirements with
  numbers** ("IP headroom ≥ 20% of max cluster size"), checked continuously from subnet free-IP
  counts.
- Staging isn't a small prod; it's a different system. Some requirements are proven **in prod,
  progressively**: upgrade one node pool, verify, continue, with a stop condition.

### C9. One number for leadership (staff-level)

> "Leadership wants a single number on a slide: 'fleet compliance %'. Give it to them?"

**Walkthrough**
- A scalar hides what matters. 99.5% compliance can mean one prod cluster with a public API
  endpoint.
- Report a **vector**: per requirement and severity, with **zero tolerance on critical**, plus
  evidence age. If a single number is unavoidable: "clusters with zero critical failures and all
  evidence fresh", as a count, not a percentage.

## 6. If the candidate is stuck

1. "What exactly does `cilium status` tell you, and about which nodes?"
2. "If a requirement held yesterday, what could make it false today without anyone running Terraform?"
3. "Who runs your check, with which permissions, and could the cluster influence its result?"
4. "How would you know a check of yours is broken?"

## 7. Signals

**Strong**
- Rewrites "100% sure" into "complete, fresh, independent evidence, or the cluster can't
  receive change".
- Distinguishes configuration, behaviour and capacity requirements.
- Demands evidence cardinality (every node, every namespace) and freshness.
- Tests the tests (known-bad canary) and treats errors as failures.
- Puts the verifier outside the blast radius, with less privilege than what it verifies.

**Weak**
- "Run the acceptance checklist in CI": automates the same config assertions.
- Equates "policy installed" with "policy enforced".
- One response for every failure.

**Red flags**
- "100% is impossible" and stops there.
- Keeps an in-cluster cluster-admin verifier after C7.
- Six months of green = compliant.

## 8. Scoring anchors

| Dimension | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Framing | Accepts or rejects "100%" | Says "we can't be sure" with caveats | Converts it into evidence + freshness | Signed promise to leadership + compliance gates delivery |
| Mechanism | "We check it" | Lists checks | Explains why config ≠ property and per-node evidence matters | Adds churn, drift and scale arithmetic |
| Verifiability | Checks without proof they work | Some behavioural checks | Cardinality, freshness, error = fail | Plus a known-bad canary and an independent signed verifier |
| Trade-offs | Same response everywhere | Different severity labels | Response per requirement | Aware of remediation blast radius and fail-open/fail-closed costs |
| Altitude | One cluster | One family | Fleet of four families | Plus upgrade waves, scale requirements, reporting to leadership |
