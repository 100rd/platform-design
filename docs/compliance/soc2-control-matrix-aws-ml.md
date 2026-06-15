# SOC2 Control-to-Evidence Matrix — AWS GPU/ML Platform (WS-E)

> **Status:** Design-target (WS-E of the **AWS** ML Platform plan,
> `docs/aws-ml-platform/IMPLEMENTATION_PLAN.md` §4). This matrix maps the SOC2 **Trust
> Services Criteria (TSC, 2017 revised — Common Criteria CC-series)** to the controls
> that satisfy each criterion **for the greenfield AWS GPU/ML estate** (ADRs 0044–0048),
> plus the WS-E-added control plane. It is the AWS-side companion to the existing
> GCP-oriented [`soc2-control-matrix.md`](soc2-control-matrix.md) (WS-E of the GCP plan,
> ADR-0040) — same TSC structure, AWS-native controls.
>
> "Evidence" = a repo artifact (Terraform module / ArgoCD app / GitHub Action / runbook)
> and the runtime signal it produces (an SCP/Config/admission deny, a CloudTrail log, a
> signed-image attestation, a fired alert, an OPA plan-gate failure). **Nothing in this
> matrix is applied without the apply gate** — it describes the intended control surface
> and flags what is still a **gap**.

## How to read this

- **Plane** — `AWS` (Terragrunt/Terraform control plane), `K8s` (ArgoCD/Helm workload
  plane), `CI` (GitHub Actions supply chain + OPA plan gate), or `Org` (Organizations/SCP).
- **Status** — `evidenced` (control exists in-repo and produces an auditable signal),
  `partial` (control exists, coverage incomplete), `gap` (no control yet; a follow-up
  closes it), `inherited` (AWS shared-responsibility).
- Every control carries the [ADR-0028](../adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md)
  `platform:system` taxonomy so evidence is attributable on the Grafana `$system` axis.

---

## CC1 — Control Environment

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC1.1 Org structure | OU split + the GPU/ML OU (`terraform/modules/organization`, `aws-ml-scp-parity` targets the ML OU) | Org | OU tree; ML-OU SCP attachment | evidenced |
| CC1.3 Authority & responsibility | ADR-0028 `platform:owner` on every ML resource (`team-ml-platform` / `team-sec`) | AWS+K8s | `owner` tag/label per resource | partial |
| CC1.4 Competence / on-call | ML on-call rotation + tabletop ([oncall-rotation-escalation-aws.md](../runbooks/oncall-rotation-escalation-aws.md)) | — | PagerDuty schedule; tabletop record | evidenced (WS-E) |

## CC2 — Communication & Information

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC2.1 Quality information | The existing observability stack (ADR-0026) reused for ML metrics (`apps/infra/ml-monitoring`, `apps/infra/observability`) | K8s | Metrics/logs/traces with ADR-0028 labels | evidenced |
| CC2.2 Internal comms | ML runbooks ([ml-incident-runbook-aws.md](../runbooks/ml-incident-runbook-aws.md), [oncall…aws.md](../runbooks/oncall-rotation-escalation-aws.md)) | — | Runbook docs; `#ml-incidents` templates | evidenced (WS-E) |

## CC3 — Risk Assessment

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC3.1 / CC3.2 Risk ID & analysis | The AWS plan risk register (R1–R8) + per-ADR Risks sections (0044–0048) | — | Plan §9; ADR "Risks" sections | evidenced |

## CC4 — Monitoring Activities

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC4.1 Continuous evaluation | AWS Config + Security Hub (`terraform/modules/aws-config`), GuardDuty | AWS | Config rule evaluations; GuardDuty findings | partial |
| CC4.1 Plan-time policy gate | **`tests/opa/platform_tags_ml.rego`** — taxonomy + ABAC floor on the net-new `aws-eks-gpu-*`/`aws-ml-*` types (conftest-opa CI) | CI | OPA `deny` on a PR plan (8/8 unit tests) | evidenced (WS-E) |

## CC5 — Control Activities

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC5.2 Tech control deployment (preventive, cloud) | **`terraform/modules/aws-ml-scp-parity`** — ML-OU SCPs: IMDSv2, EBS-encryption, no-access-keys, region-restrict | Org | SCP deny on a violating API call | evidenced (WS-E, apply-gated) |
| CC5.2 Tech control deployment (admission) | **`apps/infra/ml-policy`** — Kyverno + Gatekeeper: require ML taxonomy labels, forbid privileged GPU pods | K8s | PolicyReport / admission deny | evidenced (WS-E, Audit-first) |

## CC6 — Logical & Physical Access

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC6.1 Logical access (least-priv + ABAC) | **`terraform/modules/aws-ml-abac-iam`** — least-privilege role, ABAC `platform:system` tag-match on S3/KMS/Secrets; EKS Pod Identity (ADR-0018) | AWS | IAM policy sim; CloudTrail `AssumeRole`; ABAC denial | evidenced (WS-E, apply-gated) |
| CC6.1 IMDSv2 enforced on GPU nodes | `aws-ml-scp-parity` `require_imdsv2` SCP | Org | SCP deny of metadata-v1 RunInstances | evidenced (WS-E) |
| CC6.1 Encryption at rest | `aws-ml-scp-parity` `require_ebs_encryption`; SSE-KMS on the ML S3 store (ADR-0048 D2) | Org+AWS | SCP deny; bucket SSE-KMS config | evidenced (WS-E) / partial |
| CC6.3 No static credentials | `aws-ml-scp-parity` `deny_access_keys` (deny `iam:CreateAccessKey`); Pod Identity is the only path | Org | SCP deny of `CreateAccessKey` | evidenced (WS-E) |
| CC6.6 Network boundary | GPU VPC private subnets + EFA SG (ADR-0044/0045, WS-A); Cilium NetworkPolicy (`platform.system` scoped) | AWS+K8s | SG/NACL config; default-deny netpol | partial (WS-A owns) |
| CC6.7 Data-in-transit | Envoy Gateway + AWS WAF on the inference front (ADR-0047, WS-A); TLS | K8s | Gateway/WAF config | partial (WS-A owns) |
| CC6.8 Unauthorized software | cosign keyless verify + syft SBOM (`.github/actions/cosign-sign`, `syft-sbom`, ADR-0029); `no-privileged-gpu` admission | CI+K8s | Image attestation; admission deny | evidenced |

## CC7 — System Operations

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC7.2 Incident detection | DCGM/GPU + ML-drift alerts → Alertmanager → PagerDuty (ADR-0038, `apps/infra/ml-monitoring`) | K8s | Fired alert; PagerDuty incident | evidenced |
| CC7.3 / CC7.4 Incident response | **[ML-incident runbook](../runbooks/ml-incident-runbook-aws.md)** (drift / training / serving) + escalation | — | Runbook + incident timeline | evidenced (WS-E) |
| CC7.1 Audit logging | CloudTrail multi-region + the EKS control-plane audit log (ADR per WS-A) | AWS | CloudTrail/audit events | partial |

## CC8 — Change Management

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC8.1 Change control | ADR-first + PR-based, apply-gated workflow; OPA + fmt/validate/test CI gates | CI | PR checks; ADR ratification | evidenced |

## CC9 — Risk Mitigation

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC9.1 Risk mitigation | AWS Budgets 80/100/120% + FORECASTED on GPU spend (`terraform/modules/budgets`, ADR-0044 D4, WS-A) | AWS | Budget alert | partial (WS-A owns) |

## Availability / Confidentiality (in-scope extras)

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| A1.2 Availability / failover | Multi-region EKS + Route 53 failover (`failover-controller`, ADR-0044 D5, WS-A) | AWS | Health-check failover event | partial (WS-A owns) |
| C1.1 Data residency | `aws-ml-scp-parity` `restrict_regions` (GPU regions only) | Org | SCP deny outside allowed regions | evidenced (WS-E) |
| C1.2 Confidential disposal | S3 lifecycle + versioning on the ML store (ADR-0048 D2, WS-B) | AWS | Lifecycle config | gap (WS-B owns) |

---

## Still-gap list (honest, first-class)

A matrix is not an audit. The following are **not yet evidenced** and are tracked:

1. **AWS Config / Security Hub continuous evaluation across all GPU regions** — `partial`
   (CC4.1); breadth of conformance packs for the new ML resource types is WS-A/follow-up.
2. **Cross-cloud WIF (GCP↔AWS)** — the inverse of ADR-0040 D2; decision ratified, the
   pool/provider module is a follow-up (CC6.1/CC6.3 for cross-cloud).
3. **`ml-platform-oncall` PagerDuty service provisioning** — the dedicated routing key is
   the first tabletop action item (CC1.4); until then ML alerts fall back to the shared
   receiver.
4. **Data-disposal proof** for the ML artifact store (C1.2) — lifecycle config exists in
   the WS-B design but the deletion-evidence trail is not yet wired.
5. **EKS control-plane audit-log export + retention** for the greenfield cluster (CC7.1) —
   WS-A owns the cluster; this matrix will flip to `evidenced` when that lands.

## Evidence-collection model (repo-anchored, pull-based)

No separate GRC tool (YAGNI, mirrors ADR-0040 D3). An auditor request resolves to (1) the
ADR (0044–0048), (2) the module/app/action (this matrix's "Control" column), (3) the
`*.tftest.hcl` / `opa test` / `helm template` run proving behavior, and (4) the runtime
signal (SCP/Config/admission/OPA deny, CloudTrail, fired alert) — all attributable on the
ADR-0028 `$system` axis. The repo + observability stack **is** the evidence store.

## References

- AWS ML Platform plan — `docs/aws-ml-platform/IMPLEMENTATION_PLAN.md` (WS-E, §7 #13)
- [ADR-0040](../adrs/0040-soc-posture-and-oncall.md) — the GCP etalon (SOC posture + WIF)
- [ADR-0044](../adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md) /
  [ADR-0048](../adrs/0048-aws-ml-cicd-registry-drift.md) — the AWS GPU/ML estate
- [ADR-0028](../adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md) — taxonomy + ABAC
- [ADR-0018](../adrs/0018-eks-pod-identity-as-default-workload-identity.md) — Pod Identity
- WS-E artifacts: `terraform/modules/aws-ml-scp-parity`, `terraform/modules/aws-ml-abac-iam`,
  `apps/infra/ml-policy`, `tests/opa/platform_tags_ml.rego`,
  [ML-incident runbook](../runbooks/ml-incident-runbook-aws.md),
  [on-call rotation](../runbooks/oncall-rotation-escalation-aws.md)
- SOC2 Trust Services Criteria (2017, revised) — Common Criteria CC1–CC9.
