# ADR-0017: Resource-side data perimeter and declarative org controls (RCPs, EC2 Declarative Policies, full-IAM SCPs)

- Status: **Proposed** — research-backed; decision to ratify, not yet
  implemented.
- platform-design status: **pending** — no RCPs, EC2 Declarative Policies, or
  full-IAM-language SCP refactor are wired into this repo yet.
- Date: 2026-06-06
- Authors: platform-team, security
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)

## Context

The org data perimeter today is **principal-side only**: SCPs enforce
`aws:PrincipalOrgID` on *callers*, so an identity inside the org cannot be used to
reach an out-of-org resource. Nothing protects our *resources* from external
principals — a public-bucket misconfiguration, an over-broad KMS grant, or a
cross-account `sts:AssumeRole` trust still punches straight through the perimeter,
because SCPs gate identities, not resources.

Three further constraints compound this:

1. **The root SCP slots are at 5/5.** AWS caps SCPs at five per OU/account, and the
   root is full — there is no room to add another deny-SCP-shaped control without
   merging or evicting an existing one.
2. **IMDSv2 / public-EBS / public-AMI guardrails are brittle.** Each is a
   *deny-SCP + AWS Config rule* pair: the SCP blocks the bad API shape, Config
   detects drift after the fact. Two moving parts per control, and the SCP burns
   slot budget.
3. **SCPs are reviewed by eye.** There is no automated gate that proves a proposed
   SCP edit does not *widen* effective access; reviewers reason about deny logic
   manually in PRs.

AWS has since shipped the primitives that close all three gaps.

## Decision

Adopt four complementary org-control primitives:

1. **Resource Control Policies (RCPs).** A new `RESOURCE_CONTROL_POLICY` policy
   type that applies a *resource-side* perimeter to S3, STS, KMS, SecretsManager,
   and SQS — denying access to org resources from any principal outside the org,
   symmetric to the existing principal-side SCP. RCPs have their **own slot
   budget** (separate from the 5/5 SCP cap), which directly relieves SCP pressure.
   Add a new `modules/rcps` module; the seed RCP enforces `aws:PrincipalOrgID` on
   the resource side (deny when the calling principal is not in the org and the
   call is not an AWS-service principal).
2. **EC2 Declarative Policies.** Express *desired state* — IMDSv2 required,
   block-public-EBS-snapshots, block-public-AMI, allowed-AMI list — as declarative
   policies the platform enforces at the API layer, replacing the brittle
   deny-SCP + Config-rule pairs. This **retires the `require_imdsv2` SCP** and its
   companion Config rule, returning an SCP slot.
3. **Full-IAM-language SCPs (Sept 2025).** SCPs now support the full IAM policy
   language (richer conditions, `NotAction`/`NotResource` semantics). Refactor the
   coarse `deny + ArnNotLike` exemption lists into **tag/condition-scoped**
   statements — fewer hard-coded exception ARNs, easier to audit.
4. **Access Analyzer `CheckNoNewAccess` as a CI gate.** Wire IAM Access Analyzer's
   `CheckNoNewAccess` into `terraform-checks.yml` so every SCP/RCP change is
   machine-checked to prove it does not grant new effective access before merge —
   replacing review-by-eye.

A reviewer can check conformance by confirming `modules/rcps` exists and is
attached at the root/OU, that `require_imdsv2` is now an EC2 Declarative Policy
(not an SCP), and that `terraform-checks.yml` runs `CheckNoNewAccess` against
policy diffs.

## Alternatives considered

### Alternative A: Status quo — principal-side SCPs + Config only
Keep enforcing only on the caller side and rely on Config rules for resource
drift.
Rejected because: it leaves the resource side of the perimeter open (public bucket
/ over-broad grant / external trust), keeps the 5/5 SCP slot pressure, and never
gives an automated "did this widen access?" gate.

### Alternative B: Merge SCPs to free slots instead of adopting RCPs
Consolidate existing deny-SCPs to make room.
Rejected because: merging makes the remaining SCPs larger and harder to reason
about, and still does nothing for the *resource side*. RCPs add the missing
perimeter half **and** bring their own slot budget — strictly better.

### Alternative C: Keep deny-SCP + Config pairs for EC2 hardening
Leave IMDSv2 / public-EBS / public-AMI as-is.
Rejected because: declarative policies collapse two moving parts into one
desired-state control, are evaluated at the API layer (no detect-after-the-fact
window), and free SCP slots.

## Consequences

### Positive
- Closes the resource side of the data perimeter (S3/STS/KMS/SecretsManager/SQS).
- Relieves the 5/5 root SCP slot cap (RCPs have a separate budget; EC2 declarative
  policies retire at least the `require_imdsv2` SCP).
- Replaces brittle deny-SCP + Config pairs with single desired-state controls.
- Machine-checked policy changes (`CheckNoNewAccess`) replace review-by-eye.

### Negative
- Two new policy types to author, attach, and reason about (RCPs evaluate
  *after* identity/SCP/resource policy — a new mental model for reviewers).
- EC2 Declarative Policies cover a fixed attribute set; controls outside that set
  still need SCP/Config.

### Risks
- A mis-scoped RCP could deny legitimate AWS-service access (e.g. log delivery,
  cross-service principals). Mitigated by the staged rollout below and an explicit
  service-principal carve-out in the seed RCP.
- `CheckNoNewAccess` false-confidence on policies it cannot fully model. Mitigated
  by keeping it advisory-then-blocking and pairing with the staged promotion.

## Implementation notes

Migration order (each step independently revertible):

1. Land the `CheckNoNewAccess` CI gate (advisory) so subsequent policy edits are
   measured from the start.
2. Enable the `RESOURCE_CONTROL_POLICY` and EC2 declarative policy types in the
   org.
3. **Stage the RCP in a `Policy-Staging` OU** (a small test account set) and verify
   no legitimate access breaks.
4. **Promote the RCP to root** once staging is clean.
5. Roll out the EC2 Declarative Policies; **retire the `require_imdsv2` SCP** and
   its Config rule.
6. Refactor the coarse deny+`ArnNotLike` SCPs to full-IAM tag/condition-scoped
   statements; flip `CheckNoNewAccess` to blocking.

Effort: **M**.

## References

- Resource Control Policies (RCPs):
  <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html>
- EC2 Declarative Policies:
  <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_declarative.html>
- IAM Access Analyzer custom policy checks (`CheckNoNewAccess`):
  <https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-custom-policy-checks.html>
- Related: ADR-0001 (OU split), ADR-0011 (break-glass IAM)

---
*Research-backed — 2026 platform modernization; grounded in infra@572b54d /
argocd@c364c6c. Proposed: decision to ratify, not yet implemented in
platform-design.*
