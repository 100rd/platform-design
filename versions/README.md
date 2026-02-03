# Application Version Management

Centralized version control for all platform applications across environments.

## Overview

This directory contains **version manifests** - the single source of truth for
what version of each application is deployed in each environment.

```
versions/
├── schema.json              # JSON Schema for validation
├── dev/
│   └── versions.yaml        # All app versions for dev environment
├── integration/
│   └── versions.yaml
├── staging/
│   └── versions.yaml
└── prod/
    └── versions.yaml
```

## Version Manifest Structure

```yaml
apiVersion: platform.io/v1
kind: VersionManifest
metadata:
  environment: dev
  lastUpdated: "2026-02-03T15:00:00Z"
  updatedBy: kargo
spec:
  defaults:
    helm:
      chart: helm/app
      version: "0.2.0"
    image:
      repository: "${ECR_REGISTRY}"

  applications:
    mono:
      image:
        tag: "1.2.3"
        digest: "sha256:..."  # Optional, recommended for prod
      replicas: 2
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
```

## How Version Updates Flow

```
┌─────────────┐     ┌───────────┐     ┌──────────────────┐     ┌────────┐
│ ECR Image   │────▶│  Kargo    │────▶│ Version Manifest │────▶│ ArgoCD │
│ Published   │     │ Warehouse │     │ + Values File    │     │  Sync  │
└─────────────┘     └───────────┘     └──────────────────┘     └────────┘
```

1. **New image pushed to ECR** - CI/CD builds and pushes image with semver tag
2. **Kargo Warehouse detects** - Watches ECR for new images matching constraints
3. **Kargo Stage promotes** - Updates BOTH:
   - `versions/{env}/versions.yaml` (source of truth)
   - `envs/{env}/values/{app}/values.yaml` (for ArgoCD)
4. **ArgoCD syncs** - Detects values file change, deploys new version

## Promotion Pipeline

```
dev ──▶ integration ──▶ staging ──▶ prod
         (auto)          (auto)     (manual)
```

- **dev**: Auto-promoted when new image detected
- **integration**: Auto-promoted after dev verification passes
- **staging**: Auto-promoted after integration tests pass
- **prod**: Manual approval required

## CLI Tools

### Compare versions across environments

```bash
# All apps, all environments
./scripts/version-diff.sh

# Output:
# Application     dev             integration     staging         prod
# -------------------------------------------------------------------------------
# mono            1.2.3           1.2.3           1.2.2           1.2.0
# chains          2.0.0           2.0.0           2.0.0           1.9.5

# Compare specific environments
./scripts/version-diff.sh dev prod

# Show specific app
./scripts/version-diff.sh -a mono
```

## Adding a New Application

1. **Add to version manifests** for each environment:

```yaml
# versions/dev/versions.yaml
spec:
  applications:
    my-new-app:
      image:
        tag: "0.1.0"
      replicas: 1
```

2. **Create values file**:

```yaml
# envs/dev/values/my-new-app/values.yaml
image:
  tag: "0.1.0"
```

3. **Create Kargo resources**:
   - Warehouse (subscribes to ECR)
   - Stages (dev, integration, staging, prod)
   - Project (promotion policies)

4. **Add to ApplicationSet** (if not using dynamic generation):

```yaml
# argocd/applicationset-workloads.yaml
generators:
  - list:
      elements:
        - team: my-new-app
          namespace: my-new-app
```

## Validation

Version manifests are validated on every PR:

- **Schema validation** - Ensures correct structure
- **Required apps check** - All core apps must be present
- **Tag format validation** - Must match `^[a-zA-Z0-9][a-zA-Z0-9._-]*$`
- **Environment diff** - Shows what versions will change

## Best Practices

1. **Never edit version manifests manually** - Let Kargo handle updates
2. **Use semver tags** - Enables proper version ordering
3. **Pin digests in prod** - For immutable, reproducible deployments
4. **Review version diffs** - Before merging PRs that change versions

## Rollback

To rollback an application:

1. **Find previous version** in git history:
   ```bash
   git log -p versions/prod/versions.yaml
   ```

2. **Revert the version** manually or re-promote from Kargo UI

3. **Commit and push** - ArgoCD will sync the rollback

## Schema Reference

See `schema.json` for the full JSON Schema definition. Key fields:

| Field | Type | Description |
|-------|------|-------------|
| `spec.applications.{app}.image.tag` | string | Image tag (required) |
| `spec.applications.{app}.image.digest` | string | SHA256 digest |
| `spec.applications.{app}.helm.version` | string | Helm chart version |
| `spec.applications.{app}.replicas` | integer | Override replica count |
| `spec.applications.{app}.enabled` | boolean | Enable/disable app |
