# SPEC-04 — Delivery & GitOps Machinery

> Reverse-engineered, portable blueprint for the continuous-delivery layer: ArgoCD (app-of-apps +
> ApplicationSets), Kargo environment promotion, and the Helm/Kustomize/golden-path conventions that
> feed them. A competent platform team can rebuild this delivery plane for a new client from this
> spec alone. Placeholders follow `SPEC-00-overview.md`; spec-local placeholders are registered in
> §5.

---

## 1. Scope & non-goals

**Scope.** This spec covers *how declarative desired state in Git becomes running workloads across a
fleet of Kubernetes clusters, and how a change moves from `dev` to `prod`*. Concretely: the ArgoCD
bootstrap-from-zero sequence (cluster exists → ArgoCD installed via Terragrunt → root Application →
ApplicationSets → waves); the ApplicationSet topology (infra, role-apps, observability,
multi-cluster infra, platform-workloads, GPU-inference); the ArgoCD `AppProject` and RBAC boundary;
the Kargo `Warehouse → Stage → Freight` promotion graph with metric-gated verification; the generic
`helm/app` chart and its Deployment-vs-Rollout / PreSync-migration behaviours; the `apps/`,
`envs/`, `templates/golden-paths/` conventions; and drift/rollback handling.

**Non-goals.** Cluster/networking provisioning (SPEC covering EKS/Talos foundations), the observability
backend that *produces* the promotion-gate metrics (Tempo/Prometheus RED metrics — a dependency, not a
deliverable here), the CI pipelines that *build and push* images and open GitOps PRs (SPEC covering
CI/supply-chain), and secret material itself. Secret **delivery** is described only at the boundary
(how ArgoCD/Helm reference an `ExternalSecret`); the secret backend, `ClusterSecretStore`, and IRSA
wiring live in **SPEC-05 (secrets)**.

---

## 2. Architecture

### 2.1 Component overview

```
                          ┌──────────────────────────────────────────────┐
   Terragrunt (SPEC-02)   │  cluster exists (EKS / Talos)                 │
   installs ArgoCD via    │  platform-crds unit ── ArgoCD unit (Helm)     │
   Helm, then applies ────┼──►  argocd/bootstrap/root-app.yaml            │
   the root Application    └───────────────────┬──────────────────────────┘
                                               │  (app-of-apps root)
                          ┌────────────────────▼───────────────────────────┐
                          │  Application: bootstrap → path argocd/bootstrap │
                          │  (Kustomization lists the ApplicationSets)      │
                          └────────────────────┬───────────────────────────┘
        ┌───────────────────────┬──────────────┼───────────────────┬─────────────────────┐
        ▼                       ▼              ▼                   ▼                     ▼
  infra-appset          role-apps-appset  observability-appset  multicluster-infra-appset
  apps/infra/*          apps/cluster-     apps/infra/           apps/infra/*  (region-aware
  → ALL clusters        roles/<role>/*    observability/*       values, RollingSync by env)
  (git-dir × clusters)  → clusters by     → ALL clusters
                        cluster-role      (sync-wave 5)
                        (RollingSync by env)

  ── second delivery family (Helm + Kargo, top-level argocd/*.yaml) ─────────────────────
  platform-infra           platform-workloads          gpu-inference-infra
  (Helm apps/infra/*        (helm/app × 5 teams × 4     (apps/infra/* to
   with envs/ values)        envs, Kargo-driven tags)    cluster-type=gpu-inference)
                                   ▲
                                   │ argocd-update
                     ┌─────────────┴───────────────┐
                     │  Kargo (kargo-config App)    │
                     │  Warehouse → Stage → Freight │
                     │  dev→integration→staging→prod│
                     └──────────────────────────────┘
```

### 2.2 Two ApplicationSet families (important)

The estate contains **two overlapping delivery generations** that coexist:

| Family | Files | Render engine | Env overlays | Delivered by |
|---|---|---|---|---|
| **A — bootstrap** | `argocd/bootstrap/applicationsets/{infra,role-apps,observability,multicluster-infra}-appset.yaml` | plain manifests + Kustomize overlays (`argocd/overlays/<role>-<env>/`) | Kustomize | `root-app` → `argocd/bootstrap` Kustomization |
| **B — workloads/Helm** | `argocd/applicationset.yaml` (platform-infra), `applicationset-workloads.yaml`, `applicationset-multicluster.yaml`, `applicationset-gpu-inference.yaml`, `appproject-workloads.yaml`, `kargo-bootstrap.yaml` | `helm/app` chart + `envs/<env>/values/**` | Helm value files | **not** listed in the bootstrap Kustomization — see §7 pitfall P1 |

Family A uses the `cluster-role` label + `apps/cluster-roles/<role>` + Kustomize overlays. Family B
uses the generic `helm/app` chart, per-env Helm values, and Kargo image promotion. A rebuild should
pick **one** family as canonical; this spec documents both because both are live in source.

### 2.3 The promotion plane (Kargo)

Kargo sits **above** ArgoCD: it advances a *Freight* (an immutable image-digest + git bundle) through
an ordered `Stage` graph and, at each stage, edits the GitOps repo (image tag/digest in
`envs/<env>/values/<team>/values.yaml` and `versions/<env>/versions.yaml`) then calls `argocd-update`.
ArgoCD then reconciles the change. There is **no Argo Rollouts controller deployed** in this estate,
so Kargo promotes ArgoCD `Application`s *directly* (not canaries-within-an-environment). The
`helm/app` chart *ships* Rollout machinery (§4.6) as a design-target toggle.

```
Warehouse (watches ECR digest + git path)
   │  new Freight
   ▼
Stage: dev ─auto─► integration ─auto─► staging ─gate─► prod (manual, digest-pinned)
        │             │                   │              │
   health-check   +integration-test  +prometheus     +prometheus 5xx+p95
                                      5xx+p95          +smoke+integration
```

---

## 3. Decision record

| Decision | Rationale | Trade-off accepted | Source ADR |
|---|---|---|---|
| **ArgoCD** for all K8s delivery, app-of-apps layout | Continuous reconciliation + self-heal + a UI load-bearing for multi-team self-service; sync waves order deploys without external orchestration | Another on-cluster component to operate/upgrade; ArgoCD does not manage encrypted secrets (pushed to ESO) | `ADR-0006 ArgoCD for GitOps` |
| **ApplicationSet cluster-generator selects on a `cluster-role` label** | One AppSet definition fans out across the clusters×git matrix; label is a cluster *identity* claim distinct from account name (`env`) | An intentional mismatch (account "shared" vs role "platform") must be documented so nobody "fixes" it | `ADR-0012 cluster_role label scheme` |
| **Kargo** as the environment-promotion layer, pinned to GA (chart wraps upstream `~1.9`) | Explicit, auditable `Warehouse→Stage→Freight` promotion; metric-gated instead of one-shot job probes; reuses the already-authored 5×4 graph | Another control-plane component; gates now depend on the Tempo RED-metrics feed being live | `ADR-0021 Kargo promotion layer` |
| **Enable four ArgoCD 3.3.6 capabilities with no upgrade**: PreDelete hooks, shallow clone, server-side diff/apply, ApplicationSet RollingSync | All ship on the running version; kill spurious `OutOfSync`, cut repo-server memory, order teardown, add a dev→prod soak gradient | Four behaviours to configure/validate; SSA changes field-ownership semantics teams must learn | `ADR-0024 ArgoCD operational hardening` |
| **Argo Rollouts canary** machinery lives in the shared `helm/app` chart (Gateway-API traffic plugin + analysis), gated behind `rollout.enabled` | Progressive delivery available per-service without diverging pod specs; default `Deployment` stays backward-compatible | Rollouts controller is *not* deployed here — the block is a design-target toggle, not wired in | `ADR-0014 Argo Rollouts canary` |
| **DB migrations via an ArgoCD PreSync Job**, not per-pod init containers | Runs exactly once per sync, before Sync-phase resources, with a clean pass/fail signal; old replicas keep serving on failure | Schema *rollback* is not automated (use expand/contract) | `ADR-0032 DB migrations via PreSync Jobs` |
| **Secrets delivered out-of-band via External Secrets Operator**, referenced (never embedded) by charts | ArgoCD/Git never holds plaintext; `ExternalSecret` pulls from AWS Secrets Manager/Parameter Store at runtime | ESO is a delivery dependency; IRSA binding must exist first | `ADR-0008 External Secrets Operator` (detail in SPEC-05) |
| **Unified `platform.*` taxonomy labels** stamped by every AppSet and rendered resource | One label join powers Grafana, Cilium policy, OpenCost, Velero, Trivy across compute + cloud resources | Chart *fails render* if `platform.system/component/owner` are empty (intentional CI gate) | `ADR-0028 unified tagging taxonomy` |
| **Golden-path template directories** (no Backstage scaffolder) for new dashboards/model-services/pipelines/tenants | Copy-substitute-commit onboarding without standing up an IDP; lives in Git next to what it deploys | Manual placeholder substitution; ADR still *Proposed* (apply-gated) | `ADR-0041 golden-paths collaboration` |

---

## 4. Implementation blueprint

### 4.1 Directory layout (delivery-relevant subtrees)

```
argocd/
├── bootstrap/                          # FAMILY A — delivered by root-app
│   ├── root-app.yaml                   # the single Application ArgoCD is pointed at
│   ├── kustomization.yaml              # lists the 4 bootstrap AppSets + ../config
│   ├── applicationsets/
│   │   ├── infra-appset.yaml           # apps/infra/* → ALL clusters (excl. observability)
│   │   ├── role-apps-appset.yaml       # apps/cluster-roles/<role>/* → clusters by label, RollingSync
│   │   ├── observability-appset.yaml   # apps/infra/observability/* → ALL clusters
│   │   └── multicluster-infra-appset.yaml  # infra → clusters with a region label, region-aware
│   └── cluster-secrets/                # ArgoCD cluster registration Secrets (templates)
│       ├── in-cluster-template.yaml
│       └── staging-euc1.yaml / staging-euw1.yaml
├── config/argocd-cmd-params-cm.yaml    # ADR-0024: server-side diff + shallow clone
├── applicationset.yaml                 # FAMILY B — platform-infra (Helm, envs/ values)
├── applicationset-workloads.yaml       # FAMILY B — 5 teams × 4 envs, Kargo-driven
├── applicationset-multicluster.yaml    # FAMILY B — active-active staging, region-aware
├── applicationset-gpu-inference.yaml   # FAMILY B — cluster-type=gpu-inference only
├── appproject-workloads.yaml           # AppProject: RBAC/namespace/resource allowlist
├── kargo-bootstrap.yaml                # Application that syncs kargo/ (recurse)
├── cluster-envs/{base,dev,stage,integration,prod}/   # Kustomize env bases (commonLabels)
├── overlays/<role>-<env>/              # 20 role×env Kustomize overlays (Family A)
└── workloads/<team>/<env>.yaml         # explicit per-app Applications (legacy, pre-AppSet)

kargo/
├── projects/<project>.yaml             # Project + promotionPolicies (auto vs manual per stage)
├── warehouses/<project>.yaml           # image (ECR) + git subscriptions
├── stages/<project>/{dev,integration,staging,prod}.yaml   # promotion steps + verification
└── analysis-templates/                 # health-check, smoke, integration, prometheus 5xx/p95

helm/app/                               # the ONE generic application chart (v0.4.0)
├── Chart.yaml  values.yaml  README.md
└── templates/{deployment,rollout,service,service-canary,hpa,pdb,httproute,
              externalsecret,migration-job,analysistemplate,servicemonitor,...}.yaml

apps/                                   # delivered manifests / Helm value roots
├── infra/<component>/                  # shared infra charts (cilium, cert-manager, kargo, …)
├── cluster-roles/<role>/<app>/         # role-scoped apps (backend, dex, listeners, velocity, 3rd-party)
├── chains/ listeners/ mono/ protocols/ direct/   # per-team workload manifests / values
└── direct/hello-world/helmrelease.yaml # smallest reference app

envs/<env>/values/{infra,<team>}/*.yaml # per-environment Helm value overrides (Kargo writes here)
versions/<env>/versions.yaml            # human-readable version manifest (Kargo writes here)
templates/golden-paths/<path>/          # copy-substitute-commit onboarding templates
catalog/units/argocd/terragrunt.hcl     # how ArgoCD itself is installed (bootstrap-from-zero)
```

### 4.2 Bootstrap-from-zero ordering (what must exist before what)

1. **Cluster exists.** EKS (or Talos) is provisioned by Terragrunt (SPEC-02). The ArgoCD unit
   `dependency`s on `eks` and `platform-crds`.
2. **CRDs first.** A `platform-crds` unit pre-installs CRDs (ArgoCD, Kargo, Gateway API, ESO,
   monitoring) so Helm-managed CRDs never race with Applications that consume them.
3. **ArgoCD installed by Terragrunt/Helm** — *not* by ArgoCD itself (chicken-and-egg). The
   `catalog/units/argocd` unit renders `helm`/`kubernetes` providers with an `aws eks get-token`
   exec auth and applies the ArgoCD chart:

   ```hcl
   # catalog/units/argocd/terragrunt.hcl  (sanitized)
   terraform { source = "${get_repo_root()}/.../terraform/modules/argocd" }
   dependency "eks"           { config_path = "../eks" }
   dependency "platform_crds" { config_path = "../platform-crds" }   # CRDs before ArgoCD
   inputs = {
     chart_version = try(local.account_vars.locals.argocd_chart_version, null)
     ha_enabled    = try(..., local.environment == "prod")   # HA only in prod
     enable_dex    = try(..., false)
   }
   ```
   ArgoCD here is **3.3.6 (chart 9.5.1)**; `application.namespaces` is set at chart level.
4. **Root Application applied.** Terragrunt (or a one-shot `kubectl apply`) creates
   `argocd/bootstrap/root-app.yaml` — the *only* object pointed at by hand. It is self-managed
   thereafter (`selfHeal`, `prune`):

   ```yaml
   # argocd/bootstrap/root-app.yaml (sanitized)
   kind: Application            # name: bootstrap, namespace: argocd
   spec:
     source: { repoURL: git@github.com:{{VCS_ORG}}/{{GITOPS_REPO}}.git, targetRevision: HEAD, path: argocd/bootstrap }
     destination: { server: https://kubernetes.default.svc, namespace: argocd }
     syncPolicy:
       automated: { prune: true, selfHeal: true }
       syncOptions: [CreateNamespace=true, ServerSideApply=true]
       retry: { limit: 3, backoff: { duration: 5s, factor: 2, maxDuration: 3m } }
   ```
5. **Bootstrap Kustomization fans out.** `argocd/bootstrap/kustomization.yaml` lists the four
   Family-A ApplicationSets **and** `../config` (the ADR-0024 params ConfigMap). Applying it creates
   the AppSets, which enumerate `apps/**` × registered cluster secrets and generate child
   Applications.
6. **Cluster registration.** Each managed cluster is registered as an ArgoCD cluster `Secret`
   (`argocd.argoproj.io/secret-type: cluster`) carrying the routing labels (§4.3). The local cluster
   uses `in-cluster-template.yaml`; remote clusters use per-region secrets.
7. **Waves reconcile in order.** Within a sync, `argocd.argoproj.io/sync-wave` orders resources
   (CRDs/PreDelete < migrations wave `-1` < workloads; observability trace-lane uses waves 10→15→20).
   RollingSync (§4.4) then soaks `dev → stage/integration → prod`.
8. **Kargo activated (Family B).** `kargo-bootstrap.yaml` + `appproject-workloads.yaml` +
   `applicationset-workloads.yaml` bring up the promotion plane; the `kargo-config` Application syncs
   the whole `kargo/` tree recursively.

### 4.3 Cluster label contract (the selector that drives everything)

Every ArgoCD cluster `Secret` MUST carry:

```yaml
metadata:
  labels:
    argocd.argoproj.io/secret-type: cluster
    cluster-role: dex          # one of: dex | backend | 3rd-party | velocity | listeners
    env: dev                   # one of: dev | stage | integration | prod
    region: {{PRIMARY_REGION}} # required for multi-cluster ApplicationSets
    region-short: {{PRIMARY_REGION_SHORT}}   # used in Application names + value-file lookups
    # cluster-type: gpu-inference   # optional; routes to the GPU AppSet, excluded from platform-infra
```

`cluster-role` is a cluster **identity** claim; the account name travels separately as `env`
(ADR-0012). AppSets `matchExpressions` on these labels; a mismatch silently produces **zero**
Applications (§7 P2).

### 4.4 ApplicationSet patterns (sanitized excerpts)

**Matrix (git-dir × clusters) → all clusters** — `infra-appset`:

```yaml
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          - git: { repoURL: https://github.com/{{VCS_ORG}}/{{GITOPS_REPO}}.git, revision: HEAD,
                   directories: [ { path: apps/infra/* }, { path: apps/infra/observability, exclude: true } ] }
          - clusters: { selector: {} }        # every registered cluster
  template:
    metadata:
      name: '{{.path.basename}}-{{.name}}'
      labels:                                 # ADR-0028 taxonomy stamped at generation time
        platform.system: '{{.path.basename}}'
        platform.component: infra
        platform.env: '{{.metadata.labels.env}}'
        platform.owner: platform
        platform.managed-by: argocd
    spec:
      destination: { server: '{{.server}}', namespace: '{{.path.basename}}' }
      syncPolicy: { automated: { prune: true, selfHeal: true }, syncOptions: [CreateNamespace=true, ServerSideApply=true] }
```

**Cluster-role fan-out + RollingSync** — `role-apps-appset` (the ADR-0024 dev→prod soak):

```yaml
generators:
  - matrix:
      generators:
        - clusters: { selector: { matchExpressions: [ { key: cluster-role, operator: In,
                        values: [dex, backend, 3rd-party, velocity, listeners] } ] } }
        - git: { directories: [ { path: 'apps/cluster-roles/{{.metadata.labels.cluster-role}}/*' } ] }
strategy:
  type: RollingSync
  rollingSync:
    steps:
      - matchExpressions: [ { key: env, operator: In, values: [dev] } ]                  # maxUpdate 100%
      - matchExpressions: [ { key: env, operator: In, values: [stage, integration] } ]   # maxUpdate 50%
      - matchExpressions: [ { key: env, operator: In, values: [prod] } ]                 # maxUpdate 25% (canary wave)
# source path resolves to argocd/overlays/<cluster-role>-<env>/<app> (Kustomize overlay)
```

**Workload AppSet (Family B, Kargo-driven, multi-source Helm)** — `applicationset-workloads.yaml`:

```yaml
generators:
  - matrix:
      generators:
        - list: { elements: [ {team: mono,namespace: mono}, {team: chains,...}, {team: direct,...},
                              {team: protocols,...}, {team: listeners,...} ] }        # 5 teams
        - list: { elements: [ {env: dev,autoSync: true}, {env: integration,autoSync: true},
                              {env: staging,autoSync: true}, {env: prod,autoSync: false} ] }  # 4 envs
template:
  metadata:
    annotations:
      kargo.akuity.io/authorized-stage: '{{ .team }}:{{ .env }}'      # Kargo may edit only its own app
      platform.io/version-manifest: 'versions/{{ .env }}/versions.yaml'
  spec:
    project: platform-workloads
    sources:                                                          # multi-source: chart + $values ref
      - repoURL: git@github.com:{{VCS_ORG}}/{{GITOPS_REPO}}.git
        path: helm/app
        helm:
          releaseName: '{{ .team }}'
          valueFiles: [ $values/envs/{{ .env }}/values/{{ .team }}/values.yaml,   # Kargo writes image.tag here
                        $values/apps/{{ .team }}/values.yaml ]
          values: |
            image: { repository: "{{ECR_REGISTRY}}/{{ .team }}" }
      - repoURL: git@github.com:{{VCS_ORG}}/{{GITOPS_REPO}}.git
        ref: values
    destination: { namespace: '{{ .env }}-{{ .namespace }}' }        # e.g. prod-chains
    syncPolicy:
      {{- if eq .autoSync true }}automated: { prune: true, selfHeal: true }{{- end }}   # prod = manual
      syncOptions: [CreateNamespace=true, ServerSideApply=true, PruneLast=true, RespectIgnoreDifferences=true]
    ignoreDifferences: [ { group: apps, kind: Deployment, jqPathExpressions: [.spec.replicas] } ]  # HPA owns replicas
syncPolicy: { preserveResourcesOnDeletion: true }
strategy: { type: RollingSync, rollingSync: { steps: [ dev, integration, staging, prod ] } }
```

Key cross-cutting AppSet conventions: `goTemplate: true` + `missingkey=error` (fail on a missing
label rather than render empty); `RespectIgnoreDifferences` + a `.spec.replicas` ignore so the HPA
owns replica count; `preserveResourcesOnDeletion` so deleting the AppSet does not nuke live workloads;
`prod` autoSync **off** (human-gated). The multi-cluster and GPU AppSets add: a `region`/`region-short`
selector for active-active staging (deploy `{{PRIMARY_REGION}}` first, then `{{SECONDARY_REGION}}`),
Cilium global-service annotations (`service.global: true, globalAffinity: local`), and a
`cluster-type: gpu-inference` `NotIn`/`matchLabels` split so GPU clusters get VictoriaMetrics +
`values-gpu-inference.yaml` and skip the standard observability stack.

**AppProject boundary** — `appproject-workloads.yaml` constrains the blast radius: `sourceRepos`
pinned to the one GitOps repo; `destinations` limited to `{dev,integration,staging,prod}-*`
namespaces on the in-cluster server; a `namespaceResourceWhitelist` (Deployment, StatefulSet,
Service, ConfigMap, Secret, HPA, PDB, NetworkPolicy, Ingress, ExternalSecret, ServiceMonitor,
Job/CronJob) and `clusterResourceWhitelist` of just `Namespace`.

### 4.5 ArgoCD operational hardening (ADR-0024, no version bump)

`argocd/config/argocd-cmd-params-cm.yaml` (delivered via the bootstrap Kustomization):

```yaml
data:
  controller.diff.server.side: "true"   # diff via API server → kills spurious OutOfSync from webhook/defaulting
  reposerver.git.shallow:      "true"   # depth=1 fetch → less repo-server memory, faster reconcile
```

Note the two-layer SSA: `controller.diff.server.side` (this CM) controls the **diff**; per-Application
`syncOptions: [ServerSideApply=true]` controls the **apply**. Both are needed for the full
"no spurious OutOfSync" benefit. RollingSync (§4.4) and PreDelete hooks (drain/deregister before
teardown) are the other two capabilities.

### 4.6 The generic `helm/app` chart (v0.4.0)

One chart deploys every workload. Load-bearing behaviours:

- **Deployment *or* Rollout**, mutually exclusive, sharing one `app.podSpec` helper so the two kinds
  never diverge. `rollout.enabled: true` renders an Argo Rollouts canary with the Gateway-API traffic
  plugin (rewrites `HTTPRoute` backendRef weights; default ladder `10→30→50→100`), each step gated by
  a Prometheus `AnalysisTemplate` (5xx `<1%`, p95 `<500ms`). Design-target here (no Rollouts
  controller deployed).
- **PreSync migration Job** (`migrations.enabled`): annotated `argocd.argoproj.io/hook: PreSync`,
  `hook-delete-policy: HookSucceeded,BeforeHookCreation`, `sync-wave: "-1"`. Runs once per sync before
  any Sync-phase resource; a failure marks the Application `Failed` and old pods keep serving. Reuses
  the app image by default; DB creds come only from the ESO secret via `envFrom`; `backoffLimit: 0`.
- **Secure-by-default pod spec**: `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: [ALL]`,
  `seccompProfile: RuntimeDefault`, `automountToken: false`, default requests `100m/128Mi`, limits
  `500m/256Mi`, `terminationGracePeriodSeconds: 35` + `preStop sleep 5`.
- **Taxonomy gate (ADR-0028)**: the chart **fails `helm template`/`lint`** if `platform.system`,
  `platform.component`, or `platform.owner` is empty — a misconfigured release never reaches a cluster.
- **ExternalSecret** template (delivery boundary only — see SPEC-05) and a `ServiceMonitor`.

### 4.7 Kargo promotion (Family B)

**Project** declares which stages auto-promote:

```yaml
kind: Project   # kargo/projects/chains.yaml
spec:
  promotionPolicies:
    - { stage: dev, autoPromotionEnabled: true }
    - { stage: integration, autoPromotionEnabled: true }
    - { stage: staging, autoPromotionEnabled: true }
    - { stage: prod, autoPromotionEnabled: false }        # human gate
```

**Warehouse** subscribes to an image repo (ECR) and a git path; a new digest/tag mints Freight:

```yaml
kind: Warehouse   # kargo/warehouses/chains.yaml
spec:
  subscriptions:
    - image: { repoURL: {{ECR_REGISTRY}}/chains, semverConstraint: ">=0.1.0", discoveryLimit: 5 }
    - git:   { repoURL: git@github.com:{{VCS_ORG}}/{{GITOPS_REPO}}.git, includePaths: [apps/chains/**] }
```

**Stage** promotion steps are pure GitOps writes + an ArgoCD nudge — Kargo never `kubectl apply`s:

```yaml
kind: Stage   # kargo/stages/chains/prod.yaml
spec:
  requestedFreight: [ { origin: { kind: Warehouse, name: chains }, sources: { stages: [staging] } } ]  # prod ← staging
  promotionTemplate:
    spec:
      steps:
        - uses: git-clone      # checkout main → ./src
        - uses: yaml-update    # versions/prod/versions.yaml: image.tag AND image.digest (prod pins digest)
        - uses: yaml-update    # envs/prod/values/chains/values.yaml: image.tag  ← what ArgoCD reads
        - uses: git-commit     # "chore(chains): promote to prod v<tag>"
        - uses: git-push
        - uses: argocd-update  # apps: [chains-prod]  → triggers ArgoCD reconcile
  verification:
    analysisTemplates: [health-check, smoke-test, integration-test, prometheus-5xx-error-rate, prometheus-p95-latency]
```

Verification tightens down the graph: `dev` → `health-check` only; `integration` → `+integration-test`;
`staging`/`prod` → `+` the two Prometheus gates. `dev`/`staging` request Freight `direct: true`
(auto-advance from Warehouse); `integration`/`staging`/`prod` request from the previous stage,
enforcing linear progression. Prod additionally writes `image.digest` (immutable pin).

**Metric gate** (Prometheus provider, reading Tempo metrics-generator RED metrics — ADR-0019 dep):

```yaml
kind: AnalysisTemplate   # prometheus-p95-latency
spec:
  args: [ {name: service, value: ".*"}, {name: namespace, value: default},
          {name: prometheus-address, value: http://kube-prometheus-stack-prometheus.observability.svc:9090},
          {name: latency-threshold-ms, value: "500"} ]
  metrics:
    - name: p95-latency-ms
      provider: { prometheus: { query: |
          histogram_quantile(0.95, sum by (le) (rate(
            http_server_request_duration_seconds_bucket{service_name=~"{{args.service}}", namespace="{{args.namespace}}"}[5m]))) * 1000 } }
      successCondition: result[0] < {{args.latency-threshold-ms}}
      failureCondition: result[0] >= {{args.latency-threshold-ms}} * 2
      interval: 60s, count: 5      # 5-minute observation window
```

ML pipelines reuse the identical machinery: a `ml-pipeline-*` Warehouse tracks an ECR/GHCR model image
by **digest** (`tagSelectionStrategy: Digest` — only cosign-signed/SBOM-attested images promote), and
the Stage `yaml-update`s the serving chart's `image.tag` (e.g. `apps/infra/mlflow-baremetal/values.yaml`).

### 4.8 Environment promotion & rollback story

- **Promote.** CI builds+pushes an image and (per ADR-0015) opens a PR bumping the tag — *or* Kargo's
  Warehouse detects the new digest. Kargo auto-advances `dev → integration → staging`; each hop
  commits the new tag into `envs/<env>/values/<team>/values.yaml`, ArgoCD reconciles, verification
  runs. **Prod** requires a manual, digest-pinned Kargo promotion (human approval + ticket).
- **Rollback.** Because desired state *is* the Git commit, rollback = revert the promotion commit (or
  re-promote the prior Freight, which is digest-addressed). ArgoCD self-heals to the reverted state.
  For a failed migration, set `migrations.enabled: false` on the re-sync (image-only rollback); schema
  down-migrations are the tool's responsibility (expand/contract).
- **Drift.** `selfHeal: true` reverts any out-of-band `kubectl` edit on the next reconcile.
  Server-side diff (§4.5) ensures the drift signal is real, not a webhook artefact. `.spec.replicas`
  is deliberately ignored so the HPA is authoritative.

---

## 5. Parameterization table

| Placeholder | Meaning | Default in this estate | Resize guidance |
|---|---|---|---|
| `{{VCS_ORG}}` | Git hosting org (SPEC-00) | *(org slug)* | one org owns the GitOps mono-repo |
| `{{GITOPS_REPO}}` *(spec-local)* | single GitOps mono-repo name | `platform-design` | one repo holds `argocd/ apps/ envs/ helm/ kargo/`; split only at very large scale |
| `{{PRIMARY_REGION}}` / `{{SECONDARY_REGION}}` | active-active regions | `eu-west-1` / `eu-central-1` | add a region = register a cluster secret with `region`/`region-short`; RollingSync deploys primary-first |
| `{{PRIMARY_REGION_SHORT}}` / `{{SECONDARY_REGION_SHORT}}` | short region tokens in app names/value files | `euw1` / `euc1` | keep ≤4 chars; used literally in `values-<short>.yaml` lookups |
| `{{ECR_REGISTRY}}` *(spec-local)* | image registry base | `{{PROD_ACCOUNT_ID}}.dkr.ecr.{{PRIMARY_REGION}}.amazonaws.com` | any OCI registry; Warehouses subscribe per-team `.../<team>` |
| `{{PROD_ACCOUNT_ID}}` etc. | AWS account IDs (SPEC-00) | *(12-digit)* | one per account in the OU split |
| **Sizing knob** | | | |
| cluster-role values | workload tiers | `dex, backend, 3rd-party, velocity, listeners` | rename to the client's tiers; must match `role-apps-appset` selector AND `overlays/<role>-<env>/` dirs |
| workload teams × envs | Family-B matrix | `5 teams × 4 envs = 20 apps` | edit the two `list` generators in `applicationset-workloads.yaml` |
| env names | Kargo/workload envs | `dev, integration, staging, prod` | ⚠ Family-A cluster label uses `stage`, Family-B uses `staging` — see P3 |
| RollingSync `maxUpdate` | fleet canary width | `100% / 50% / 25%` (dev/stage+int/prod) | lower prod % for larger fleets |
| ArgoCD version / HA | control plane | `3.3.6` (chart `9.5.1`), `ha_enabled = (env==prod)` | HA in prod only; pin `argocd_chart_version` per account |
| Kargo version | promotion plane | chart `~1.9` (locked `1.9.8`), appVersion `1.9.0` | stage a major bump in a non-prod Project first |
| `helm/app` version | app chart | `0.4.0` (appVersion `1.0`) | bump per chart change; every workload rides one chart |
| gate thresholds | promotion safety | 5xx `<1%`, p95 `<500ms`, window `5×60s` | start permissive in `dev`, tighten toward `prod` via per-Stage `args` |

---

## 6. Best practices distilled

1. **Point ArgoCD at exactly one object.** The `root-app` Application is the only hand-applied
   manifest; everything else is generated. *Why:* a single, self-healing entrypoint means "rebuild the
   control plane" is `apply root-app.yaml` — no snowflake bootstrap script to drift.
2. **Install the GitOps engine with the IaC tool, not with itself.** Terragrunt installs ArgoCD (and
   CRDs) via Helm; ArgoCD then manages everything *including its own config*. *Why:* breaks the
   chicken-and-egg and keeps day-2 ArgoCD config (`argocd-cmd-params-cm`) under GitOps.
3. **Make the cluster a queryable set, not a list.** ApplicationSets select clusters by *labels*
   (`cluster-role`, `env`, `region`, `cluster-type`), so onboarding a cluster is "create a labelled
   Secret" and it auto-receives the right apps. *Why:* fleet growth costs zero AppSet edits.
4. **`goTemplateOptions: ["missingkey=error"]` everywhere.** *Why:* a missing cluster label should
   *fail loudly*, never silently render an Application into the wrong namespace or with an empty name.
5. **Bake a dev→prod soak into the fleet rollout.** RollingSync steps keyed on the `env` label promote
   `dev (100%) → stage/integration (50%) → prod (25%)`, pausing on any degraded Application. *Why:* one
   bad generated Application can otherwise land on every cluster at once.
6. **Server-side diff *and* server-side apply.** Enable both (they are different layers). *Why:*
   eliminates spurious `OutOfSync` from webhook/defaulting mutation across the whole matrix — the
   alternative (`ignoreDifferences` per field) is unbounded maintenance that masks real drift.
7. **Let the autoscaler own what it owns.** `ignoreDifferences` on `.spec.replicas` +
   `RespectIgnoreDifferences`. *Why:* otherwise ArgoCD and the HPA fight every reconcile.
8. **Promote by committing, verify by metric.** Kargo edits a value file and pushes; verification is a
   Prometheus RED-metric gate (5xx/p95), not a one-shot probe. *Why:* "it responded once" ≠ "it is
   healthy under traffic"; and a git commit is an auditable, revertible promotion record.
9. **Pin prod by digest, gate prod by a human.** Prod Stage writes `image.digest` and
   `autoPromotionEnabled: false`; the workload AppSet sets prod `autoSync: false`. *Why:* immutable,
   reproducible prod artifacts with a deliberate human checkpoint.
10. **Migrate with a PreSync Job, never an init container.** One Job per sync, before Sync-phase
    resources, clean pass/fail. *Why:* avoids racing migrations across a rolling update and leaves old
    replicas serving on failure.
11. **One generic chart, many services.** Every workload rides `helm/app`; per-service difference is a
    values file. *Why:* security posture, taxonomy labels, probes, and canary machinery are fixed once
    and inherited everywhere; drift between services is impossible.
12. **Fail the render on missing ownership labels.** The chart hard-errors without
    `platform.system/component/owner`. *Why:* turns "who owns this / what does it cost" into a
    render-time invariant, powering Grafana/OpenCost/Cilium joins for free.
13. **Constrain blast radius with an AppProject.** Whitelist source repo, destination namespaces, and
    resource kinds for the workload project. *Why:* a compromised or buggy AppSet cannot deploy
    cluster-scoped resources or escape its `<env>-*` namespaces.
14. **`preserveResourcesOnDeletion` on workload AppSets.** *Why:* deleting/renaming an AppSet must not
    prune live production workloads out from under traffic.

---

## 7. Known pitfalls

- **As-built divergence:** **P1 — Two ApplicationSet families, only one wired.** `argocd/bootstrap/kustomization.yaml` lists
  the four *Family-A* AppSets + `../config` but **not** the top-level *Family-B* files
  (`applicationset-workloads.yaml`, `appproject-workloads.yaml`, `kargo-bootstrap.yaml`,
  `applicationset.yaml`, `applicationset-gpu-inference.yaml`). Nothing in-repo applies them, so on a
  clean bootstrap the workload/Kargo plane never comes up. A rebuild must add these to an app-of-apps
  (or a second bootstrap Kustomization) — or pick one family as canonical and delete the other.
- **P2 — Label/selector mismatch → zero Applications.** ADR-0012's founding bug: the AppSet selected
  `cluster_role: platform` while the cluster secret was labelled `shared`, so the AppSet produced
  **zero** Applications and workloads silently never deployed. Always dry-run AppSet output after any
  label or selector change; treat "0 generated" as an error.
- **As-built divergence:** **P3 — `stage` vs `staging` drift.** Family-A cluster labels + `role-apps` RollingSync use `stage`;
  Family-B workloads + Kargo use `staging`; overlays are named `<role>-stage`. A value file or
  selector using the wrong spelling silently no-ops. Normalize the env vocabulary on rebuild.
- **P4 — Gates depend on a live metrics feed.** The Prometheus 5xx/p95 templates read Tempo
  metrics-generator RED metrics (ADR-0019). Without that feed the gate has no data and fails
  open/closed. Sequence the observability trace-lane *before* flipping Stages from `health-check` to
  metric gates.
- **As-built divergence:** **P5 — Rollouts referenced but not deployed.** `helm/app` ships `rollout.yaml` + analysis and ADR-0014
  is "synced", but no Argo Rollouts controller runs here. `rollout.enabled: true` renders a `Rollout`
  CRD nothing reconciles. Keep `rollout.enabled: false` until the controller is actually installed.
- **As-built divergence:** **P6 — Repo URL scheme is mixed.** Some manifests use `https://github.com/...` (git-dir generators,
  root-app) and others `git@github.com:...` (Helm multi-source, Kargo). SSH-based sources need a repo
  credential Secret in `argocd`/`kargo`; HTTPS public reads do not. Standardize and provision creds
  accordingly, or ArgoCD reports `ComparisonError` on the SSH sources.
- **P7 — Shallow clone needs a resolvable revision.** `reposerver.git.shallow` fetches depth=1;
  `targetRevision: HEAD` on a rolling branch fetches only the tip (desired), but a floating tag that
  moves can surprise. Prefer concrete SHAs for reproducible prod syncs.
- **P8 — Namespaces aren't Helm-rendered.** `CreateNamespace=true` makes ArgoCD create the namespace,
  so `helm/app` cannot label it. Ship an explicit `Namespace` manifest (with `platform.*` labels) or a
  Kyverno mutation, else namespace-level taxonomy/policy selectors miss.

---

## 8. Acceptance checklist

A rebuild passes when:

- [ ] From an empty cluster, applying **only** `argocd/bootstrap/root-app.yaml` (after Terragrunt
      installs ArgoCD + CRDs) results in a fully-synced app-of-apps with **zero** manual `kubectl apply`
      of child manifests.
- [ ] `argocd app list` shows the expected generated Applications for every registered cluster; no
      AppSet produces **0** Applications (P2 guard).
- [ ] `argocd-cmd-params-cm` has `controller.diff.server.side=true` and `reposerver.git.shallow=true`;
      a steady-state fleet shows **no spurious `OutOfSync`**.
- [ ] Role-apps / infra ApplicationSets use `RollingSync` keyed on the `env` label; a change lands in
      `dev` first and pauses the rollout on any degraded Application before `prod`.
- [ ] The workload AppProject (`platform-workloads`) restricts sources to the one GitOps repo,
      destinations to `{dev,integration,staging,prod}-*`, and resources to the kind whitelist.
- [ ] `helm template helm/app` **fails** when `platform.system/component/owner` are unset, and
      **succeeds** with them set; every rendered resource carries the five `platform.*` labels.
- [ ] A Kargo `dev` promotion auto-commits an image-tag bump into `envs/dev/values/<team>/values.yaml`
      and `versions/dev/versions.yaml`, and ArgoCD reconciles it; `prod` requires a manual,
      digest-pinned promotion and the prod Application has `autoSync: false`.
- [ ] Staging/prod Stages run the Prometheus 5xx + p95 `AnalysisTemplate`s and block promotion when a
      threshold is breached (with the metrics feed live).
- [ ] Enabling `migrations.enabled` renders a PreSync Job (`sync-wave: -1`) that runs once before the
      Deployment/Rollout; a failing migration marks the Application `Failed` with old pods still serving.
- [ ] Reverting a promotion commit rolls the environment back via self-heal with no manual cluster
      surgery.
- [ ] Deleting a workload ApplicationSet does **not** prune live workloads
      (`preserveResourcesOnDeletion: true`).

---

## 9. Dependencies on other specs

- **SPEC-02 (Terragrunt / IaC foundation)** — provisions the cluster and runs the `catalog/units/argocd`
  unit that installs ArgoCD + CRDs (the pre-`root-app` steps of §4.2). The `never_apply`/CI-only apply
  discipline governs how this delivery plane's Terragrunt units reach prod.
- **SPEC-05 (Secrets)** — owns the External Secrets Operator, `ClusterSecretStore`, IRSA/Pod-Identity
  bindings, and rotation. This spec only references `ExternalSecret` at the chart boundary
  (§4.6, ADR-0008); ArgoCD/Git never hold plaintext.
- **SPEC (Observability)** — supplies the Tempo metrics-generator RED metrics + Prometheus that the
  Kargo/Rollouts `AnalysisTemplate` gates query (ADR-0019/0026); without it promotion gates have no
  data (P4). Also consumes the `platform.*` taxonomy (ADR-0028) for dashboards.
- **SPEC (CI / supply chain)** — builds and signs images (cosign/SBOM), pushes to ECR, and opens the
  GitOps PRs (or feeds the Kargo Warehouse) that this plane consumes (ADR-0015/0016/0022/0048).
- **SPEC (Networking / connectivity)** — Cilium ClusterMesh global services + Gateway API `HTTPRoute`
  that the multi-cluster AppSet annotations and the chart's canary traffic-shifting rely on
  (ADR-0009/0043).
- **SPEC (Platform overview / taxonomy)** — defines the `platform.*` label taxonomy (ADR-0028) stamped
  by every ApplicationSet and rendered resource, and the OU/account model behind the account-id
  placeholders.
```
