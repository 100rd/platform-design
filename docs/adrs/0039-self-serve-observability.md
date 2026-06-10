# ADR-0039: Self-Serve Observability — Templated Grafana Folders, Dashboards, and Alert-Rules-as-Code

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — `apps/infra/grafana-self-serve/` introduced
  in this PR (templates + two sample teams); no Grafana folder provisioner or team
  PrometheusRules deployed yet.
- Date: 2026-06-10
- Authors: platform-team (devops-engineer)
- Related issues: WS-D "System & self-serve observability + team enablement" (GCP ML
  Platform plan §4 WS-D); ADR-0034 (Backstage — deferred); ADR-0026 (observability
  target architecture); ADR-0028 (mandatory platform taxonomy).
- Supersedes: (none)
- Superseded by: (none)

## Context

The platform has a mature **system observability layer**: Prometheus 3.x / Thanos,
Grafana, Loki, Tempo, Pyroscope, OTel Collector, Alertmanager → PagerDuty — all
in `apps/infra/observability/`. The existing `grafana-dashboards` Helm chart
(`apps/infra/observability/grafana-dashboards/`) ships **platform-owned** dashboards
(cluster-overview, node-health, karpenter, golden-signals, SLO, ML drift) as
ConfigMaps labelled `grafana_dashboard: "1"`, which the Grafana sidecar picks up
automatically.

What is entirely absent is a **per-team layer**: individual teams (ML platform,
checkout, data, SRE, etc.) have no way to:

1. Get a scoped Grafana folder visible only to their team.
2. Add their own service/workload dashboards without filing a platform ticket.
3. Define custom alert rules in a Prometheus namespace they own without touching
   the platform's `PrometheusRule` objects.

The consequence is every new team either duplicates platform dashboards, files
tickets, or goes dark on alerting — all of which create toil and observability
gaps. The WS-C ML observability work (ADR-0038) noted this gap in §D5
("per-team dashboard access control") as a follow-up.

### Why not Backstage?

[ADR-0034](0034-backstage-idp.md) put Backstage on hold pending three conditions:

1. A **dedicated Backstage owner** (engineer or team) assigned to operate the
   Node.js app, plugins, and catalog hygiene.
2. The **platform backlog matures** so the Golden Path Scaffolder can reference a
   stable, fully-implemented set of ADRs (currently many are `pending` in
   platform-design).
3. **≥3 teams actively onboarded** via golden-path templates from WS-F.

None of those three conditions are currently met. Deploying Backstage now —
without a dedicated owner — would produce an abandoned portal within months.
The GCP ML Platform implementation plan (§7 decision #5) explicitly recommends:
"ship lightweight self-serve in WS-D first; revisit Backstage when all three
conditions are met."

**Backstage remains deferred.** This ADR delivers the lightweight self-serve
layer that bridges the gap until Backstage's revisit criteria are satisfied.

## Decision

**Ship a lightweight, GitOps-delivered self-serve observability layer** based
entirely on the platform's existing patterns (ConfigMap sidecar, ArgoCD,
PrometheusRule CRD). No new operators are introduced.

The mechanism has four components:

### D1 — Per-team Grafana folder via ConfigMap provisioning

A ConfigMap labelled `grafana_dashboard: "1"` carries Grafana's folder
provisioning JSON. The Grafana sidecar picks it up and creates a folder named
`team-<slug>` in the Grafana org. Folder-level RBAC restricts Viewer access
to the team's Grafana service account or user group — other teams cannot browse
the folder.

### D2 — Starter dashboard ConfigMap (parameterised)

A second ConfigMap, also labelled `grafana_dashboard: "1"` with a
`grafana_folder` annotation pointing to `team-<slug>`, contains a starter
Grafana dashboard JSON. The dashboard is parameterised by `team.slug`,
`team.namespace`, and `team.system` (ADR-0028 `platform.system`) via Helm
values and covers:

| Panel row | Non-ML team | ML team (`ml.enabled: true`) |
|---|---|---|
| RED metrics — rate / errors / duration | yes | yes |
| Pod CPU + memory saturation | yes | yes |
| Active alert table (namespace-scoped) | yes | yes |
| ML drift score + model accuracy | no | yes (ADR-0038 metrics) |
| ML retrain trigger count | no | yes |

### D3 — Alert-rules-as-code (PrometheusRule per team)

A `PrometheusRule` in the team's workload namespace defines two starter alert
groups:

- `<team-slug>-availability` — fires when HTTP error rate exceeds 5% for 5 min.
- `<team-slug>-saturation` — fires when CPU or memory saturation exceeds 80% for
  15 min.

Alert names are prefixed with the team slug in UPPER_CASE to prevent
`alertname` collisions across teams (e.g. `CHECKOUT_HighErrorRate`).

Teams extend these rules by editing their own `PrometheusRule` in their namespace
without touching platform objects in the `monitoring` namespace.

### D4 — RBAC: Kubernetes + Grafana folder isolation

**Kubernetes layer:**

- A namespace-scoped `Role` grants the team `get/list/watch/create/update/
  delete` on `prometheusrules.monitoring.coreos.com` in their workload namespace
  only.
- A `RoleBinding` binds it to the team's CI service account (or developer
  group).
- The existing Kyverno `require-platform-labels` policy (ADR-0020) validates
  that `platform.owner` on resources in a namespace matches the namespace's own
  `platform.owner` label, preventing namespace escape via label forgery.

**Grafana layer:**

- Grafana's folder provisioning sets `permissions` on the team folder:
  `role: Viewer` for `team-<slug>` org users; `role: Editor` for the team's
  dedicated service account.
- Platform dashboards in the `Platform` folder remain read-only for all teams.

### D5 — Self-onboarding via template PR

A team wanting observability creates a PR adding two files under
`apps/infra/grafana-self-serve/example-teams/<team-slug>/`:

```
apps/infra/grafana-self-serve/example-teams/<team-slug>/
├── values.yaml            # team: {name, slug, namespace, system, owner}; ml: {enabled}
└── argocd-application.yaml
```

The platform reviewer confirms:
- `team.system` is a valid ADR-0028 system slug.
- `team.namespace` is an existing namespace.
- `team.owner` resolves to a real team slug.

On merge, ArgoCD deploys the chart into the team's namespace, producing:
- 1 × Grafana folder ConfigMap (sidecar-picked-up).
- 1 × Grafana dashboard ConfigMap (folder-scoped, sidecar-picked-up).
- 1 × PrometheusRule (availability + saturation starter rules; + ML groups
  when `ml.enabled: true`).
- 1 × Role + RoleBinding (scoped to team namespace).

### Backstage revisit conditions (cite from ADR-0034)

Backstage is explicitly kept deferred until **all three** of the following
conditions from ADR-0034 are satisfied:

1. **(a) GCP ML platform Phase-3 stable** — WS-A (GKE ML infra), WS-B (ML
   CI/CD + MLflow), and WS-C (ML observability) fully implemented and operating
   in production. "Phase-3 stable" means all three workstreams have passed
   their acceptance criteria and are apply-gated into production.
2. **(b) Dedicated IDP owner assigned** — a named engineer or team formally
   assigned to operate the Backstage Node.js app, manage plugin upgrades, and
   maintain catalog hygiene. No deployment until this is formal.
3. **(c) ≥3 teams actively onboarded** via golden-path templates from WS-F,
   validating that the scaffolder template covers real use-cases before
   committing to the Backstage operational surface.

When all three conditions are met, the template PR pattern established here maps
1:1 onto a Backstage scaffolder template — no rework required, only UX uplift.

### ADR-0028 label compliance

Every resource generated by the chart carries the five mandatory keys:

| Key (K8s label) | Value |
|---|---|
| `platform.system` | `observability` |
| `platform.component` | `dashboard` / `alert-rules` / `rbac` |
| `platform.env` | `{{ .Values.team.env }}` (required, no default) |
| `platform.owner` | `{{ .Values.team.slug }}` |
| `platform.managed-by` | `argocd` |

## Alternatives considered

### Alternative A: Grafana-Operator `GrafanaFolder` + `GrafanaDashboard` CRDs

Deploy the grafana-operator and use type-safe CRDs for folder and dashboard
management.

*Not chosen now because:* grafana-operator is not in the current stack. Adding
it solely for self-serve would introduce a new operator with its own upgrade
cycle when the existing ConfigMap sidecar pattern is already wired and working.
**Revisit if the platform adopts grafana-operator for other reasons.**

### Alternative B: Grafana HTTP API push (CI-driven)

A CI job calls `POST /api/folders` and `POST /api/dashboards/db` on PR merge.

*Rejected because:* it requires Grafana admin credentials in CI, breaks the
GitOps pull-model (ArgoCD cannot reconcile API-side state), and creates drift
between Git and Grafana. The ConfigMap sidecar is declarative and
ArgoCD-reconciled.

### Alternative C: Backstage golden-path scaffolder

Use Backstage's scaffolder to generate the template PR automatically.

*Rejected for now because:* Backstage is explicitly on hold (ADR-0034). Even
when live, the scaffolder output would be identical to the files this ADR
defines — the scaffolder is a UX layer, not the implementation. When Backstage
is eventually undeferred, the existing template PR becomes the scaffolder
template with zero rework.

### Alternative D: Status quo — file platform tickets

Teams continue requesting dashboards and alert rules via platform tickets.

*Rejected because:* this is the problem statement. Centrally-maintained
dashboards do not scale; platform ticket latency blocks team visibility.

### Alternative E: Per-team Grafana Organization

Create a separate Grafana Org per team.

*Rejected because:* Grafana multi-org is a legacy feature with significant
overhead (no cross-org dashboards, no shared platform datasource aliases,
separate session management). Grafana's recommended model since v8 is
folder-level RBAC within a single org.

## Consequences

### Positive

- **Zero new operators or infrastructure.** Reuses ConfigMap sidecar, ArgoCD,
  and PrometheusRule CRD — nothing new to operate.
- **Team autonomy without blast radius.** A broken alert expression in
  `team-checkout` cannot affect `monitoring`-namespace SLO rules or ML drift
  alerts.
- **ML + non-ML unified.** One template, `ml.enabled` flag gates ML panels.
- **Backstage-ready by construction.** Template PR pattern maps 1:1 onto a
  Backstage scaffolder template when ADR-0034 conditions are met.
- **ADR-0028 compliant by construction.** Missing required label values cause
  `helm lint` to fail.

### Negative

- **Grafana folder RBAC requires manual Grafana user/service-account setup.**
  Team Grafana users or service accounts must be pre-created in the Grafana
  org before folder permissions take effect. Documented in the runbook as a
  one-time step.
- **Dashboard JSON is Helm-templated.** Go template `{{ }}` syntax in JSON
  strings requires careful escaping. This is the same tradeoff already present
  in `configmap-dashboards.yaml`.
- **Second dashboard requires a PR.** Teams can edit their PrometheusRule
  freely, but adding a second dashboard still requires a PR. Intentional —
  keeps Git as the source of truth.

### Risks

- **Namespace escape via label forgery.** A team could label a PrometheusRule
  with `platform.system: monitoring` to attempt influence over scrape targets.
  *Mitigated by* the Kyverno `require-platform-labels` policy (ADR-0020),
  which validates `platform.owner` on resources matches the namespace label.
- **Grafana sidecar reloads on every ConfigMap change.** High-frequency merges
  trigger reloads. *Mitigated by* ArgoCD wave `"30"` (after all observability
  components at wave 10–20) and Grafana's idempotent sidecar behaviour.
- **Alert name collisions.** Two teams define `HighCPU` in different namespaces;
  both fire with the same `alertname`. *Mitigated by* prefixing all alert names
  with `{{ .Values.team.slug | upper }}_`.
- **Grafana folder permission provisioning not reconciled by ArgoCD.** Grafana
  folder permissions set via provisioning JSON are applied at sidecar reload but
  are not subsequently reconciled if changed in the Grafana UI. *Mitigated by*
  documentation in the runbook: "do not edit folder permissions in the Grafana
  UI — edit `values.yaml` and raise a PR."

## Implementation notes

This ADR introduces no new operators or cloud resources. The PR adds:

- `apps/infra/grafana-self-serve/` — Helm chart (`apiVersion: v2`,
  type `application`, wave `"30"`):
  - `Chart.yaml`, `values.yaml` (required fields, no defaults)
  - `templates/configmap-dashboard.yaml` — Grafana folder + starter dashboard
  - `templates/prometheusrule.yaml` — team PrometheusRule (availability +
    saturation; + ML groups behind `ml.enabled`)
  - `templates/rbac.yaml` — Role + RoleBinding
- `apps/infra/grafana-self-serve/example-teams/team-checkout/` — non-ML example
- `apps/infra/grafana-self-serve/example-teams/team-ml-platform/` — ML example
- `docs/self-serve-observability.md` — onboarding runbook
- This ADR + `docs/adrs/README.md` update (0039 row)

**Validation:** `helm lint` + `helm template` on the chart; `yamllint` on all
new YAML (`.yamllint.yml` config, max 200 lines warning); `kubeconform` on
rendered PrometheusRule and RBAC manifests.

**ArgoCD Application shape per team:**

```yaml
source:
  path: apps/infra/grafana-self-serve
  helm:
    valueFiles:
    - values.yaml
    - example-teams/<team-slug>/values.yaml
destination:
  namespace: <team.namespace>
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
  - CreateNamespace=false
```

**Rollback:** deleting a team's ArgoCD Application removes their dashboard
ConfigMap, PrometheusRule, and RBAC from the cluster. No side effects on
platform dashboards or other teams.

**Effort:** S — chart skeleton + two example teams + runbook. No new infra.

## Revisit trigger

- **When all three ADR-0034 revisit conditions are met**, promote the template
  PR pattern to a Backstage scaffolder template and link from ADR-0034 Phase 1
  scope.
- **If the platform adopts grafana-operator**, migrate ConfigMap-based folder
  provisioning to `GrafanaFolder`/`GrafanaDashboard` CRDs and update this ADR.
- **If >10 teams onboard**, evaluate an ApplicationSet generator over the
  `example-teams/` directory instead of per-team ArgoCD Applications.

## References

- Grafana dashboard provisioning (ConfigMap sidecar):
  <https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards>
- Grafana folder RBAC:
  <https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/access-control/>
- PrometheusRule CRD (prometheus-operator):
  <https://prometheus-operator.dev/docs/user-guides/alerting/>
- ADR-0034 (Backstage deferred — revisit criteria):
  [0034-backstage-idp.md](0034-backstage-idp.md)
- ADR-0028 (unified platform taxonomy — mandatory):
  [0028-unified-platform-tagging-and-labeling-taxonomy.md](0028-unified-platform-tagging-and-labeling-taxonomy.md)
- ADR-0026 (observability target architecture):
  [0026-observability-target-architecture.md](0026-observability-target-architecture.md)
- ADR-0038 (ML observability + drift metrics — feeds ML panel row):
  [0038-ml-observability-drift.md](0038-ml-observability-drift.md)
- ADR-0020 (Kyverno policy engine — label validation):
  [0020-kyverno-and-vap-policy-engine.md](0020-kyverno-and-vap-policy-engine.md)
- In-repo: `apps/infra/observability/grafana-dashboards/` (ConfigMap sidecar
  pattern reference); `apps/infra/observability/prometheus-stack/templates/
  prometheusrules/slo-rules.yaml` (PrometheusRule pattern reference)
- GCP ML Platform implementation plan §4 WS-D:
  `docs/gcp-ml-platform/IMPLEMENTATION_PLAN.md`

---
*Planning-only ADR — proposed, not yet implemented in platform-design.
WS-D "System & self-serve observability + team enablement"; implementation
apply-gated. Doc-verified 2026-06-10.*
