# Kyverno — ADR-0020

Kubernetes Native Policy Management. Complements Gatekeeper + Pod Security Admission.

## Status

**Enabled** (v1.18.1). Policies are in **Enforce** mode (graduated from Audit — W3/ADR-0020).
See [Rollback](#rollback) below if enforcement must be reverted.

See [ADR-0020](../../../docs/adrs/0020-kyverno-and-vap-policy-engine.md) for rationale.

## Enforcement History

| Date | Event | PR |
|------|-------|-----|
| Initial deploy | All policies set to Audit | #266 |
| W3 graduation | Audit → Enforce (post-soak, zero unexpected violations) | W3/ADR-0020 |

## Policy split (ADR-0020)

| Layer | What it owns | Why |
|-------|-------------|-----|
| **Kyverno** | verifyImages (keyless cosign), mutate securityContext, generate default-deny NetworkPolicy | Verify/mutate/generate — things VAP and Rego handle poorly |
| **VAP (native CEL)** | Block `:latest`, require resource limits | Simple in-process CEL checks, no webhook, lower latency |
| **Gatekeeper** | 4 existing ConstraintTemplates (kept) | Mature, audited — no rewrite risk |
| **PSA** | `restricted` baseline | Node-level Pod Security Admission |

## What is deployed

### Kyverno engine (`kyverno/`)

- Chart: `kyverno/kyverno` at **v3.4.4** (app v1.18.1)
- 3-replica admission controller, 2-replica background/cleanup/reports controllers
- Image verification cache enabled (~60 min TTL) to limit Rekor round-trips

### Policies (`templates/policies/`)

| File | Kind | Purpose |
|------|------|---------|
| `verify-images.yaml` | ClusterPolicy | Keyless cosign image signature verification. Fulcio issuer = GitHub Actions OIDC. mutateDigest rewrites tag to verified digest. **Enforce** (W3). |
| `mutate-security-context.yaml` | ClusterPolicy | Injects `runAsNonRoot: true`, `seccompProfile: RuntimeDefault`, `capabilities.drop: [ALL]` into containers that do not already set these fields. |
| `generate-default-deny-netpol.yaml` | ClusterPolicy | Generates a `default-deny-all` NetworkPolicy into every new namespace (excluding system/infra namespaces). Synchronized back if deleted. |

### ValidatingAdmissionPolicy (`templates/vap/`)

| File | Kind | Purpose |
|------|------|---------|
| `block-latest-require-limits.yaml` | ValidatingAdmissionPolicy + Binding | Block `:latest` image tags; require `resources.limits.cpu` and `resources.limits.memory`. In-process CEL, no webhook. **Deny** (W3). |

## Why image verification is here and NOT in ArgoCD

ArgoCD can only verify GnuPG-signed git commits. It cannot verify cosign or
OCI image signatures. Image-signature enforcement belongs at admission, where
Kyverno's `verifyImages` checks the OCI signature before the pod is admitted.
This is the verification layer that ADR-0016's cosign signing requires.

## Current enforcement state (post W3 graduation)

```
ClusterPolicy verify-images-keyless-cosign:
  validationFailureAction: Enforce

ValidatingAdmissionPolicy platform-pod-baseline:
  failurePolicy: Fail

ValidatingAdmissionPolicyBinding platform-pod-baseline-binding:
  validationActions: [Deny]

values.yaml admissionController:
  forceFailurePolicyIgnore.enabled: false   # webhook is fail-closed
```

## Rollback

**Prerequisite**: this rollback assumes a completed soak period. Only use it
to revert unexpected admission failures after graduation — not as a way to
skip soak-validation in new environments.

To revert enforcement to Audit mode, apply the following changes and push:

1. `apps/infra/kyverno/templates/policies/verify-images.yaml`
   ```yaml
   spec:
     validationFailureAction: Audit   # revert from Enforce
   ```

2. `apps/infra/kyverno/templates/vap/block-latest-require-limits.yaml`
   ```yaml
   spec:
     failurePolicy: Ignore            # revert from Fail (ValidatingAdmissionPolicy)
   ---
   spec:
     validationActions:
       - Audit                        # revert from Deny (ValidatingAdmissionPolicyBinding)
   ```

3. `apps/infra/kyverno/values.yaml`
   ```yaml
   admissionController:
     forceFailurePolicyIgnore:
       enabled: true                  # revert from false — restores fail-open webhook
   ```

Commit, push, and let ArgoCD sync. Audit mode produces `PolicyReport` /
`ClusterPolicyReport` violations but does not block admission.

Investigate violations before re-attempting graduation:

```bash
kubectl get policyreport -A
kubectl get clusterpolicyreport
kubectl describe policyreport -n <namespace> <name>
```

## ArgoCD

The `argocd-application.yaml` in this directory wires Kyverno as an ArgoCD
Application at sync-wave 5 (after cert-manager, before workloads). Apply with:

```bash
kubectl apply -f apps/infra/kyverno/argocd-application.yaml
```

## Monitoring

Kyverno exposes Prometheus metrics (scraped by kube-prometheus-stack):

- `kyverno_policy_results_total` — policy evaluation results by action/policy/result
- `kyverno_admission_review_duration_seconds` — admission webhook latency
- `kyverno_controller_reconcile_total` — background controller reconciliation

Check policy reports:

```bash
kubectl get policyreport -A
kubectl get clusterpolicyreport
kubectl describe policyreport -n <namespace> <name>
```

## References

- [ADR-0020](../../../docs/adrs/0020-kyverno-and-vap-policy-engine.md) — policy engine decision
- ADR-0016 — cosign signing (verified here at admission, not in ArgoCD)
- ADR-0003 — Cilium (generated NetworkPolicy pairs with Cilium baseline)
- [Kyverno docs](https://kyverno.io/docs/)
- [Kyverno image verification](https://kyverno.io/docs/policy-types/cluster-policy/verify-images/)
- [ValidatingAdmissionPolicy (GA 1.30)](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
