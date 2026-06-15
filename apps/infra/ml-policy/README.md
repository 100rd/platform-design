# App: `ml-policy`

> **ADRs:** [0020](../../../docs/adrs/0020-kyverno-and-vap-policy-engine.md)
> (Kyverno + VAP / Gatekeeper engines),
> [0028](../../../docs/adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md)
> (taxonomy + ABAC), [0044](../../../docs/adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md)
> (GPU/ML estate), [0048](../../../docs/adrs/0048-aws-ml-cicd-registry-drift.md) (ML layer).

WS-E **in-cluster policy enforcement** for the greenfield AWS EKS GPU/ML estate — the
admission-plane parity to the cloud-plane control set
(`terraform/modules/aws-ml-scp-parity` SCPs, `tests/opa/platform_tags_ml.rego` plan-time
OPA). It **reuses the existing Kyverno and Gatekeeper engines** (apps/infra/kyverno,
apps/infra/gatekeeper) — it ships only policy objects, no engine.

## What it ships (`helm template` → 3 manifests)

| Manifest | Engine | Effect |
|---|---|---|
| `require-ml-platform-labels` (ClusterPolicy) | Kyverno | ML/GPU Jobs/Deployments/StatefulSets in the ML namespaces must carry the 3 ADR-0028 platform labels |
| `no-privileged-gpu-pods` (ClusterPolicy) | Kyverno | denies privileged / privilege-escalating containers on ML/GPU pods (SOC2 CC6.1) |
| `ml-block-privileged-containers` (Constraint) | Gatekeeper | second engine, **reuses** the existing `K8sBlockPrivileged` ConstraintTemplate, ML-namespace-scoped |

Two engines on the privileged-pod control (ADR-0020 belt-and-suspenders): if one webhook
is unavailable the other still denies.

## Apply-gated / phased rollout

Ships **Audit-first** (`values.enforcement.platformLabels=Audit`,
`values.enforcement.noPrivilegedGpu=Audit`; Gatekeeper `dryrun`). No workload is blocked
until a human promotes to `Enforce` after a clean soak window (the ADR-0020 pattern). The
`kyverno.enabled` / `gatekeeper.enabled` toggles render the chart inert per-engine if an
engine is absent.

## ADR-0028 taxonomy

The Application and every policy object carry `platform.system=security`,
`platform.component=ml-policy`, `platform.owner=team-sec`, `platform.env=production`,
`platform.managed-by=argocd`.

## Validation (plan/validate-only)

`helm template apps/infra/ml-policy/` renders 3 valid manifests; `yamllint` clean on the
static YAML. **No `kubectl apply` / `helm install` / ArgoCD sync** is performed — delivery
is apply-gated behind the ArgoCD sync gate and human promotion to Enforce.
