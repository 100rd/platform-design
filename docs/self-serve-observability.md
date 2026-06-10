# Self-Serve Observability — Onboarding Runbook

> **ADR reference:** [ADR-0039](adrs/0039-self-serve-observability.md)
> **Scope:** WS-D of the GCP ML Platform plan.
> **Backstage:** explicitly deferred — see ADR-0034 and the revisit conditions
> in ADR-0039 §D5.

This runbook explains how a team gets a scoped Grafana folder, a starter
dashboard, and a PrometheusRule in their workload namespace via a template PR.
No platform ticket required.

---

## What you get

After your PR merges, ArgoCD deploys four resources:

| Resource | Kind | Namespace |
|---|---|---|
| `<team-slug>-grafana-folder` | ConfigMap | `observability` (Grafana sidecar picks it up) |
| `<team-slug>-grafana-dashboard` | ConfigMap | `observability` (folder-scoped starter dashboard) |
| `<team-slug>-alerts` | PrometheusRule | Your workload namespace |
| `<team-slug>-prometheusrule-manager` | Role + RoleBinding | Your workload namespace |

The Grafana folder appears at **Dashboards > team-`<your-slug>`**. Only Grafana
users assigned to your team's folder can browse it. The PrometheusRule fires
through the existing Alertmanager path.

---

## Prerequisites

Before raising a PR:

1. **Namespace exists.** `CreateNamespace=false` — your workload namespace must
   already exist. If it does not, bootstrap it in a separate PR with ADR-0028
   labels on the Namespace object.

2. **`platform:system` value registered.** `team.system` must be a valid ADR-0028
   system slug already in use by your workloads. If it is new, define it in a
   separate PR first.

3. **(ML teams only) ADR-0038 ml-monitoring stack deployed.** ML panel rows
   query `ml_monitoring_*` metrics from `apps/infra/ml-monitoring/`. If that
   stack is not yet deployed, set `ml.enabled: false` initially and flip to
   `true` once it is.

4. **(Optional) Grafana service account pre-created.** If you want folder-level
   Editor access for a team service account, create it in the Grafana UI first,
   then set `team.grafanaServiceAccount` to its name in `values.yaml`. Leave
   the field empty to skip.

---

## Step-by-step: raise a template PR

### 1. Copy the example directory

```bash
cp -r apps/infra/grafana-self-serve/example-teams/team-checkout \
       apps/infra/grafana-self-serve/example-teams/<your-team-slug>
```

### 2. Edit `values.yaml`

Fill in every required field in
`apps/infra/grafana-self-serve/example-teams/<your-team-slug>/values.yaml`:

```yaml
team:
  name: "Your Team Name"
  slug: "team-your-slug"          # lowercase, hyphens only
  namespace: "your-namespace"     # must already exist
  system: "your-system"           # ADR-0028 platform:system value
  owner: "team-your-slug"
  env: "production"               # production | staging | dev | sandbox
  grafanaServiceAccount: ""       # optional — leave empty to skip
  ciServiceAccount: "your-ci-sa"  # optional — leave empty to skip RBAC
```

ML teams additionally set:

```yaml
ml:
  enabled: true
  modelName: "your-model-name"   # optional filter
  tenant: "your-tenant"          # optional filter
```

### 3. Edit `argocd-application.yaml`

Replace all `team-checkout` references with your slug:

```yaml
metadata:
  name: grafana-self-serve-<your-team-slug>
  labels:
    platform.owner: "<your-team-slug>"
spec:
  source:
    helm:
      valueFiles:
        - values.yaml
        - example-teams/<your-team-slug>/values.yaml
  destination:
    namespace: <your-namespace>
```

### 4. Validate locally (required before PR)

```bash
# Lint — checks template syntax + required value presence
helm lint apps/infra/grafana-self-serve \
  -f apps/infra/grafana-self-serve/example-teams/<your-team-slug>/values.yaml

# Template — render for visual inspection
helm template grafana-self-serve apps/infra/grafana-self-serve \
  -f apps/infra/grafana-self-serve/example-teams/<your-team-slug>/values.yaml \
  --namespace <your-namespace>

# yamllint — style check (max 200 chars/line per .yamllint.yml)
yamllint -c .yamllint.yml \
  apps/infra/grafana-self-serve/example-teams/<your-team-slug>/

# kubeconform — schema validation
helm template grafana-self-serve apps/infra/grafana-self-serve \
  -f apps/infra/grafana-self-serve/example-teams/<your-team-slug>/values.yaml \
  --namespace <your-namespace> \
  | kubeconform -strict -ignore-missing-schemas -
```

A clean run outputs:
```
==> Linting apps/infra/grafana-self-serve
1 chart(s) linted, 0 chart(s) failed
```

Fix all errors before raising the PR. CI runs the same checks.

### 5. Raise the PR

Suggested title: `feat: add self-serve observability for <your-team-slug>`

Include:
- Team slug and workload namespace.
- Confirmation the namespace pre-exists.
- `ml.enabled` status and, if true, which ADR-0038 deployment it targets.
- Paste the `helm lint` output (or "CI green").

### 6. Platform review checklist

The reviewer confirms:

- [ ] `team.system` is a valid ADR-0028 system slug.
- [ ] `team.namespace` exists in the cluster.
- [ ] `team.owner` matches a real team slug.
- [ ] `team.env` is one of `production`, `staging`, `dev`, `sandbox`.
- [ ] `helm lint` passes with the team's `values.yaml`.
- [ ] No resources target the `monitoring` namespace.
- [ ] (ML) `ml.enabled: true` only if `ml-monitoring` is deployed and metrics
  are flowing.

### 7. After merge

ArgoCD syncs at wave 30. Within ~60 seconds:

- Grafana sidecar reloads — dashboard appears at **Dashboards > team-`<slug>`**.
- PrometheusRule loads — verify:
  `kubectl get prometheusrule -n <your-namespace>`
- RBAC Role + RoleBinding created (if `ciServiceAccount` was set).

---

## What the team owns vs what the platform owns

| Resource | Owner | How to change |
|---|---|---|
| `<team-slug>-grafana-folder` ConfigMap | Platform (via template) | Edit `values.yaml`, raise PR |
| `<team-slug>-grafana-dashboard` ConfigMap | Platform (via template) | Edit `values.yaml`, raise PR |
| `<team-slug>-alerts` PrometheusRule | **Team** | Edit directly in your namespace (no PR needed for threshold changes); for structural changes raise a PR |
| Platform dashboards (`cluster-overview` etc.) | Platform only | Do not edit |
| Platform SLO rules in `monitoring` namespace | Platform only | Do not edit |

### Adding a second dashboard

Raise a PR adding a new ConfigMap in your namespace (or an additional values
key if the template is extended). The reviewer confirms it carries ADR-0028
labels and targets your team folder only.

### Modifying alert thresholds

Edit `alerts.*` in your `values.yaml` and raise a PR. Alternatively, if
`ciServiceAccount` is set, your CI service account can `kubectl patch` the
`PrometheusRule` directly for urgent threshold changes — bring Git back into
sync with your next PR.

---

## Grafana folder access

The starter dashboard is in folder `team-<your-slug>`. To grant team members
access:

1. In Grafana: **Administration > Teams** — create or use a team named
   `team-<your-slug>` and add members.
2. **Dashboards > Folders > team-`<your-slug>`** > **Folder settings** >
   **Permissions** — add the Grafana team with `Viewer` or `Editor`.

If `team.grafanaServiceAccount` was set, folder permissions for that service
account are provisioned automatically via the folder ConfigMap on sidecar reload.

Do not edit folder permissions in the Grafana UI if they were set via
provisioning — they will be overwritten on the next sidecar reload. Manage
them in `values.yaml`.

---

## ML teams: dashboard panel details

When `ml.enabled: true`, the starter dashboard gains a third row:

| Panel | PromQL metric | Source |
|---|---|---|
| ML Dataset Drift Score | `ml_monitoring_dataset_drift_score` | ADR-0038 whylogs profiler |
| Model Accuracy | `ml_monitoring_model_accuracy` | ADR-0038 Evidently drift-exporter |
| Retrain Triggers (per hour) | `ml_monitoring_retrain_triggers_total` | ADR-0038 retrain-trigger proxy |

All three panels respect `ml.modelName` and `ml.tenant` filters. Leave empty
to show all models/tenants in your namespace.

The PrometheusRule gains a third group `<team-slug>-ml-observability` with:

- `<PREFIX>_MLDriftDetected` (warning) — fires when drift score exceeds threshold.
- `<PREFIX>_MLAccuracyDegraded` (critical) — fires when accuracy drops below
  threshold.

These fire through team-labelled Alertmanager routing alongside — not instead
of — the platform-level ML alerts in `apps/infra/ml-monitoring/` (ADR-0038).

---

## Troubleshooting

### Dashboard not appearing in Grafana

1. `kubectl get configmap -n observability | grep <team-slug>`
2. Check Grafana sidecar logs:
   `kubectl logs -n observability deployment/grafana -c grafana-sc-dashboard`
3. Confirm label: `kubectl get configmap -n observability <team-slug>-grafana-dashboard -o yaml | grep grafana_dashboard`

### PrometheusRule not loading

1. `kubectl get prometheusrule -n <your-namespace>`
2. Check prometheus-operator:
   `kubectl logs -n monitoring deployment/prometheus-operator | grep <team-slug>`
3. Confirm label: `kubectl get prometheusrule -n <your-namespace> <team-slug>-alerts -o yaml | grep "prometheus: kube-prometheus"`

### ArgoCD Application stuck in OutOfSync

Check wave ordering — wave 30 waits for prometheus-stack (wave 10) and
ml-monitoring (wave 20) to complete. Run `helm template ... | kubeconform` to
rule out schema errors.

### ML panels show "No data"

1. Confirm `ml.enabled: true` and `apps/infra/ml-monitoring/` is deployed.
2. Explore in Grafana: `ml_monitoring_dataset_drift_score{namespace="<ns>"}`.
3. Verify `ml.modelName` and `ml.tenant` match actual metric label values
   (case-sensitive).

---

## Reference

- [ADR-0039](adrs/0039-self-serve-observability.md) — decision
- [ADR-0034](adrs/0034-backstage-idp.md) — Backstage deferred (revisit criteria)
- [ADR-0028](adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md) — mandatory platform taxonomy
- [ADR-0038](adrs/0038-ml-observability-drift.md) — ML observability (source of ML panel metrics)
- [ADR-0026](adrs/0026-observability-target-architecture.md) — observability target architecture
- Chart source: `apps/infra/grafana-self-serve/`
- Example teams: `apps/infra/grafana-self-serve/example-teams/`
