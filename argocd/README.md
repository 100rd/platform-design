# ArgoCD Configuration

This directory contains the complete ArgoCD GitOps configuration, covering both multi-cluster infrastructure bootstrap and workload application deployment.

## Architecture Overview

```
                    ┌─────────────┐
                    │  root-app   │  (ArgoCD points here)
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────────┐
        │  infra   │ │  role    │ │ observability │
        │  appset  │ │  appset  │ │    appset     │
        └────┬─────┘ └────┬─────┘ └──────┬───────┘
             │             │              │
             ▼             ▼              ▼
        ALL clusters   By label     ALL clusters
        apps/infra/*   apps/cluster-roles/<role>/*
                                   apps/infra/observability/*

        ┌──────────────┐   ┌──────────────────┐
        │ platform-    │   │ platform-        │
        │ infra appset │   │ workloads appset │
        └──────┬───────┘   └───────┬──────────┘
               │                    │
               ▼                    ▼
        apps/infra/*          apps/{team}/*
        (Helm charts)         (Kargo promotion)
```

## Directory Structure

```
argocd/
├── applicationset.yaml             # Platform infra ApplicationSet (Helm-based)
├── applicationset-workloads.yaml   # Workload ApplicationSet (Kargo-driven)
├── appproject-workloads.yaml       # AppProject for workloads
├── kargo-bootstrap.yaml            # Kargo configuration Application
│
├── bootstrap/                      # Multi-cluster bootstrap entry point
│   ├── root-app.yaml               # Single Application ArgoCD targets
│   ├── kustomization.yaml          # Lists all bootstrap ApplicationSets
│   ├── applicationsets/            # Bootstrap ApplicationSet definitions
│   │   ├── infra-appset.yaml       # Shared infra → ALL clusters
│   │   ├── role-apps-appset.yaml   # Role-specific apps → matching clusters
│   │   └── observability-appset.yaml # Monitoring → ALL clusters
│   └── cluster-secrets/            # Cluster registration templates
│       └── in-cluster-template.yaml
│
├── cluster-envs/                   # Kustomize overlays for multi-cluster envs
│   ├── base/                       # Common labels & config
│   ├── dev/
│   ├── stage/
│   ├── integration/
│   └── prod/
│
├── overlays/                       # Role+Env combinations (20 total)
│   ├── dex-dev/
│   ├── backend-prod/
│   └── ...
│
└── workloads/                      # Explicit Application definitions
    ├── chains/                     # Per-team, per-env Applications
    ├── direct/
    ├── listeners/
    ├── mono/
    └── protocols/
```

## ApplicationSets

### 1. Platform Infrastructure (`applicationset.yaml`)

Deploys Helm-based infrastructure apps from `apps/infra/*` to all clusters. Uses environment-specific value overrides from `envs/<env>/values/infra/<app>.yaml`.

### 2. Platform Workloads (`applicationset-workloads.yaml`)

Deploys workload applications (5 teams x 4 environments = 20 apps) with Kargo-driven image promotion. Auto-sync for dev/integration/staging, manual for prod.

### 3. Bootstrap Infrastructure (`bootstrap/applicationsets/infra-appset.yaml`)

Multi-cluster shared infrastructure from `apps/infra/*` deployed to ALL registered clusters.

### 4. Role-Specific Apps (`bootstrap/applicationsets/role-apps-appset.yaml`)

Role-specific apps from `apps/cluster-roles/<role>/*` deployed only to clusters with matching `cluster-role` label.

### 5. Observability (`bootstrap/applicationsets/observability-appset.yaml`)

Observability stack from `apps/infra/observability/*` deployed to ALL clusters into the `observability` namespace.

### 6. Multi-Cluster Workloads (`applicationset-multicluster.yaml`)

Deploys workload applications across multiple regional clusters for active-active. Uses cluster selector with `region` label to discover targets. Each app gets Cilium global service annotations for cross-cluster discovery. RollingSync deploys to eu-west-1 first, then eu-central-1.

### 7. Multi-Cluster Infrastructure (`bootstrap/applicationsets/multicluster-infra-appset.yaml`)

Deploys shared infra to all clusters with `region` label. Supports region-specific value overrides via `values/infra/<app>-<regionShort>.yaml`.

## Cluster Label Convention

Every cluster registered with ArgoCD must have these labels on its Secret:

```yaml
metadata:
  labels:
    cluster-role: dex        # one of: dex, backend, 3rd-party, velocity, listeners
    env: dev                 # one of: dev, stage, integration, prod
    region: eu-west-1        # AWS region (required for multi-cluster ApplicationSets)
    region-short: euw1       # short name (used in Application names and value file lookups)
```

See `bootstrap/cluster-secrets/in-cluster-template.yaml` for a full example.

## Onboarding a New Cluster

1. Create a cluster Secret with the correct labels (see template)
2. ArgoCD will automatically deploy:
   - Shared infra from `apps/infra/`
   - Observability stack from `apps/infra/observability/`
   - Role-specific apps from `apps/cluster-roles/<cluster-role>/`
   - Using overlays from `overlays/<role>-<env>/`

## Adding a New App

### Shared infra (all clusters)

1. Create Helm chart under `apps/infra/<app-name>/`
2. Add environment overrides in `envs/<env>/values/infra/<app-name>.yaml`
3. Auto-discovered by both `applicationset.yaml` and `infra-appset`

### Role-specific app

1. Create directory under `apps/cluster-roles/<role>/<app-name>/`
2. Add `kustomization.yaml` with manifests or Helm chart reference
3. Optionally add overlay patches in `overlays/<role>-<env>/<app-name>/`
4. Auto-discovered by `role-apps-appset`

## Environments

| Environment   | Purpose                    | Promotion Gate          |
|---------------|----------------------------|-------------------------|
| `dev`         | Development / testing      | Automatic               |
| `integration` | Integration testing        | Passing integration tests |
| `stage`       | Pre-production validation  | Passing tests           |
| `prod`        | Production                 | Human approval + ticket |
