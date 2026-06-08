# argocd/config — ArgoCD operational hardening (ADR-0024)

This directory contains ConfigMap patches for ArgoCD operational capabilities
enabled on the running **ArgoCD 3.3.6 (chart 9.5.1)** — no version upgrade
required. Applied via the bootstrap Kustomization
(`argocd/bootstrap/kustomization.yaml`) and reconciled by the root ArgoCD
Application (`argocd/bootstrap/root-app.yaml`).

Ratified: ADR-0024 (`docs/adrs/0024-argocd-operational-hardening.md`),
2026-06-07.

---

## Files

| File | Purpose |
|------|---------|
| `argocd-cmd-params-cm.yaml` | Enables server-side diff and shallow git clone |
| `kustomization.yaml` | Kustomize entrypoint for this directory |

---

## argocd-cmd-params-cm.yaml

### controller.diff.server.side = "true"

Switches ArgoCD's diff engine to **server-side diff**: the application-controller
submits a dry-run server-side apply to the Kubernetes API server to determine
what would change, rather than comparing local manifests against cached live
state. Because the diff goes through the API server's admission webhook and
defaulting chain, any fields that a webhook or mutating admission controller
rewrites are already present in the diff result — they no longer cause spurious
`OutOfSync`.

Without this flag, a single field mutated by a webhook (e.g. a label injected
by Kyverno, or a container security context normalised by an admission webhook)
causes every Application that touches that resource to report `OutOfSync` on
every reconcile cycle, generating alert noise and unnecessary sync churn across
the entire clusters-x-git matrix.

### reposerver.git.shallow = "true"

Switches the ArgoCD repo-server to **shallow git clone** (depth=1). Instead of
fetching full commit history on every reconcile, the repo-server fetches only
the tip commit. On large repos with thousands of commits this reduces both clone
wall-clock time and repo-server heap usage significantly.

**Important constraint:** shallow clone is most effective when `targetRevision`
is a branch name or tag (the tip is depth=1). If an Application pins a specific
historical SHA the repo-server will still fetch a minimal graph to reach that
commit. All ApplicationSets in this repo use `revision: HEAD`, so the benefit
is realised immediately.

---

## PreDelete hook pattern (ADR-0024)

A **PreDelete hook** is an ArgoCD sync hook that runs **before ArgoCD deletes
a managed resource**. It is the correct way to implement ordered teardown:
drain connections, deregister from a service registry, remove from a load
balancer target group, or flush an in-flight queue before the workload
disappears.

### When to use

Use a PreDelete hook on any resource whose abrupt deletion would:

- Drop live user traffic (e.g. a Deployment serving HTTP requests)
- Leave a dangling registration in an external system (e.g. a Consul service,
  an AWS target group, an Istio service registry entry)
- Leave in-flight work unprocessed (e.g. a consumer Deployment reading from
  a Kafka topic)

### Annotation syntax

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreDelete
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

`HookSucceeded` causes ArgoCD to delete the hook resource itself once the hook
Job completes successfully. Use `BeforeHookCreation` instead if you want the
hook Job to be re-created on subsequent deletions (idempotent teardown).

### Example: graceful drain Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-service-predel-drain
  namespace: my-namespace
  annotations:
    # Run this Job BEFORE ArgoCD deletes any resource in the Application.
    argocd.argoproj.io/hook: PreDelete
    # Delete this Job resource once it succeeds.
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  backoffLimit: 2
  activeDeadlineSeconds: 120
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: drain
          image: curlimages/curl:8.7.1
          command:
            - /bin/sh
            - -c
            - |
              # Deregister from the load-balancer / service registry.
              # Replace with the appropriate drain command for your service.
              curl -f -X DELETE \
                "http://service-registry.internal/services/my-service/${POD_NAME}" \
                --max-time 30
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
```

### Hang prevention

A PreDelete hook that hangs blocks ArgoCD from deleting the Application.
Always set **`activeDeadlineSeconds`** on the hook Job (120 seconds is a
reasonable upper bound for most drain operations). If the Job exceeds the
deadline, Kubernetes marks it as Failed; ArgoCD then surfaces the failure in
the Application status so an operator can investigate and manually proceed.

### Hook ordering with sync waves

PreDelete hooks run in sync-wave order (lowest wave first) during the delete
phase, the same way PreSync/Sync hooks run during the sync phase. If you have
multiple PreDelete hooks that must run in sequence, use
`argocd.argoproj.io/sync-wave` annotations on each hook Job.

```yaml
# Drain connections first (wave 0)
argocd.argoproj.io/hook: PreDelete
argocd.argoproj.io/sync-wave: "0"

# Deregister from service discovery second (wave 5)
argocd.argoproj.io/hook: PreDelete
argocd.argoproj.io/sync-wave: "5"
```

---

## References

- ADR-0024: `docs/adrs/0024-argocd-operational-hardening.md`
- ArgoCD sync phases and hooks:
  <https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/>
- ArgoCD server-side diff:
  <https://argo-cd.readthedocs.io/en/stable/user-guide/diff-strategies/>
- ArgoCD cmd params reference:
  <https://argo-cd.readthedocs.io/en/stable/operator-manual/argocd-cmd-params-cm/>
- ApplicationSet Progressive Syncs:
  <https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Progressive-Syncs/>
