# baremetal-org-policy (ArgoCD app)

> **WS-E — Security posture & SOC compliance** (Bare-Metal ML Platform).
> In-cluster GitOps delivery of the Talos tenant-isolation Kyverno policy bundle —
> the counterpart of [`terraform/modules/baremetal-org-policy`](../../../terraform/modules/baremetal-org-policy/).
>
> **ADRs cited:** [ADR-0040](../../../docs/adrs/0040-soc-posture-and-oncall.md) (SOC
> posture, reused), [ADR-0049](../../../docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
> (foundation/tenant model), [ADR-0050](../../../docs/adrs/0050-talos-gpu-driver-system-extensions.md)
> (immutable-OS posture), [ADR-0028](../../../docs/adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md)
> (taxonomy), [ADR-0020](../../../docs/adrs/0020-kyverno-and-vap-policy-engine.md)
> (Kyverno engine — reused, **not** reinstalled).

## What it ships

Two `ClusterPolicy` CRs (the UK-DC Gatekeeper tenant constraints ported to Kyverno):

| Policy | Effect | SOC2 |
|---|---|---|
| `bm-require-tenant-label` | reject Pods without a `tenant={id}` label | CC6.1 |
| `bm-deny-cross-ns-sa` | reject Pods projecting a foreign-namespace SA token | CC6.3 |

Every CR carries the ADR-0028 dotted taxonomy (`platform.system=security` …) via
`_helpers.tpl`, so SOC2 evidence is attributable on the Grafana `$system` axis.

## Apply-gating (observe-first)

- The ArgoCD `Application` uses **manual sync** (no `automated:` block): the bundle
  is **not auto-delivered**. A human applies it after blast-radius review.
- The policies ship in **Audit** mode (`values.enforcementMode`) — violations are
  recorded in PolicyReports, admission is not blocked. Promote to `Enforce` after a
  clean soak window (record below).
- Reuses the existing `apps/infra/kyverno` controller (sync wave 6, after wave 5).

## Enforcement history

| Date | Policy | Mode | Note |
|---|---|---|---|
| (design) | both | Audit | initial WS-E delivery; observe-first |

## Validation

`helm lint` clean; `helm template | kubeconform -ignore-missing-schemas` (CRDs
skipped — Kyverno `ClusterPolicy` is a CRD, validated by the in-cluster controller).
