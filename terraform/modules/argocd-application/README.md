# `argocd-application` — generic ArgoCD Application wrapper

Renders a single **ArgoCD `Application`** (`argoproj.io/v1alpha1`) as a `kubernetes_manifest`
resource via the `hashicorp/kubernetes` provider. The Application points at a Helm chart in a
Git repository; the actual in-cluster workloads (Deployments, ServiceMonitors, PrometheusRules,
ExternalSecrets, …) are rendered by Helm and reconciled by ArgoCD — not by Terraform.

This is the **generic, reusable** Application wrapper. It is substrate-agnostic: bare-metal
(Talos) and cloud (EKS/GKE) catalog units can all source it. It was introduced to satisfy the
`catalog/units/baremetal-ml-monitoring` unit (WS-C), but the interface is intentionally generic
so other units can source it too.

## Why this module exists

The `baremetal-ml-monitoring` catalog unit (merged via PR #326) sources
`${get_repo_root()}/terraform/modules/argocd-application`, but that module directory did not
exist on `main` — so `terragrunt init/validate` of the unit errored. This module fills that gap
and conforms to the unit's `inputs` interface.

## Apply gate (mock / `never_apply`)

This is a **mock / emulation** repo. Cluster mutation is gated:

- `enabled` defaults to **`false`**. The Application resource is created with
  `count = var.enabled ? 1 : 0`, so a default `plan`/`validate` renders **nothing**.
- `automated_sync` defaults to **`false`** — no ArgoCD auto-sync without explicit human approval.
- CI/CD flips `enabled` to `true` only on `main` after merge, with human approval. **Never** run
  `terraform apply` / `argocd sync` from an agent or feature branch.

## ADR citations

- **ADR-0028 — Unified Platform Tagging and Labeling Taxonomy.** The five core taxonomy keys
  (`platform.system`, `platform.component`, `platform.env`, `platform.owner`,
  `platform.managed-by`) are applied as **Kubernetes labels** on the Application metadata.
  Catalog units pass the keys in underscore form (`platform_system`, …) because dotted keys are
  awkward in HCL map literals; this module normalizes them to the canonical dotted form. The
  `platform.cluster` extension key is also carried through. Labels propagate to the destination
  workload through the Helm chart's own templated metadata.
- **ADR-0038 — ML Observability (Drift Detection, Accuracy Monitoring, Retrain Trigger).** The
  first consumer is `baremetal-ml-monitoring`, which deploys the `ml-monitoring` Helm chart
  (Evidently/whylogs drift exporter) onto the Talos UK bare-metal cluster.
- **ADR-0049 — Bare-metal GPU K8s (Talos) foundation, multi-DC, UK-resident data** — provides
  the destination cluster context for the first consumer.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enabled` | `bool` | `false` | Apply gate. `false` ⇒ no resources rendered (plan/validate create nothing). |
| `app_name` | `string` | — | Application `metadata.name`. |
| `argocd_namespace` | `string` | `"argocd"` | Namespace where ArgoCD runs / the Application object lives. |
| `project` | `string` | `"default"` | ArgoCD AppProject (`spec.project`). |
| `repo_url` | `string` | — | Git repo URL of the chart/manifests (`spec.source.repoURL`). |
| `target_revision` | `string` | `"main"` | Git revision to track (`spec.source.targetRevision`). |
| `chart_path` | `string` | — | Path within the repo to the chart/manifests (`spec.source.path`). |
| `helm_value_files` | `list(string)` | `[]` | Helm values files (`spec.source.helm.valueFiles`). |
| `helm_set_values` | `map(string)` | `{}` | Helm parameter overrides (`spec.source.helm.parameters`). No secrets. |
| `destination_server` | `string` | `"https://kubernetes.default.svc"` | Target cluster API URL (`spec.destination.server`). |
| `destination_namespace` | `string` | — | Destination namespace (`spec.destination.namespace`). |
| `sync_wave` | `number` | `0` | Rendered as `argocd.argoproj.io/sync-wave` annotation. |
| `automated_sync` | `bool` | `false` | Enable `spec.syncPolicy.automated` (gated). |
| `auto_prune` | `bool` | `false` | Prune on auto-sync. |
| `self_heal` | `bool` | `false` | Self-heal drift on auto-sync. |
| `create_namespace` | `bool` | `true` | Add `CreateNamespace=true` to `syncOptions`. |
| `labels` | `map(string)` | `{}` | ADR-0028 taxonomy labels (underscore keys, normalized to dotted). |

## Outputs

| Name | Description |
|------|-------------|
| `application_name` | Application `metadata.name`. |
| `namespace` | ArgoCD namespace (`metadata.namespace`). |
| `destination_namespace` | Destination namespace in the target cluster. |
| `labels` | Normalized (dotted-key) taxonomy labels applied to the Application. |
| `enabled` | Whether the Application was actually rendered. |

Outputs are derived from inputs/locals (not the count-gated resource) so they resolve even when
`enabled = false`.

## Security

- **No secrets.** `helm_set_values` carries non-sensitive wiring only (e.g. an S3 bucket URI,
  an ExternalSecrets `secretStoreRef` *name*). Secret material is sourced in-cluster via the
  referenced secret store (Vault/ESO), never passed through Terraform variables or state.

## Usage (Terragrunt unit)

```hcl
terraform {
  source = "${get_repo_root()}/terraform/modules/argocd-application"
}

inputs = {
  app_name              = "ml-monitoring-baremetal"
  argocd_namespace      = "argocd"
  project               = "platform"
  repo_url              = "https://github.com/your-org/platform-infrastructure.git"
  target_revision       = "main"
  chart_path            = "apps/infra/ml-monitoring"
  helm_value_files      = ["values.yaml", "values-baremetal.yaml"]
  destination_server    = dependency.talos_cluster.outputs.cluster_endpoint
  destination_namespace = "ml-monitoring"
  sync_wave             = 20

  labels = {
    platform_system     = "ml-monitoring"
    platform_component  = "drift-exporter"
    platform_env        = "production"
    platform_owner      = "team-ml-platform"
    platform_managed_by = "argocd"
    platform_cluster    = "talos-uk-primary"
  }

  helm_set_values = {
    "driftExporter.referenceBucketUri"    = "s3://${dependency.baremetal_rook_ceph.outputs.rgw_bucket_name}"
    "externalSecrets.secretStoreRef.name" = "vault-cluster-secret-store"
  }
}
```

## Testing

`argocd-application.tftest.hcl` is a plan-command test with a mocked `kubernetes` provider. It
asserts: nothing renders when `enabled = false`; the Application renders as
`argoproj.io/v1alpha1` with the correct identity/destination/source when `enabled = true`; and
ADR-0028 labels are normalized to dotted K8s label keys with the sync-wave annotation applied.

```bash
terraform init -backend=false
terraform validate
terraform test
```
