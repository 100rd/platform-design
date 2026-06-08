# External Secrets Operator

This chart installs the [External Secrets Operator](https://github.com/external-secrets/external-secrets)
(ESO) using the official Helm chart from `https://charts.external-secrets.io`.

The `Chart.yaml` declares a dependency on the upstream chart so ArgoCD can pull it
automatically. `values.yaml` disables in-chart CRD installation because CRDs are
managed by the Terraform `platform-crds` module.

This application is discovered by the ApplicationSet and deployed into each cluster
as an infrastructure component.

---

## Current version

| Field         | Value         |
|---------------|---------------|
| Helm chart    | `2.6.0`       |
| App version   | `v2.6.0`      |
| API version   | `external-secrets.io/v1` |

ESO v2.x graduated the `ExternalSecret`, `ClusterExternalSecret`, `SecretStore`,
`ClusterSecretStore`, `PushSecret`, and Generator CRDs from `v1beta1` to `v1`.
The `v1beta1` served version was removed in v2.x. All manifests in this repo must
use `external-secrets.io/v1`.

---

## Staged upgrade procedure (CRD-first)

Because CRDs are managed out-of-band (Terraform) and ArgoCD syncs the Helm chart
separately, the upgrade must follow a strict order to avoid a window where the
controller expects `v1` but only `v1beta1` is registered (or vice-versa).

### Step 1 — Apply upgraded CRDs via Terraform

```bash
# In the platform-crds Terragrunt unit
terragrunt plan   # confirm CRD changes
terragrunt apply  # installs external-secrets.io/v1 alongside v1beta1
```

After this step the API server serves both `v1beta1` (deprecated, still stored) and
`v1` (new storage version). Existing objects are not migrated yet.

### Step 2 — Migrate all CR manifests from v1beta1 to v1

Update every `ExternalSecret`, `ClusterExternalSecret`, `SecretStore`,
`ClusterSecretStore`, `PushSecret`, and Generator manifest in the repo:

```diff
-apiVersion: external-secrets.io/v1beta1
+apiVersion: external-secrets.io/v1
```

No field-level changes are needed — the v1 schema is backwards-compatible with
v1beta1 for all core fields. Commit and push the manifest changes.

### Step 3 — Trigger a CRD storage migration

After the CRD apply in Step 1, Kubernetes still stores objects in `v1beta1`
internally. Run the storage migration job or wait for the operator's built-in
migration (ESO v2 handles this automatically on first startup with the
`--storage-version` flag enabled by default).

### Step 4 — Bump this chart and sync ArgoCD

Merge this PR. ArgoCD will sync the new Helm chart version (`2.6.0`). The operator
restarts and begins serving all objects through the `v1` storage version.

### Step 5 — Remove the v1beta1 CRD served version (Terraform)

Once all clusters are running v2.x and no object is stored as `v1beta1`, remove the
`v1beta1` served version from the CRD definitions in the `platform-crds` Terraform
module and apply again.

---

## Rollback procedure

If the v2.x upgrade fails after Step 4:

1. **Revert ArgoCD sync** — set `targetRevision` back to the previous chart tag in
   the ApplicationSet, or use `argocd app rollback external-secrets <history-id>`.
2. **Do not downgrade CRDs** — removing the `v1` served version while objects are
   stored as `v1` will make them unreadable. Keep both `v1` and `v1beta1` served
   versions in the CRD until the rollback window has passed.
3. **Check controller logs** for admission-webhook errors before re-applying traffic:
   ```bash
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100
   ```
4. After a successful rollback, re-plan the migration and address the root cause
   before retrying.

---

## Auth

The ESO controller uses EKS Pod Identity (ADR-0018). An
`aws_eks_pod_identity_association` in `catalog/units/pod-identity-eso` binds the
controller `ServiceAccount` to an IAM role. The `ServiceAccount` must not carry an
`eks.amazonaws.com/role-arn` IRSA annotation alongside a Pod Identity association
(precedence is undocumented by AWS; ADR-0018 forbids the combination).

---

## Auto-refresh for rotated secrets (`refreshInterval` + Reloader) — ADR-0031

When a backend credential is **rotated** in AWS Secrets Manager (see ADR-0031: the
`secret-rotation` Terraform module + rotation Lambda), ESO must **re-pull** the new
value and consumers must **roll their pods** onto it. Rotation alone is not enough —
the materialized K8s `Secret` and any running pods keep the **old** value until
something refreshes them, which silently breaks auth on the next reconnect.

### Set a bounded `refreshInterval` on each `ExternalSecret`

`refreshInterval` controls how often ESO re-pulls the `SecretString` from Secrets
Manager and updates the materialized `Secret`. For a rotated credential it must be
**bounded** (not `0`, which disables refresh) and shorter than the gap between the
new credential going live and the old one being retired:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-db-credentials
spec:
  refreshInterval: 1h            # re-pull hourly; tune to the rotation cadence
  secretStoreRef:
    name: cluster-secret-store
    kind: ClusterSecretStore
  target:
    name: app-db-credentials     # the materialized K8s Secret
  data:
    - secretKey: password
      remoteRef:
        key: staging/app-db/credentials   # the rotated Secrets Manager secret
        property: password
```

Trade-off: each `ExternalSecret` issues one Secrets Manager `GetSecretValue` per
`refreshInterval`, so do not set it to seconds — minutes-to-hours is the right range.

### Roll the pods onto the new value (Stakater Reloader)

Updating the `Secret` does **not** restart the pods that mounted it. Annotate the
consuming `Deployment`/`StatefulSet` for [Stakater Reloader](https://github.com/stakater/Reloader),
which watches the `Secret` and triggers a rolling restart when its content changes:

```yaml
metadata:
  annotations:
    # restart only when THIS secret changes
    secret.reloader.stakater.com/reload: "app-db-credentials"
    # or, to watch every referenced Secret/ConfigMap:
    # reloader.stakater.com/auto: "true"
```

Equivalently, ESO can stamp a content checksum the pod template references (so a
value change produces a new pod-template hash and a rollout), but Reloader is the
simpler, declarative default for this estate.

### End-to-end flow

```
Secrets Manager rotation Lambda rotates the value (ADR-0031)
      → ESO re-pulls within refreshInterval and updates the K8s Secret
      → Reloader sees the Secret change and rolls the Deployment
      → new pods read the rotated credential; old credential can be retired
```

See `terraform/modules/secret-rotation/README.md` and ADR-0031 for the
Secrets-Manager-side rotation Lambda, schedule, and least-privilege IAM.
