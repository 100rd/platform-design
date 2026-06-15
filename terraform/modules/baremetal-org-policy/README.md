# baremetal-org-policy

> **WS-E — Security posture & SOC compliance** (Bare-Metal ML Platform).
> Bare-metal/Talos analogue of [`gcp-org-policy`](../gcp-org-policy/) and the AWS
> `iam-baseline` + `scps` guardrails.
>
> **ADRs cited:** [ADR-0040](../../../docs/adrs/0040-soc-posture-and-oncall.md)
> (SOC posture + on-call, reused as decision of record),
> [ADR-0049](../../../docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
> (Talos foundation / multi-DC — the posture IS a WS-A property this module asserts),
> [ADR-0050](../../../docs/adrs/0050-talos-gpu-driver-system-extensions.md)
> (immutable-OS security rationale: no package manager, system-extension driver),
> [ADR-0028](../../../docs/adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md)
> (platform taxonomy).
>
> **plan/validate-only — apply-gated.** This is a MOCK/emulation repo. Nothing here
> is applied to a real Talos cluster. The policy bundle is **default-OFF**
> (`deploy_policy_bundle = false`): a plan creates **zero** resources.

## What it does

The Talos estate has no cloud org-policy API. This module delivers guardrail parity
on two **plan-safe** planes:

### 1. Talos OS posture assertions (immutable-OS controls)

Compares the **expected** Talos security posture (the `assert_*` toggles) against the
**observed** posture (the `observed_*` inputs, wired from WS-A's `talos-machineconfig`
through a `dependency` block) and emits `posture_violations` + a `posture_compliant`
boolean — pure computation, never touches a cluster. Each assertion maps to a SOC2
control family, so the [SOC2 control-to-evidence matrix](../../../docs/compliance/soc2-control-matrix-baremetal.md)
can cite a concrete Terraform assertion (the WS-E acceptance criterion).

| Assertion | Talos posture | SOC2 |
|---|---|---|
| `no_ssh` | no shell, no sshd, no shell-opening kernel args | CC6.1 / CC6.6 |
| `mtls_machine_api` | machine API mTLS-only, strict client-cert auth | CC6.1 / CC6.7 |
| `kubeprism` | `machine.features.kubePrism` enabled (in-cluster API HA) | A1.2 / CC7.5 |
| `immutable_install` | immutable install disk; A/B atomic upgrade + auto-rollback | CC8.1 |
| `no_package_manager` | no package manager / writable `/usr` (driver via system extension) | CC6.8 |

### 2. Kyverno/Gatekeeper admission policy bundle (as code)

Renders the UK-DC tenant-isolation constraints (the `06-uk-datacenters.md` Gatekeeper
constraints, ported to Kyverno `ClusterPolicy`): **require `tenant={id}` label** and
**deny cross-namespace ServiceAccount references**. The bundle is **rendered into
outputs for plan review even when not deployed**; it is only materialised as
`kubectl_manifest` resources when `deploy_policy_bundle = true` (CI on `main`, after
human go + blast-radius review).

## Apply-gating

| Plane | Default | Creates infra? |
|---|---|---|
| Posture assertions (locals/outputs) | always evaluated | no — pure computation |
| Policy bundle (`kubectl_manifest.policy`) | `deploy_policy_bundle = false` | **no** — `for_each` is empty |

## ADR-0028 taxonomy

`platform_system = security`, `platform_component = org-policy` on the Terraform plane
(underscore form, recorded for provenance — neither posture assertions nor CR bindings
are labelable Terraform resources). Rendered CRs carry the **dotted** form
(`platform.system`, `platform.managed-by`) in `metadata.labels`.

## Usage (via the catalog unit)

Wired in [`catalog/units/baremetal-org-policy`](../../../catalog/units/baremetal-org-policy/)
with the Talos kubeconfig from the `talos-cluster` dependency (mocked at plan time)
and the observed posture from `talos-machineconfig`. See the unit for the provider
generation pattern (no static credentials).

## Tests

`terraform test` (`baremetal-org-policy.tftest.hcl`, mocked providers): 12 runs —
posture compliance, per-assertion drift detection + SOC2 mapping, staged carve-outs,
bundle rendering, the **default-OFF apply gate** (`length(kubectl_manifest.policy) == 0`),
dotted-label re-keying, enforce-mode threading, and input validation.
