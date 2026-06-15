# talos-gpu-nodepool

A **logical, fixed-capacity GPU node pool** over a set of bare-metal machines — the
bare-metal analogue of `gcp-gke-gpu-nodepools` **minus the autoscaler**. Part of **WS-A**
of the Bare-Metal ML Platform. System: `ml-infra`.

**ADRs:** [ADR-0049](../../../docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
(foundation), [ADR-0054](../../../docs/adrs/0054-baremetal-elasticity-node-lifecycle.md)
(elasticity / node lifecycle without a cloud autoscaler). ADR-0028 taxonomy labels.

## No cloud autoscaler (the load-bearing difference)

On owned hardware there is **no cloud API that conjures nodes in seconds** (ADR-0054). A
"new node" is a PXE/Talos **re-image**, minutes-to-hours. So this module does **not**
manage a `min/max` range — capacity is **fixed** and equals the length of `var.machines`.
The node-pool policy ConfigMap records `autoscaling = disabled` explicitly. Elasticity
comes from **workload** scale-to-zero (KEDA/HPA/Volcano), not node count.

## What it creates (when `enabled = true`)

| Resource | Purpose |
|----------|---------|
| `kubernetes_manifest.nodepool_policy` | A ConfigMap the GitOps layer reconciles — pool size, GPU taint, and ADR-0028 + GPU labels |
| `kubernetes_manifest.cluster_api_machine` | (gated) Cluster-API `Machine`/`MetalMachine` objects for re-image lifecycle |

The Cluster-API objects are **off by default** (`manage_cluster_api = false` → static
pre-provisioned pool). `cluster_api_infra_provider` defaults to **sidero** (Talos-native,
the ADR-0054 recommendation), with `metal3` selectable.

## Apply-gated

`var.enabled` defaults **false**; nothing reconciles real hardware. Manifests are
rendered against mocked providers at plan time — no live cluster read.

## ADR-0028 labeling

Dotted keys: `platform.system = ml-infra`, `platform.component = gpu-nodepool`, plus
`platform_labels` overrides; nodes also carry `nvidia.com/gpu.present`,
`node.kubernetes.io/gpu-pool`, and `gpu.platform/model`.

## Testing

```bash
terraform init -backend=false
terraform test
```

Mocks the `kubernetes` provider — asserts the fixed-capacity (no-autoscaler) intent, the
GPU taint/labels, and the gated Cluster-API re-image path.
