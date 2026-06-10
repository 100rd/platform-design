# gke-gpu-scheduling

Deploys a **batch / queueing scheduler** on a **GKE** cluster for GPU analysis
workloads. Defaults to **Volcano** (native gang scheduling); **Kueue** is selectable
as an alternative. Part of **WS-A** of the GCP ML Platform. System: `ml-infra`.

## Scheduler choice

**ADR-0036** selected **Volcano** as the WS-A batch scheduler — native gang
scheduling for distributed training, plus parity with the existing EKS
`gpu-inference-volcano` stack — so `scheduler` defaults to `volcano`. Set
`scheduler = "kueue"` to deploy Kueue (job-level queueing, quota and fair-sharing)
instead. Exactly one scheduler is installed; `enabled = false` falls back to the
default kube-scheduler.

## What it creates

| Resource | When |
|----------|------|
| `kubernetes_namespace.scheduling` | `enabled = true` |
| `helm_release.volcano` | `enabled && scheduler == "volcano"` (default) |
| `helm_release.kueue` | `enabled && scheduler == "kueue"` |

## Queue custom resources

`Queue` (Volcano) and `ClusterQueue` / `ResourceFlavor` / `LocalQueue` (Kueue) CRs
are **not** created here — they require `kubernetes_manifest`, which needs a live
cluster at plan time and would break mocked validation. They are applied by the
GitOps/ArgoCD layer after the CRDs exist. This module owns the controller install
plus namespace labeling.

## ADR-0028 labeling

Kubernetes-plane labels use **dotted** keys. The namespace and scheduler pods carry:
`platform.system = ml-infra`, `platform.component = scheduler`,
`platform.managed-by = terragrunt`, merged with any `platform_labels` overrides.

## Usage

```hcl
module "gpu_scheduling" {
  source = "../../terraform/modules/gke-gpu-scheduling"

  enabled   = true
  scheduler = "volcano"

  platform_labels = {
    "platform.env"   = "production"
    "platform.owner" = "team-data"
  }
}
```

## Testing

```bash
terraform init -backend=false
terraform test
```

Tests mock the `helm` and `kubernetes` providers — no cluster or credentials needed.

## Network isolation (follow-up)

This module creates the `gpu-batch-scheduling` namespace but does **not** ship a NetworkPolicy. The
EKS gpu-inference stack pairs every GPU namespace with a default-deny baseline plus
scoped allow rules (see `network-policies/gpu-inference/00-default-deny.yaml`). The
GKE side needs the same: a **default-deny CiliumNetworkPolicy** for `gpu-batch-scheduling` plus
scoped-allow policies (DNS/kube-api, metrics scrape, and the specific peers this
component talks to).

This is **required** for parity and is **deferred to the GitOps / network-policies
layer** (Dataplane V2 / Cilium), not implemented in this Terraform module. Tracking
item for the network-policies workstream.
