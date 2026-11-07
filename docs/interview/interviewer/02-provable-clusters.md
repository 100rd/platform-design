# Interviewer guide — Challenge 2: Prove It's the Cluster We Declared

> Do not share with candidates. Candidate brief: [`../candidate/02-provable-clusters.md`](../candidate/02-provable-clusters.md).

## The trap

"100% sure" invites one of two bad answers: **"impossible"** (and stop), or **"more tests"**
(and never ask what a test proves). The honest promise is narrower and stronger:

> For every cluster, for every declared requirement, we hold **fresh, independently produced
> evidence** that it held at time *t*, with a known maximum staleness — and a cluster without
> that evidence is treated as non-compliant and loses the right to receive changes.

Certainty moves from "the cluster is compliant" (unknowable) to "we know exactly what we have
proven, when, and how" (achievable). Watch for the candidate who makes that move unprompted.

The second trap is the **configuration vs. behaviour** gap: most of SPEC-03 §8 asserts that
config is *present* (`cilium status` says WireGuard), not that the *property* holds (packets
on the wire are encrypted).

## Reference shape of a strong answer

**Requirement as data.** Each requirement is an ID + a property + a scope (which cluster
families) + one or more **evidence adapters** per family + max evidence age + response policy.
Same idea as `platform-contracts/` (versioned, digested, indexed). Prose ADRs point to IDs.

**Verification stages.**

| Stage | Proves | Cannot prove |
|---|---|---|
| Static (IaC policy, OPA/checkov on `plan -json`) | The *intent* violates nothing we can express statically | Anything about mocked values, runtime defaults, chart defaults, or drift |
| Plan with real dependency outputs | The delta we're about to make | What's already there that IaC doesn't manage |
| Post-apply conformance (behavioural) | The property held right after creation | That it still holds tomorrow |
| Continuous conformance (scheduled + event-driven) | The property holds now, ± max age | Anything between two samples |
| Canary violation ("known-bad" cluster or injected violations) | The checks are not vacuous | — |

**Evidence matrix (sketch).**

| Req | Strongest evidence | How it could lie | Detect the lie |
|---|---|---|---|
| R1 private endpoint | **External** probe from the internet fails to reach the endpoint + AWS API read of `endpointPublicAccess`/CIDRs | API read is config; a probe from an allow-listed IP gives false pass | Probe from known-not-allowed vantage points; compare both sources |
| R2 Cilium only | No `aws-node` DS, no `vpc-cni` add-on, **every** pod IP assigned by Cilium IPAM | Add-on re-added by console/managed defaults | EKS add-on list in continuous check; node-level IPAM audit |
| R3 encryption | **Behavioural**: capture between two nodes (or Cilium/Hubble per-node encryption status for *every* node) shows WireGuard UDP only | Cluster-wide flag ≠ every node; a node with agent fallback or excluded CIDR sends plaintext | Per-node evidence, count must equal node count; periodic packet sample |
| R4 immutable OS | Node `osImage` + AMI ID matched against an allow-list, per node | Label/field spoofable by whoever controls the node; Talos/COS need different evidence | Cross-check with cloud API (instance AMI) — evidence from outside the node |
| R5 default-deny | **Behavioural**: a probe pod in a fresh namespace cannot reach a canary service; *can* reach DNS + apiserver | Policy object exists but is shadowed by an allow-all with higher priority | The probe, not the object, is the evidence |
| R6 signed images | Admission denies an **unsigned test image** (attempted on purpose) + inventory of running image digests verified against signatures | Policy in `Audit` mode; namespace excluded; images admitted before the policy | Periodic deny-test; inventory scan of what's *running*, not only what's *admitted* |
| R7 Pod Identity | Inventory of SAs: none with IRSA annotation **and** association; workload gets creds from Pod Identity agent | IRSA kept "for bootstrap" grows silently | Exception list is versioned; anything outside it fails |
| R8 no creator admin | IAM/EKS access-entry listing from **outside** the cluster; SubjectAccessReview for known principals | Break-glass entries added in an incident never removed | Break-glass entries carry expiry; expired = non-compliant |

## Curveballs — play one at a time

### C1. What did the plan prove?
> "`terragrunt stack plan` is clean, using `mock_outputs` for dependencies. Name two
> requirements from R1–R8 a clean plan can **never** prove, and one it can."

Can never prove: R3 (runtime per node), R5 (behavioural), R6 for images admitted earlier,
anything set by Helm chart defaults or EKS-managed defaults. Can prove (intent only): R1 CIDR
list isn't `0.0.0.0/0` — *if* the value isn't mocked. Strong: points out that mocks can make a
plan pass with values that would fail policy in reality → policy must run on plans with real
outputs, or mocks must be policy-valid by construction.

### C2. The node that didn't get the memo
> "`cilium status` says Encryption: Wireguard. A node joined from an older AMI and its agent
> runs with encryption disabled. Does your R3 check catch it? Generalise."

Listen for: config assertions sample the *control plane's belief*; properties live on *each
node / each packet*. Generalisation: evidence must be **per-unit with a cardinality check**
(evidence count = node count) and as close to the property as possible. Strong: "an evidence
set that covers 199 of 200 nodes is a fail, not 99.5%".

### C3. Six months of green
> "Your conformance suite has passed on every cluster for six months. Good or bad?"

The best answer: "Unknown — and that's the problem." A check that has never failed may be
vacuous (wrong selector, always-true query, skipped on error). Fix: **mutation testing for
infrastructure** — a permanent canary cluster (or namespace) with deliberately injected
violations, and the suite must report exactly those as failures. Also: checks that error out
must count as fail, not skip. Red flag: "good, it means we're compliant".

### C4. Day 40
> "Day 0 everything passes. By day 40: a break-glass access entry was added from the console,
> `EC2NodeClass` uses an AMI alias that auto-rolls, and a Helm chart bump changed a default.
> Design for this — and then: it's 03:00, a **prod** cluster fails R3. What happens?"

Listen for: continuous verification with max evidence age per requirement; event-driven
re-checks (node join, add-on change, chart sync). The 03:00 question tests judgment: the
response is **per requirement**, e.g.
- R3/R1 failing (exposure) → page + block promotions to that cluster;
- R6 inventory drift → block deploys, ticket;
- R8 expired break-glass → auto-remediate (remove entry) with audit;
- never auto-"remediate" by cordoning half the fleet at 03:00 — remediation has its own blast radius.
Strong: "blocking deploys" is the universal safe lever — a non-compliant cluster loses the right
to receive change (Kargo/Argo gate on evidence freshness).

### C5. Two policy engines
> "The diagram shows both **Kyverno** and **Gatekeeper**, plus VAP. A pod is admitted by one
> and flagged by the other's audit. Which one is the source of truth for R6, and how do you
> prove the policy set on a cluster is the one you declared?"

Listen for: two engines = two truths; pick one authority per requirement (ADR-0020 lists
Kyverno + VAP), the other is either removed or explicitly non-authoritative. Proof: policy
bundle digest is part of the cluster's evidence; the **deny-test** (C3-style) is the real proof
the engine enforces, not the presence of the CR. Strong: asks whether either engine is in
`Audit`/`failurePolicy: Ignore` — a webhook that fails open is a requirement that silently
disappears when the engine is down.

### C6. One requirement, three worlds
> "R4 'immutable OS' on EKS is Bottlerocket, on bare metal Talos, on GKE COS. How do you keep
> one requirement with three evidence methods without someone marking it 'N/A' to pass?"

Listen for: requirement ID stable; evidence adapters per family; **scope is declared in the
requirement**, not chosen by the cluster; "N/A" only via a versioned, owned, expiring
exception. Strong: notices evidence from *outside* the node (cloud API, Talos machine
config API, GKE node pool API) is stronger than node self-report.

### C7. Who watches the watcher?
> "Your conformance job runs inside the cluster as cluster-admin. Problems?"

Listen for: a compromised or misconfigured cluster can lie to an in-cluster verifier;
cluster-admin verifier is itself a violation of least privilege (and of R8's spirit). Better:
verifier runs **outside** (management plane), reads cloud APIs, uses a narrowly-scoped
read-only identity, and signs results with a key the cluster can't reach — exactly the pattern
of [ADR-0059](../../adrs/0059-independent-observer-attestor-profiles.md). Deep question:
"Can you prove nobody has cluster-admin from a principal that doesn't have it?" — yes, via
SubjectAccessReview and listing bindings; but listing needs read on RBAC, which is itself a
sensitive grant. Watch how they bound it.

### C8. It passed in staging
> "1.34 → 1.35 passed conformance in dev and staging. Prod GPU cluster at 4 800 nodes fails:
> pods stuck `ContainerCreating`. Which requirements are scale-dependent, and how do you
> verify them before prod?"

Listen for: IP exhaustion with ENI IPAM, apiserver/etcd load, Cilium identity count,
Karpenter launch rate limits, EC2 capacity (ICE). These are **capacity requirements**, not
config — need explicit numbers (IP headroom %, identities, pods/node) checked continuously
and a pre-prod scale test or a progressive upgrade by node pool. Strong: "staging is not a
smaller prod; it's a different system. Some requirements must be proven *in* prod,
progressively, with a stop condition."

## Signals

**Strong**
- Rewrites "100% sure" into "complete, fresh, independent evidence — or the cluster can't
  receive change".
- Distinguishes config, behaviour, and capacity requirements.
- Demands evidence cardinality (every node, every namespace) and freshness.
- Tests the tests (canary violations).
- Puts the verifier outside the blast radius and with less privilege than the verified.

**Weak**
- "Run the acceptance checklist in CI" — automates the same config assertions.
- Equates "policy installed" with "policy enforced".
- One response for every failure.

**Red flags**
- "100% is impossible" and stops.
- Verifier with cluster-admin inside the cluster, after C7.
- Six months green = compliant.

## Scoring anchors

| Dimension | 1 | 4 |
|---|---|---|
| Framing | Accepts or rejects "100%" | Converts it into a signed, falsifiable promise about evidence |
| Mechanism | "We check it" | Explains exactly why config ≠ property and per-node evidence matters |
| Verifiability | Checks without proof they work | Canary violations, error-as-fail, cardinality, freshness |
| Trade-offs | Same response everywhere | Different response per requirement, aware of remediation blast radius |
| Altitude | One cluster | Fleet of four families, scale-dependent requirements, upgrade waves |
