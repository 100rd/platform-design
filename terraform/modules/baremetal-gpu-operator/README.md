# baremetal-gpu-operator

Deploys the **NVIDIA GPU Operator in driver-less mode** on the Talos GPU cluster. Part of
**WS-A** of the Bare-Metal ML Platform. System: `ml-infra`.

**ADRs:** [ADR-0050](../../../docs/adrs/0050-talos-gpu-driver-system-extensions.md)
(GPU driver via Talos system extension → Operator runs driver-less). ADR-0028 labels.

## Why driver-less (and why it's *enforced*)

On Talos the GPU driver and `nvidia-container-toolkit` ship as a **system extension** baked
into the boot image (`talos-machineconfig`, ADR-0050). The Operator **cannot** install a
driver on an immutable, package-manager-less host — so `driver.enabled` and
`toolkit.enabled` are not just defaulted false, they are **`validation`-enforced false**:
setting either true fails the plan. The Operator provides only **device-plugin + GFD/NFD/CDI
+ the NVIDIA DRA driver**; DCGM is owned by `baremetal-gpu-dcgm`.

This is the immutable-OS inversion of `gke-gpu-operator` (which also runs driver-less, but
because GKE/COS supplies the driver — here the reason is Talos).

## What it creates (when `enabled = true`)

| Resource | Purpose |
|----------|---------|
| `kubernetes_namespace.gpu_operator` | Namespace, labeled per ADR-0028 |
| `helm_release.gpu_operator` | The GPU Operator chart, driver-less |

## Apply-gated

`var.enabled` defaults **false**. Providers are mocked at plan time — no live cluster, no
Helm install. No `terraform apply` in this repo.

## ADR-0028 labeling

Dotted keys: `platform.system = ml-infra`, `platform.component = compute`,
`platform.managed-by = terragrunt`, plus `platform_labels` overrides.

## Testing

```bash
terraform init -backend=false
terraform test
```

Tests assert the driver-less wiring and that a `driver_enabled = true` attempt is rejected.
