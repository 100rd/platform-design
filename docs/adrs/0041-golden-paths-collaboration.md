# ADR-0041: Golden-path templates, shared contracts, and cross-team collaboration model

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — `templates/golden-paths/` directory introduced by
  this ADR; no Backstage scaffolder installed; golden paths delivered as template directories
  + onboarding docs.
- Date: 2026-06-10
- Authors: platform-team (devops-engineer)
- Related issues: WS-F "Collaboration / golden paths" (GCP ML Platform plan §4 WS-F);
  plan readiness row 4 ("Collaboration — golden paths + shared contracts + IDP missing");
  ADR-0034 (Backstage — deferred); ADR-0037 (WS-B ML CI/CD + MLflow); ADR-0038 (WS-C
  drift/accuracy monitoring); ADR-0039 (WS-D self-serve observability).
- Supersedes: (none)
- Superseded by: (none)

## Context

The GCP ML Platform implementation plan (§2, row 4) identifies a partial gap in the
**collaboration layer**: Grafana dashboards exist, but golden paths, shared API/data
contracts, and a cross-team IDP are missing.

Four workstreams (WS-A..E) have now delivered their platform artifacts:

| Workstream | Key artifact | WS-F consumes |
|-----------|-------------|---------------|
| WS-B (ADR-0037) | `.github/workflows/ml-pipeline.yml`, `apps/infra/airflow/` (4 DAGs), `apps/infra/mlflow/` | Train→eval→register→deploy pipeline that golden paths must wire new models into |
| WS-C (ADR-0038) | `apps/infra/ml-monitoring/` (Evidently drift-exporter, whylogs profiler, `retrain-trigger`, PrometheusRule) | Drift/accuracy metrics + retrain webhook that every model service must expose |
| WS-D (ADR-0039) | `apps/infra/grafana-self-serve/` (per-team Grafana folder + dashboard + alert-rules, ConfigMap-sidecar) | Self-serve observability surface that every new team/service must provision |

Three concrete problems remain unsolved:

1. **No standard starting point for a new model service.** A new model takes weeks to
   integrate manually because there is no reference that shows how to wire
   `ml-pipeline.yml` + MLflow registration + Evidently drift-exporter + grafana-self-serve
   in one place. Each team re-invents the same glue.

2. **No shared API/data contract.** ML engineers define model request/response schemas
   ad-hoc. Backend and frontend teams discover mismatches at integration time. There is
   no single authoritative spec that all four personas (data, ML, backend, frontend) sign
   off on before code is written.

3. **No RACI or handoff protocol.** The production model lifecycle touches four personas
   with overlapping responsibilities. Without an explicit RACI, gaps (who triggers a
   retrain? who owns a drift alert?) and overlaps (duplicate dashboards, conflicting
   alert thresholds) are inevitable.

### Why template directories, not a Backstage scaffolder?

[ADR-0034](0034-backstage-idp.md) deferred Backstage pending three conditions:

1. A dedicated Backstage owner is assigned.
2. The platform backlog matures (many ADRs still `pending`).
3. Three or more teams are actively onboarded via golden-path templates from this
   WS-F iteration.

Condition 3 creates a bootstrapping dependency: the WS-F golden paths must exist and
prove value before Backstage's revisit criteria can be met. Implementing golden paths
as Backstage scaffolders now — without a dedicated owner — would leave them abandoned.

The implementation plan (§7 #5) recommends: "ship lightweight self-serve in WS-D first;
revisit Backstage when all three conditions are met." The same logic applies to WS-F:
ship template directories first, map them onto Backstage scaffolders later.

**Chosen approach:** every golden path is a directory under `templates/golden-paths/`
containing templated files with clearly marked `{{UPPER_SNAKE_CASE}}` substitution
points, a `README.md` onboarding guide, and an `argocd-application.yaml` stub. The
directory structure is explicitly designed to map 1:1 onto a Backstage Software Template
when ADR-0034 is revisited.

### ADR-0028 mandate

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) requires
`platform.system` / `platform.component` / `platform.env` / `platform.owner` /
`platform.managed-by` labels on every Kubernetes resource and the equivalent tags on
every cloud resource. All template files in this ADR carry these labels as substitutable
placeholders. `platform.system` defaults to `ml-pipeline` for model-service and pipeline
templates (per ADR-0037 §D) and `observability` for dashboard templates (per ADR-0039 §D).

## Decision

### D1 — Template-directory golden paths (three paths)

Deliver three golden paths as `templates/golden-paths/{path-name}/` directories:

| Path | Template directory | Purpose |
|------|--------------------|---------|
| **new-model-service** | `templates/golden-paths/new-model-service/` | New model pre-wired to ml-pipeline.yml, MLflow, WS-C drift-exporter, WS-D dashboard |
| **new-ml-pipeline** | `templates/golden-paths/new-ml-pipeline/` | New Airflow DAG mirroring WS-B DAG shape + MLflow registration + drift metric emission |
| **new-dashboard** | `templates/golden-paths/new-dashboard/` | New team grafana-self-serve values (re-uses WS-D chart); onboards a new team in one PR |

Each template directory contains:

- `README.md` — human-readable onboarding guide with a numbered checklist, copy-paste
  commands, and links to the underlying WS-B/C/D artifacts.
- One or more templated files with `{{UPPER_SNAKE_CASE}}` placeholders (never live
  values, never secrets).
- An `argocd-application.yaml` stub pre-filled with the correct chart path, wave
  annotation, and ADR-0028 labels.
- An explicit mapping to the corresponding Backstage Software Template fields so
  migration is mechanical when ADR-0034 is revisited.

### D2 — Shared API/data contracts (`docs/contracts/`)

Publish a canonical contract specification at `docs/contracts/` covering:

- **`model-api-contract.md`** — model request/response schema (OpenAPI-compatible
  JSON Schema fragments) + feature schema, versioning policy, and a worked example.
- **`example-domain-adapter-contract.yaml`** — a concrete YAML instance of the contract
  for the `domain-adapter` model family, suitable for use in CI contract tests.

All four engineering personas (data, ML, backend, frontend) are expected to read and
sign off on the contract before a new model service is promoted beyond staging.
The contract file lives in the repo so it is version-controlled and reviewable via PR.

### D3 — RACI and handoff protocol (`docs/golden-paths/RACI-and-handoffs.md`)

Document the production model lifecycle as:

1. A **RACI matrix** mapping five lifecycle activities (feature pipeline, model training,
   drift monitoring, serving/API, incident response) to four personas (Data Engineering,
   ML Engineering, Backend/Frontend, Platform/SRE) with explicit R/A/C/I assignments.
2. A **handoff flow** (Mermaid-compatible text diagram) showing the artifact hand-off
   sequence from raw data → trained adapter → registered model → deployed service →
   monitored production, including WS-B/C/D system boundaries.
3. An **on-call and escalation table** (supplement to ADR-0040 ML-incident runbooks)
   recording who gets paged first per alert class and what the first-response action is.

### D4 — Backstage migration path

Each template directory README includes a "Backstage future mapping" section recording:

- Backstage Software Template `spec.type` mapping.
- Which `parameters` blocks map to which `{{PLACEHOLDER}}` values.
- Which `steps` blocks (fetch template, publish, register catalog entity) are needed.

This makes the migration to a Backstage scaffolder a mechanical transformation rather
than a redesign.

## Alternatives considered

### A1 — Implement golden paths as Backstage scaffolders immediately

Deploy Backstage (reversing ADR-0034 deferral) and implement WS-F as Software Templates.

*Rejected because:* ADR-0034 deferral conditions are not met (no dedicated owner, many
ADRs still `pending`). A Backstage deployment without an owner degrades within months.
ADR-0039 successfully shipped lightweight WS-D self-serve without Backstage, proving
the template-directory pattern is sufficient.

### A2 — Reuse an existing open-source golden-path framework (Cookiecutter/Copier)

Use a templating engine to generate golden-path scaffolds.

*Partially adopted, rejected as a mandatory dependency:* the `{{PLACEHOLDER}}`
convention used here is intentionally compatible with both `envsubst`-style substitution
and Copier/Cookiecutter config. However, adding a Python/Go CLI dependency to the
developer workflow without a dedicated owner creates a new failure mode. Template
directories with documented `envsubst` substitution are simpler and sufficient.

### A3 — Inline the contracts into the ADRs

Document model API contracts inside each ADR rather than in `docs/contracts/`.

*Rejected because:* ADRs are decision records, not living specifications. Contracts
must be updated as the API evolves without creating new ADRs; a versioned file in
`docs/contracts/` is the correct artifact for a living spec.

### A4 — Status quo (no golden paths, no contracts, no RACI)

Continue with ad-hoc onboarding and per-team schema definitions.

*Rejected because:* this is exactly the gap identified in the implementation plan (§2,
row 4). Repeated manual integration cost and integration-time mismatches are documented
failure modes.

## Consequences

### Positive

- A new model team can onboard end-to-end (training pipeline + drift monitoring +
  dashboard + serving contract) from a single starting point rather than reading five
  separate ADRs and four separate `values.yaml` files.
- Shared contracts surface schema mismatches before code is written, not at integration
  time.
- RACI eliminates the "who owns drift alerts?" ambiguity.
- Template directories require no new operators and no new infra; they are checked-in
  docs with zero runtime footprint.
- `platform.system = ml-pipeline` (model/pipeline templates) and `platform.system =
  observability` (dashboard template) are pre-populated in every stub, satisfying the
  ADR-0028 OPA gate from day one.

### Negative

- Template files require manual `envsubst`/`sed` substitution until Backstage is
  available. A numbered checklist in each README reduces substitution errors.
- Three template directories add maintenance surface. Changes to WS-B/C/D artifacts
  require updating the corresponding template.

### Risks

- **Template drift:** if WS-B/C/D charts evolve and templates are not updated, teams
  hit integration errors. Mitigation: each template README records the WS-B/C/D chart
  versions it was verified against; CI yamllint + kubeconform validate template YAML
  on every PR.
- **Contract adoption:** teams may bypass the contract review step. Mitigation: the
  RACI assigns contract sign-off as a blocking pre-condition before staging promotion.
- **Backstage deferral indefinite:** if ADR-0034 revisit criteria are never met, the
  template-directory approach becomes permanent. Mitigation: the revisit criteria are
  tied to observable milestones in the implementation plan (Phase-3 GCP ML stable).

## Implementation notes

### Files created by this ADR

| File | Purpose |
|------|---------|
| `docs/adrs/0041-golden-paths-collaboration.md` | This ADR |
| `templates/golden-paths/new-model-service/README.md` | Onboarding guide |
| `templates/golden-paths/new-model-service/values-grafana-self-serve.yaml` | WS-D values |
| `templates/golden-paths/new-model-service/values-ml-monitoring.yaml` | WS-C values |
| `templates/golden-paths/new-model-service/ml-pipeline-trigger.yaml` | Pipeline dispatch example |
| `templates/golden-paths/new-model-service/argocd-application.yaml` | ArgoCD stub |
| `templates/golden-paths/new-ml-pipeline/README.md` | Onboarding guide |
| `templates/golden-paths/new-ml-pipeline/dag_template.py` | Airflow DAG scaffold |
| `templates/golden-paths/new-ml-pipeline/argocd-application.yaml` | ArgoCD stub |
| `templates/golden-paths/new-dashboard/README.md` | Onboarding guide |
| `templates/golden-paths/new-dashboard/values.yaml` | grafana-self-serve values template |
| `templates/golden-paths/new-dashboard/argocd-application.yaml` | ArgoCD stub |
| `docs/contracts/model-api-contract.md` | Model request/response + feature schema spec |
| `docs/contracts/example-domain-adapter-contract.yaml` | Concrete contract example |
| `docs/golden-paths/RACI-and-handoffs.md` | RACI matrix + handoff flow |

### Backstage future mapping

When ADR-0034 is revisited, each golden path maps to a Backstage Software Template:

| Template directory | Backstage `spec.type` | Key `parameters` |
|--------------------|-----------------------|------------------|
| `new-model-service` | `model-service` | `modelName`, `tenant`, `domain`, `teamSlug`, `namespace` |
| `new-ml-pipeline` | `ml-pipeline` | `dagName`, `modelName`, `tenant`, `domain` |
| `new-dashboard` | `team-dashboard` | `teamName`, `teamSlug`, `namespace`, `system` |

### Rollback

Template directories are documentation artefacts with no deployment. If a template
produces a broken resource, the team's PR fails CI before merge.

## References

- [ADR-0034](0034-backstage-idp.md) — Backstage deferred
- [ADR-0037](0037-ml-cicd-pipeline-mlflow.md) — WS-B ML CI/CD + MLflow
- [ADR-0038](0038-ml-observability-drift.md) — WS-C drift/accuracy monitoring
- [ADR-0039](0039-self-serve-observability.md) — WS-D self-serve observability
- [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) — Platform taxonomy
- [ADR-0040](0040-soc-posture-and-oncall.md) — WS-E SOC posture + ML on-call runbooks
- In-repo: `docs/gcp-ml-platform/IMPLEMENTATION_PLAN.md` §4 WS-F and §7 #5
- In-repo: `apps/infra/grafana-self-serve/values.yaml` (WS-D chart values reference)
- In-repo: `apps/infra/ml-monitoring/values.yaml` (WS-C chart values reference)
- In-repo: `.github/workflows/ml-pipeline.yml` (WS-B pipeline reference)
- In-repo: `apps/infra/airflow/dags/` (WS-B DAG scaffolds)
- CNCF Backstage Software Templates: <https://backstage.io/docs/features/software-templates/>

---
*Planning-only ADR — proposed, not yet implemented. WS-F "Collaboration / golden paths";
implementation apply-gated. Design 2026-06-10.*
