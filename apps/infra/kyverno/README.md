# Kyverno — ADR-0020

Kubernetes Native Policy Management. Complements Gatekeeper + Pod Security Admission.

## Status

**Enabled** (v1.18.1). All policies start in **Audit** mode.
Promote to **Enforce** after a clean audit window in each environment.

See [ADR-0020](../../../docs/adrs/0020-kyverno-and-vap-policy-engine.md) for rationale.

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
| `verify-images.yaml` | ClusterPolicy | Keyless cosign image signature verification. Fulcio issuer = GitHub Actions OIDC. mutateDigest rewrites tag to verified digest. Audit then Enforce. |
| `mutate-security-context.yaml` | ClusterPolicy | Injects `runAsNonRoot: true`, `seccompProfile: RuntimeDefault`, `capabilities.drop: [ALL]` into containers that do not already set these fields. |
| `generate-default-deny-netpol.yaml` | ClusterPolicy | Generates a `default-deny-all` NetworkPolicy into every new namespace (excluding system/infra namespaces). Synchronized back if deleted. |

### ValidatingAdmissionPolicy (`templates/vap/`)

| File | Kind | Purpose |
|------|------|---------|
| `block-latest-require-limits.yaml` | ValidatingAdmissionPolicy + Binding | Block `:latest` image tags; require `resources.limits.cpu` and `resources.limits.memory`. In-process CEL, no webhook. Audit then Deny. |

## Why image verification is here and NOT in ArgoCD

ArgoCD can only verify GnuPG-signed git commits. It cannot verify cosign or
OCI image signatures. Image-signature enforcement belongs at admission, where
Kyverno's `verifyImages` checks the OCI signature before the pod is admitted.
This is the verification layer that ADR-0016's cosign signing requires.

## Rollout

All policies and the VAP binding start in Audit mode (no blocking):

```
ClusterPolicy:                    validationFailureAction: Audit
ValidatingAdmissionPolicy:        failurePolicy: Ignore
ValidatingAdmissionPolicyBinding: validationActions: [Audit]
```

Promotion checklist (per environment):

1. Monitor `kubectl get policyreport -A` and `kubectl get clusterpolicyreport` for violations.
2. Investigate and remediate violating workloads.
3. After a clean audit window (no unexpected violations), promote:
   - ClusterPolicy: `validationFailureAction: Enforce`
   - Webhook failurePolicy in `values.yaml`: `Fail`
   - VAP Binding: `validationActions: [Deny]` (or `[Deny, Warn]`)
   - VAP Policy: `failurePolicy: Fail`

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
