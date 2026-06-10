# ADR-0040: SOC2 posture (GCP policy parity, cross-cloud WIF, control-to-evidence mapping) + ML on-call

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — the GCP org-policy module
  (`gcp-org-policy`) and the compliance/runbook docs are introduced by this ADR; no
  org-policy is applied and no GCP↔AWS Workload Identity Federation is provisioned
  until the apply gate is cleared.
- Date: 2026-06-10
- Authors: platform-team (security-expert), compliance, SRE
- Related issues: WS-E "Security posture & SOC compliance + on-call" (GCP ML Platform
  plan); plan readiness row 6 ("SOC compliance + on-call", partial); ADR-0028
  (taxonomy), ADR-0038 (drift→PagerDuty route), ADR-0037 (MLflow/Cloud SQL/GCS),
  ADR-0036 (multi-region GKE), ADR-0018 (Pod Identity / IRSA).
- Supersedes: (none)
- Superseded by: (none)

## Context

The platform already runs a strong security control set, but it is **AWS- and
K8s-plane heavy** and has **never been mapped to an audit framework**. The plan's
readiness assessment (row 6) records the gap precisely: on-call exists (PagerDuty +
Alertmanager + runbooks), the controls exist (Kyverno + VAP, Tetragon, Gatekeeper,
GuardDuty, `iam-baseline`, SCPs, `secret-rotation`, cosign/syft signing), but there
is **no SOC2 control-mapping / evidence-collection / posture report**, and **GCP-side
policy parity is thin**.

Four forces shape this ADR:

1. **GCP lacks a deny-list guardrail plane.** On AWS, SCPs (`terraform/modules/scps`)
   plus `iam-baseline` give an organization-wide deny layer: deny public S3, require
   EBS encryption, restrict regions, no root usage. On GCP there is **no equivalent
   org-policy layer in-repo** — a GCP project today could expose public IPs, create
   public buckets, mint long-lived service-account keys, or create unencrypted
   resources, with nothing stopping it.

2. **Cross-cloud identity is still key-based.** Per-pod GKE Workload Identity is
   **already done** in `gcp-gke-gpu-nodepools`
   (`workload_metadata_config { mode = "GKE_METADATA" }`) and is **not re-opened
   here.** What is missing is **cross-cloud federation**: a GCP workload that needs an
   AWS resource (or vice-versa — e.g. the GCP ML platform reading an S3 dataset, or an
   AWS job writing to the GCS artifact store from ADR-0037) has no keyless path and
   would fall back to a static access key. That is exactly the static credential the
   AWS `iam-baseline` posture forbids.

3. **No auditor-facing control map exists.** A SOC2 (or ISO/customer-security) review
   asks "which control satisfies CC6.1, and where is the evidence?" Today the answer
   lives in the heads of the platform team. There is no artifact tying TSC criteria to
   the modules/apps/actions that satisfy them, and no statement of what is still a gap.

4. **On-call has no ML track and no tested rotation.** ADR-0038 explicitly deferred a
   **dedicated ML PagerDuty service** to "the follow-up recommended by WS-E," and
   there are **no ML-incident runbooks** (drift, training-pipeline, serving). The
   rotation is informal.

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (the unified
`platform:system` / `platform.system` taxonomy) is mandatory on everything introduced
here; `system = security` for the org-policy/posture plane and `compliance` is used as
the documentation domain. GCP label keys use the underscore spelling
(`platform_system`) because GCP labels disallow `:`.

## Decision

Make SOC2-style compliance **demonstrable** and complete the **on-call posture on
GCP**, via four sub-decisions. All are **plan/validate-only**; nothing applies without
the apply gate, and org-policy / WIF changes additionally require explicit
blast-radius review (they are organization-wide and identity-critical).

### D1 — GCP policy parity via org-policy constraints (`gcp-org-policy` module)

Introduce `terraform/modules/gcp-org-policy` (+ catalog unit + `*.tftest.hcl`),
binding a bundle of **GCP Organization Policy constraints** to a resource-manager node
(org / folder / project) using the **modern `google_org_policy_policy` resource**
(provider `google ~> 6`, the v2 Org Policy API — **not** the deprecated
`google_organization_policy`). The bundle maps onto the AWS deny-list controls:

| AWS control (in-repo) | GCP parity (this module) | SOC2 |
|---|---|---|
| `scps` deny_s3_public + `iam-baseline` S3 PAB | `storage.publicAccessPrevention` | CC6.6 |
| `iam-baseline` EBS-encryption-by-default | `gcp.restrictNonCmekServices` (CMEK mandatory) | CC6.1 |
| `scps` restrict_regions | `gcp.resourceLocations` (data residency) | C1.1 |
| `iam-baseline` MFA / no static creds | `iam.disableServiceAccountKeyCreation` + `…Upload` | CC6.1/CC6.3 |
| (no AWS analog — GCP hardening) | `compute.vmExternalIpAccess` (deny public IPs), `compute.requireOsLogin`, `sql.restrictPublicIp`, `storage.uniformBucketLevelAccess` | CC6.1/CC6.6 |

The module is **deny-by-default** (every constraint on), with per-constraint toggles
for staged rollout and an allow-list for `vmExternalIpAccess` (e.g. a NAT/egress
instance). Boolean constraints set `spec.rules[].enforce = "TRUE"`; list constraints
(`restrictNonCmekServices`, `resourceLocations`, `vmExternalIpAccess`) use
`values { denied_values | allowed_values }` / `deny_all`.

Chosen as the **GCP deny-list plane** because org-policy is the *only* GCP control that
is **preventive and hierarchy-inherited** the way SCPs are on AWS — it blocks the
violating API call regardless of IAM grants, giving true parity with the SCP posture
rather than detect-after-the-fact.

### D2 — Cross-cloud Workload Identity Federation (GCP WIF ↔ AWS IAM), keyless

Adopt **Workload Identity Federation** for cross-cloud access in **both directions**,
eliminating static cross-cloud credentials:

- **AWS → GCP:** a `google_iam_workload_identity_pool` + AWS provider
  (`google_iam_workload_identity_pool_provider` with an `aws { account_id }` block).
  An AWS role's STS identity is exchanged for short-lived GCP credentials via
  `roles/iam.workloadIdentityUser`, with **attribute mapping** pinning
  `google.subject = assertion.arn` and `attribute.aws_role`. Google is a **built-in
  OIDC provider in AWS**, so no `aws_iam_openid_connect_provider` is needed.
- **GCP → AWS:** the GCP workload's Google identity is presented to an **AWS IAM role
  whose trust policy federates `accounts.google.com`** (web-identity), again keyless.

This composes with — and depends on — **D1's `iam.disableServiceAccountKeyCreation`**:
once SA keys are denied org-wide, WIF is the *only* cross-cloud path, which is the
intended forcing function. The actual pool/provider Terraform is a **follow-up module**
(`gcp-wif` or folded into `iam-baseline`'s GCP analog) and is **not built in this WS**;
this ADR ratifies the **decision and the keyless contract**, and D1 ships the
constraint that makes it mandatory.

### D3 — SOC2 control-to-evidence mapping + repo-anchored evidence collection

Publish [`docs/compliance/soc2-control-matrix.md`](../compliance/soc2-control-matrix.md):
a matrix from the **SOC2 Trust Services Criteria (CC1–CC9, plus A/C/PI where in
scope)** to the **existing in-repo controls** that satisfy each criterion (Kyverno,
Gatekeeper, Tetragon, `iam-baseline`, `scps`, `secret-rotation`, GuardDuty/SecurityHub,
CloudTrail/Config, cosign/syft supply chain), with each row's **plane**, **evidence
signal**, and **status** (`evidenced` / `partial` / `gap` / `inherited`), and an
explicit **still-gap** list.

**Evidence-collection approach: pull-based and repo-anchored.** No separate GRC tool is
introduced. An auditor request resolves to (1) the ADR documenting the decision, (2)
the module/app/action implementing it, (3) the `*.tftest.hcl` or CI run proving
behavior, and (4) the runtime signal (Config evaluation, GuardDuty finding, admission
deny, **org-policy deny**, fired alert) — all attributable on the ADR-0028 `$system`
axis. The repo + observability stack **is** the evidence store.

### D4 — On-call rotation formalization + ML-incident runbooks

Publish [`docs/runbooks/ml-incident-runbook.md`](../runbooks/ml-incident-runbook.md)
(model drift/accuracy, training-pipeline failure, serving outage — each with a triage
decision tree, mitigation, and recovery) and
[`docs/runbooks/oncall-rotation-escalation.md`](../runbooks/oncall-rotation-escalation.md)
(two rotations — `platform-oncall` + `ml-platform-oncall` — L1→L3 escalation with
per-severity timers, and a quarterly **tabletop**).

These **tie into the existing PagerDuty/Alertmanager wiring**, not a new one: the ML
runbook routes off the ADR-0038 `ml-drift-pagerduty` / `ml-retrain-webhook` receivers
and the existing `alertmanager-pagerduty-secret` (ESO-sourced, ADR-0008). The
`ml-platform-oncall` PagerDuty **service** is the formalization of the dedicated ML
routing key ADR-0038 D3 deferred to WS-E; until provisioned, ML alerts fall back to the
shared platform receiver.

### D5 — ADR-0028 label compliance (org-policy plane)

`google_org_policy_policy` is **not a labelable resource** (it is an org-policy
binding, not a billable resource), exactly as `google_billing_budget` is not in
`gcp-billing-budget`. The `gcp-org-policy` module therefore carries the ADR-0028
taxonomy on a `labels` input (GCP underscore keys), defaults
`platform_system = security` / `platform_component = org-policy` /
`platform_managed_by = terragrunt`, and exposes it on the `platform_labels` output for
**provenance** — a reviewer greps for it and the `*.tftest.hcl` asserts it. It is not
applied to a GCP resource because none in this module accepts labels. K8s/doc artifacts
use the dotted form (`platform.system`).

## Alternatives considered

### Alternative A: GKE Policy Controller / Gatekeeper constraint bundle on GKE instead of org-policy

The plan offered org-policy **or** a GKE Gatekeeper constraint bundle under
`apps/infra/policy-controller/`. Rejected as the *primary* deliverable because
Gatekeeper only governs **Kubernetes admission** — it cannot stop a public IP on a
Compute VM, a public GCS bucket, a long-lived SA key, or a non-CMEK Cloud SQL
instance, all of which are **GCP-resource-level** concerns and exactly the SCP-parity
gap. Org-policy is the correct preventive plane for those. The GKE Gatekeeper bundle
remains the right tool for *workload* admission and is **parity-designed** here (it
mirrors the existing EKS `apps/infra/gatekeeper` constraints) but its in-cluster
delivery to GKE is a tracked **follow-up**, recorded as a `gap` in the matrix (CC5.2).

### Alternative B: deprecated `google_organization_policy` (v1 API)

Rejected. The v1 resource is superseded by `google_org_policy_policy` (v2 Org Policy
API), which supports the richer `spec.rules` model (conditions, `deny_all`,
merged inheritance) and is the provider's forward path. Using the deprecated resource
would incur a near-term migration.

### Alternative C: static cross-cloud access keys (or per-workload secrets via ESO)

Rejected for cross-cloud auth. Even ESO-managed static keys are long-lived secrets that
must be rotated and can leak; they contradict the `iam-baseline` no-static-creds
posture. WIF is keyless and short-lived. ESO remains correct for *third-party* secrets
(Slack/PagerDuty tokens), not for cloud-to-cloud identity.

### Alternative D: adopt a dedicated GRC/compliance SaaS for evidence

Rejected (YAGNI for this stage). A GRC tool adds a second source of truth that drifts
from the repo. The repo-anchored, pull-based evidence model (D3) keeps evidence next to
the control and versioned with it. A GRC tool can later *index* this matrix without
owning it.

### Alternative E: status quo (no GCP guardrails, no control map)

Rejected — it is the exact readiness gap (plan row 6) this WS exists to close, and it
leaves the GCP estate able to create public/unencrypted/key-based resources with no
preventive control and no audit story.

## Consequences

### Positive

- **GCP gains a real preventive deny-list plane** at parity with AWS SCPs +
  `iam-baseline` — public IPs, public buckets, public Cloud SQL, non-CMEK resources,
  and long-lived SA keys are all blocked at the API.
- **Cross-cloud identity becomes keyless** (decision ratified; D1 makes it mandatory),
  removing the last static-credential path between clouds.
- **The platform is auditable**: a single matrix answers SOC2 TSC questions with repo
  evidence and an honest gap list.
- **On-call covers ML** with tested runbooks and a formal escalation policy, closing
  ADR-0038's deferred ML-PagerDuty follow-up.

### Negative

- **Org-policy is high-blast-radius.** A wrong constraint can block legitimate
  provisioning org-wide (e.g. CMEK on a service with no key, or `resourceLocations`
  too tight). Mitigated by per-constraint toggles, an allow-list for external IPs, the
  apply gate, and staged rollout (project → folder → org).
- **WIF setup is non-trivial** (attribute mapping, trust policies both directions) and
  is deferred to a follow-up module — this ADR ships the decision + the forcing
  constraint, not the pool.
- **The matrix must be maintained.** It is only useful if kept current as controls
  change; it is wired into the ADR/PR process (a new control adds a matrix row).

### Risks

- **R1 — org-policy lockout.** Applying `disableServiceAccountKeyCreation` before WIF
  exists could strand a workload that still needs a key. *Mitigation:* sequence WIF
  (D2) before/with that constraint in prod; non-prod can enforce immediately since the
  ML platform uses Workload Identity already.
- **R2 — false sense of compliance.** A matrix is not an audit. *Mitigation:* statuses
  are honest (`partial`/`gap` are first-class), and the still-gap list is explicit
  (GCP SCC/Config, GCP audit-log export, GKE admission delivery, data-disposal proof).
- **R3 — drift between matrix and reality.** *Mitigation:* evidence is repo-anchored
  (D3) so the matrix points at code that CI already validates; a stale row points at a
  removed module and is caught in review.
- **R4 — CMEK/locations breaking ADR-0037 GCS/Cloud SQL.** *Mitigation:* the catalog
  unit's `enforce_cmek` already lists `storage`/`sqladmin`, so those services are
  provisioned CMEK-first by design; `resourceLocations` defaults to US+EU groups that
  cover the planned regions (ADR-0036).

## Implementation notes

### Files created by this ADR

- `terraform/modules/gcp-org-policy/` — `versions.tf`, `variables.tf`, `main.tf`,
  `outputs.tf`, `gcp-org-policy.tftest.hcl` (mocked-provider plan tests).
- `catalog/units/gcp-org-policy/terragrunt.hcl` — per-project/folder/org consumption;
  falls back to `projects/<project_id>` (least blast radius) when no
  `org_policy_parent` is set in `project.hcl`.
- `docs/compliance/soc2-control-matrix.md` — the control-to-evidence matrix (D3).
- `docs/runbooks/ml-incident-runbook.md` + `docs/runbooks/oncall-rotation-escalation.md`
  (D4).
- `docs/adrs/0040-soc-posture-and-oncall.md` (this file) + the README index row.

### Validation performed (plan/validate-only)

- `terraform fmt`, `terraform init -backend=false`, `terraform validate`,
  `terraform test` (mocked `google` provider) on `gcp-org-policy` — **11/11 tests
  pass**.
- `terragrunt hcl fmt --check` on the catalog unit — clean.
- `yamllint` on any YAML; markdown link sanity on the docs.
- **No `terraform apply`, no org-policy applied, no WIF pool created.**

### Out of band / follow-ups (tracked as matrix gaps)

- `gcp-wif` pool/provider module (D2 implementation).
- GKE Gatekeeper constraint-bundle delivery to GKE clusters (CC5.2 gap).
- GCP Security Command Center / Config-equivalent continuous evaluation (CC4.1 gap).
- GCP Cloud Audit Logs export + log-based metrics (audit-logging gap).
- `ml-platform-oncall` PagerDuty service provisioning (expected first-tabletop action
  item).

### Rollback

Org-policy and the docs are additive. To roll back, set the relevant module toggles to
`false` (removes the policy bindings) or detach the catalog unit; no data is destroyed.
WIF is not yet applied, so there is nothing to roll back there.

## Revisit trigger

Revisit this ADR when: (a) the `gcp-wif` module is built (fold the pool/provider
contract back in), (b) GCP SCC / Config parity lands (flip CC4.1 from `gap`), (c) the
GKE Gatekeeper bundle is delivered (flip CC5.2), or (d) a real SOC2 audit scopes
additional TSC categories (A/C/PI) requiring new matrix rows.

## References

- [SOC2 control matrix](../compliance/soc2-control-matrix.md) (D3)
- [ML incident runbook](../runbooks/ml-incident-runbook.md) +
  [on-call rotation & escalation](../runbooks/oncall-rotation-escalation.md) (D4)
- [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) — taxonomy
- [ADR-0038](0038-ml-observability-drift.md) — drift→Alertmanager→PagerDuty (ML
  PagerDuty follow-up deferred to WS-E)
- [ADR-0037](0037-ml-cicd-pipeline-mlflow.md) — MLflow / Cloud SQL / GCS (CMEK +
  public-IP constraints protect these)
- [ADR-0036](0036-gke-ml-infra-parity-multiregion.md) — multi-region GKE (locations
  guardrail) + DCGM/serving failover referenced by the ML runbook
- [ADR-0018](0018-eks-pod-identity-as-default-workload-identity.md) — Pod Identity /
  IRSA (AWS-side keyless identity; WIF is the cross-cloud analog)
- GCP Org Policy v2 — `google_org_policy_policy` (hashicorp/google ~> 6);
  constraints: `compute.vmExternalIpAccess`, `iam.disableServiceAccountKeyCreation`,
  `gcp.restrictNonCmekServices`, `gcp.resourceLocations`,
  `storage.publicAccessPrevention`, `sql.restrictPublicIp`,
  `storage.uniformBucketLevelAccess`, `compute.requireOsLogin`.
- GCP Workload Identity Federation with AWS — `google_iam_workload_identity_pool` +
  `…_provider` `aws { account_id }`; Google as a built-in OIDC provider in AWS IAM.
- SOC2 Trust Services Criteria (2017, revised) — Common Criteria CC1–CC9.
