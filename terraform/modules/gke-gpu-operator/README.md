# gke-gpu-operator

Deploys the **NVIDIA GPU Operator** on a **GKE Standard** cluster via `helm_release`,
toggleable and version-pinned. Part of **WS-A** of the GCP ML Platform. System:
`ml-infra`.

## What it creates

| Resource | Purpose |
|----------|---------|
| `kubernetes_namespace.gpu_operator` | Namespace for the operator, labeled per ADR-0028. |
| `helm_release.gpu_operator` | The NVIDIA GPU Operator chart (pinned version). |

Both are gated by `var.enabled`. Set `enabled = false` for clusters that rely solely
on the **GKE-managed GPU driver DaemonSet** instead of the operator.

## GKE defaults

On GKE Standard with COS, the container toolkit ships in the node image and the
kernel driver is provided by the GKE-managed driver DaemonSet, so:

- `driver_enabled = false`
- `toolkit_enabled = false`
- `dcgm_exporter_enabled = false` (DCGM is owned by `gke-gpu-dcgm`)

The operator then provides the device plugin, GPU Feature Discovery (GFD), Node
Feature Discovery (NFD) and CDI. Flip the driver/toolkit toggles for clusters where
the operator should own the full stack.

## ADR-0028 labeling

Kubernetes-plane labels use **dotted** keys. The namespace and operator workloads
carry: `platform.system = ml-infra`, `platform.component = compute`,
`platform.managed-by = terragrunt`, merged with any `platform_labels` overrides
(e.g. `platform.env`, `platform.owner`).

## Usage

```hcl
module "gpu_operator" {
  source = "../../terraform/modules/gke-gpu-operator"

  enabled       = true
  chart_version = "v24.9.2"

  gpu_node_selector = { "cloud.google.com/gke-accelerator" = "nvidia-l4" }

  platform_labels = {
    "platform.env"   = "production"
    "platform.owner" = "team-data"
  }
}
```

Requires `helm` and `kubernetes` providers configured against the target GKE cluster
(wired by the catalog unit via a generated provider override).

## Testing

```bash
terraform init -backend=false
terraform test
```

Tests mock the `helm` and `kubernetes` providers — no cluster or credentials needed.

## Network isolation (follow-up)

This module creates the `gpu-operator` namespace but does **not** ship a NetworkPolicy. The
EKS gpu-inference stack pairs every GPU namespace with a default-deny baseline plus
scoped allow rules (see `network-policies/gpu-inference/00-default-deny.yaml`). The
GKE side needs the same: a **default-deny CiliumNetworkPolicy** for `gpu-operator` plus
scoped-allow policies (DNS/kube-api, metrics scrape, and the specific peers this
component talks to).

This is **required** for parity and is **deferred to the GitOps / network-policies
layer** (Dataplane V2 / Cilium), not implemented in this Terraform module. Tracking
item for the network-policies workstream.
