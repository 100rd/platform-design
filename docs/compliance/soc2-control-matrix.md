# SOC2 Control-to-Evidence Matrix

> **Status:** Design-target (WS-E of the GCP ML Platform plan). This matrix maps the
> SOC2 **Trust Services Criteria (TSC, 2017 revised — Common Criteria CC-series)** to
> the **controls that already exist in this repository** plus the **GCP-side controls
> WS-E adds** ([ADR-0040](../adrs/0040-soc-posture-and-oncall.md)). It is the
> single artifact an auditor (or the platform owner) uses to answer "which control
> satisfies this criterion, and where is the evidence?"
>
> "Evidence" here means a repo artifact (Terraform module / ArgoCD app / GitHub Action
> / runbook) and the runtime signal it produces (a deny event, a Config rule
> evaluation, a CloudTrail log, a signed image attestation, a fired alert). Nothing in
> this matrix is applied without the apply gate (ADR-0040, plan §); the matrix
> describes the **intended control surface** and flags what is **still a gap**.

## How to read this

- **Plane** — `AWS` (Terragrunt/Terraform control plane), `K8s` (ArgoCD/Helm workload
  plane), `GCP` (the new GCP estate), or `CI` (GitHub Actions supply chain).
- **Status** — `evidenced` (control exists in-repo and produces auditable signal),
  `partial` (control exists but coverage is incomplete), `gap` (no control yet;
  WS-E or a follow-up closes it), `inherited` (cloud-provider shared responsibility).
- Every control carries the [ADR-0028](../adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md)
  `platform:system` / `platform.system` taxonomy so evidence is attributable to a
  logical system on the same Grafana `$system` variable across AWS + GCP.

---

## CC1 — Control Environment (governance, accountability)

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC1.1 Integrity & ethics; defined org structure | OU split — Prod / Non-Prod / Deployments / Suspended / Sandbox ([ADR-0001](../adrs/0001-ou-split.md)); `terraform/modules/organization` | AWS | Org/OU tree in Organizations; per-OU SCP attachment | evidenced |
| CC1.2 Board/owner oversight | ADR ratification trail (`docs/adrs/README.md` records owner ratification dates) | — | ADR status + ratification footer per ADR | evidenced |
| CC1.3 Authority & responsibility | ADR-0028 `platform:owner` taxonomy on every resource (team-sec / team-data / team-ml-platform) | AWS+K8s+GCP | `owner` tag/label per resource; Backstage ownership (ADR-0034, deferred) | partial |
| CC1.4 Competence / on-call readiness | On-call rotation + tabletop ([docs/runbooks/oncall-rotation-escalation.md](../runbooks/oncall-rotation-escalation.md)) | — | Tabletop exercise record; PagerDuty schedule | evidenced (WS-E) |

## CC2 — Communication & Information

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC2.1 Quality information for control | Unified observability stack (`apps/infra/observability/prometheus-stack`, VictoriaMetrics, OTel) | K8s | Metrics/logs/traces with ADR-0028 labels | evidenced |
| CC2.2 Internal comms of responsibilities | Runbooks (`docs/sre-runbook.md`, `docs/runbooks/*`, `docs/multi-region/runbooks/*`) + incident Slack templates | — | Runbook docs; #incidents channel templates | evidenced |
| CC2.3 External comms | Incident comms templates in on-call doc (status-page / stakeholder updates) | — | Comms templates in [oncall doc](../runbooks/oncall-rotation-escalation.md) | partial |

## CC3 — Risk Assessment

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC3.1 Objectives for risk ID | Risk register referenced by the GCP ML plan (R1–R5) and per-ADR Risks sections | — | ADR "Risks" sections; plan risk register | evidenced |
| CC3.2 Risk identification & analysis | Drift/accuracy monitoring ([ADR-0038](../adrs/0038-ml-observability-drift.md)); GuardDuty findings (`terraform/modules/guardduty-org`) | GCP-ML+AWS | Evidently/whylogs metrics; GuardDuty findings feed | partial |
| CC3.3 Fraud risk | GuardDuty threat detection (`guardduty-org`, `securityhub-org`) | AWS | GuardDuty/SecurityHub findings | evidenced |
| CC3.4 Change-impact on risk | ADR process; `terraform plan` in PR + `*.tftest.hcl` gating | AWS+CI | PR plan output; passing module tests | evidenced |

## CC4 — Monitoring Activities

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC4.1 Ongoing/separate evaluations | AWS Config + Security Hub (`aws-config`, `config-org`, `security-hub`, `securityhub-org`) | AWS | Config rule evaluations; SecurityHub CIS/FSBP score | evidenced |
| CC4.1 (GCP parity) | Gap → **WS-E follow-up**: GCP Security Command Center / Config equivalent | GCP | (not yet) | gap |
| CC4.2 Deficiency communication | Findings → Alertmanager → PagerDuty; SecurityHub → SNS | AWS+K8s | Fired alerts; PagerDuty incidents | evidenced |

## CC5 — Control Activities

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC5.1 Control selection to mitigate risk | SCPs (`terraform/modules/scps`) + org-policy (`terraform/modules/gcp-org-policy`, WS-E) as the deny-list control layer | AWS+GCP | SCP/org-policy deny events | evidenced (GCP new) |
| CC5.2 Technology general controls | Admission policy: Kyverno (`apps/infra/kyverno`) + Gatekeeper (`apps/infra/gatekeeper`) + GKE Gatekeeper constraint-bundle parity (ADR-0040) | K8s | Admission deny audit events | evidenced (GKE parity designed) |
| CC5.3 Policy deployment via procedures | GitOps — ArgoCD app-of-apps; policies delivered as code | K8s | ArgoCD sync status; Git history | evidenced |

## CC6 — Logical & Physical Access Controls *(the core security family)*

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC6.1 Identity & least-privilege access | `iam-baseline` (password policy, MFA, Access Analyzer); IRSA/Pod Identity (ADR-0018); GKE Workload Identity (`gcp-gke-gpu-nodepools`); **org-policy `iam.disableServiceAccountKeyCreation` + cross-cloud WIF (WS-E)** | AWS+K8s+GCP | Access Analyzer findings; no static SA keys; WIF token-exchange logs | evidenced (GCP new) |
| CC6.2 Registration/authorization of users | SSO permission sets (`docs/runbooks/sso-permission-sets.md`); break-glass IAM (ADR-0011) | AWS | Permission-set assignments; break-glass audit | evidenced |
| CC6.3 Role-based access / segregation | RBAC + namespace isolation; `platform:owner` segregation; org-policy SA-key deny (WS-E) | K8s+GCP | RBAC bindings; org-policy deny | evidenced |
| CC6.4 Physical access | Cloud-provider responsibility (AWS/GCP shared responsibility — out of platform scope) | — | Provider SOC2/ISO report (inherited) | inherited |
| CC6.5 Data disposal | Velero backup lifecycle (`apps/infra/velero`); KMS key destruction protection (`terraform/modules/kms`) | AWS+K8s | Backup/retention policy; KMS schedule | partial |
| CC6.6 Boundary protection (network) | Cilium NetworkPolicies + default-deny (`kyverno generate-default-deny-netpol`); TGW segmentation (ADR-0013); **org-policy `compute.vmExternalIpAccess` / `sql.restrictPublicIp` / `storage.publicAccessPrevention` (WS-E)** | K8s+AWS+GCP | NetworkPolicy enforcement; org-policy deny of public IPs | evidenced (GCP new) |
| CC6.7 Transmission encryption / restriction | mTLS (Cilium, `docs/runbooks/cilium-mtls.md`); TLS ingress (Gateway API, ADR-0009) | K8s | mTLS handshake; TLS cert chain | evidenced |
| CC6.8 Malicious-software prevention | Image signing/verification: cosign (`.github/actions/cosign-sign`) + Kyverno `verify-images` + Gatekeeper `block-latest-tag`; Trivy scan (`.github/actions/trivy-scan`); Tetragon runtime (`apps/infra/tetragon`) | CI+K8s | cosign attestations; admission verify deny; Trivy report; eBPF events | evidenced |

## CC7 — System Operations (detection, incident response)

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC7.1 Vulnerability detection | Trivy (`.github/actions/trivy-scan`), CodeQL SAST (`sast-codeql`), dep scans (`node-dep-scan`, `python-dep-scan`), SBOM (`syft-sbom`) | CI | Scan reports; SBOM artifacts | evidenced |
| CC7.2 Anomaly/security-event monitoring | GuardDuty (`guardduty-org`) + Tetragon runtime (`apps/infra/tetragon`) + Security Hub | AWS+K8s | GuardDuty findings; Tetragon eBPF events | evidenced |
| CC7.3 Security-incident evaluation | Incident runbooks ([ml-incident-runbook](../runbooks/ml-incident-runbook.md), `docs/sre-runbook.md`); PagerDuty severity routing | — | Incident records; PagerDuty timeline | evidenced (WS-E adds ML) |
| CC7.4 Incident response | On-call rotation + escalation L1→L3 ([oncall doc](../runbooks/oncall-rotation-escalation.md)) | — | PagerDuty escalation; postmortems | evidenced (WS-E) |
| CC7.5 Recovery from incidents | DR runbooks (`docs/runbooks/DISASTER_RECOVERY.md`, `velero-restore.md`, multi-region failover) | — | Restore tests; failover drills | evidenced |

## CC8 — Change Management

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC8.1 Authorized, tested, approved changes | PR workflow + `terraform plan` + `*.tftest.hcl` + CI gates (ADR-0015/0016); ArgoCD GitOps; ML CI/CD (ADR-0037) | AWS+K8s+CI | PR approvals; passing tests; plan diff; ArgoCD sync | evidenced |

## CC9 — Risk Mitigation

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC9.1 Risk-mitigation (business disruption) | Multi-region GKE + serving failover (ADR-0036); billing budgets (`gcp-billing-budget`, `budgets`) | GCP+AWS | Failover drills; budget threshold alerts | evidenced |
| CC9.2 Vendor/third-party management | SBOM + signed-image supply chain (`syft-sbom`, `cosign-sign`); pinned chart/provider versions | CI+K8s | SBOM; signature attestations; pin diffs | evidenced |

---

## Audit-logging cross-cut (spans CC4 / CC6 / CC7)

| Concern | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| Org-wide audit trail | CloudTrail (`terraform/modules/cloudtrail`, `cloudtrail-org`) | AWS | Immutable multi-region trail, log-file validation | evidenced |
| Config/state recording | AWS Config (`aws-config`, `config-org`) | AWS | Config snapshots + rule evaluations | evidenced |
| Secret lifecycle / rotation | `terraform/modules/secret-rotation` + `secrets`; ESO ([ADR-0008]) | AWS+K8s | Rotation Lambda runs; ESO sync events | evidenced |
| Encryption key management | `terraform/modules/kms` (CMK rotation, destroy protection) | AWS | KMS rotation status | evidenced |
| GCP audit logging | Gap → **WS-E follow-up**: Cloud Audit Logs export + log-based metrics | GCP | (not yet) | gap |

---

## Availability (A-series), Confidentiality (C-series), Processing Integrity (PI-series)

These TSC categories are *additional* to the Common Criteria and apply only if the
SOC2 report scope includes them. Where the platform already has coverage:

| Criterion | Control | Plane | Status |
|---|---|---|---|
| A1.1 Capacity management | KEDA/HPA elasticity + GPU budgets (ADR-0036); cost (`opencost`, `gcp-billing-budget`) | K8s+GCP | evidenced |
| A1.2 Backup & recovery | Velero + DR runbooks; multi-region | K8s+AWS | evidenced |
| A1.3 Recovery testing | Failover drills + tabletop (WS-E on-call doc) | — | partial |
| C1.1 Confidential-data identification | ADR-0028 `platform:system` + data-residency org-policy (`gcp.resourceLocations`, WS-E) | GCP | evidenced (GCP new) |
| C1.2 Confidential-data disposal | KMS destruction protection; Velero retention | AWS+K8s | partial |
| PI1.x Processing integrity (ML correctness) | Drift/accuracy monitoring + retrain trigger (ADR-0038); ML CI/CD model registry (ADR-0037) | GCP-ML | evidenced |

---

## Coverage summary — what WS-E changes

**Before WS-E** the platform had strong AWS-plane and K8s-plane controls but the
**GCP estate lacked a deny-list guardrail layer**, **cross-cloud identity was
key-based**, and there was **no auditor-facing control map** or **ML-incident on-call
posture**. WS-E closes:

| SOC2 area | GCP/posture gap WS-E closes | New artifact |
|---|---|---|
| CC5.1 / CC6.6 | No GCP org-policy deny layer (public IPs, public buckets, Cloud SQL public IP) | `terraform/modules/gcp-org-policy` |
| CC6.1 | GCP CMEK + SA-key-creation not enforced; cross-cloud creds were static | org-policy `restrictNonCmekServices` + `disableServiceAccountKeyCreation`; **GCP↔AWS WIF** (ADR-0040) |
| C1.1 | No data-residency control on GCP | org-policy `gcp.resourceLocations` |
| CC1.4 / CC7.3 / CC7.4 | No ML-incident runbooks; on-call rotation informal | [ml-incident-runbook](../runbooks/ml-incident-runbook.md) + [oncall-rotation-escalation](../runbooks/oncall-rotation-escalation.md) |
| (all) | No auditor-facing control-to-evidence map | **this matrix** |

### Still-gap (tracked, not closed by WS-E)

- **CC4.1 (GCP)** — no GCP Security Command Center / Config-equivalent continuous
  evaluation yet (AWS has Config + Security Hub; GCP side is a follow-up).
- **Audit-logging (GCP)** — Cloud Audit Logs export + log-based metrics are a
  follow-up; AWS CloudTrail/Config parity is not yet on GCP.
- **CC5.2 (GKE admission)** — Kyverno/Gatekeeper run on EKS today; the GKE Gatekeeper
  constraint bundle is parity-designed in ADR-0040 but its in-cluster delivery to GKE
  is a follow-up (this WS ships the **org-policy** plane on GCP).
- **CC6.5 / C1.2 (data disposal)** — KMS + Velero retention exist but a documented,
  tested confidential-data-disposal procedure is partial.
- **CC1.3 (ownership)** — `platform:owner` taxonomy is present but the Backstage
  ownership catalog (ADR-0034) is deferred, so ownership evidence is tag-based not
  catalog-based.

> **Evidence-collection approach (ADR-0040, D3):** evidence is *pull-based and
> repo-anchored*. An auditor request resolves to: (1) the ADR documenting the
> decision, (2) the Terraform module / ArgoCD app / GitHub Action implementing it,
> (3) the `*.tftest.hcl` or CI run proving it behaves, and (4) the runtime signal
> (Config evaluation, GuardDuty finding, admission deny, org-policy deny, fired
> alert). No separate GRC tool is introduced; the repo + observability stack *is*
> the evidence store, queried on the ADR-0028 `$system` axis.
