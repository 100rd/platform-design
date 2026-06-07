# OPA Gatekeeper - Policy Enforcement

OPA Gatekeeper provides policy enforcement for Kubernetes clusters using the Open Policy Agent.

## Installation

```bash
# Using Helm
helm dependency update
helm install gatekeeper . -n gatekeeper-system --create-namespace

# Or via ArgoCD
# The Application manifest is in argocd/apps/gatekeeper.yaml
```

## Included Constraint Templates

All four constraints are now enforced in **deny** mode (W3/ADR-0017). The three
non-privileged constraints were graduated `warn → deny` after the audit-log soak
confirmed no remaining legitimate-workload violations; `block-privileged` was
already `deny`.

| Template | Purpose | Enforcement | Graduated |
|----------|---------|-------------|-----------|
| `K8sRequireSecurityContext` | Require runAsNonRoot, block privilege escalation | deny | warn → deny (W3) |
| `K8sBlockPrivileged` | Block privileged containers | deny | already deny |
| `K8sRequireResourceLimits` | Require memory limits | deny | warn → deny (W3) |
| `K8sBlockLatestTag` | Block :latest image tag | deny | warn → deny (W3) |

## Enforcement Modes

- `deny` - Reject non-compliant resources (current state for all four)
- `warn` - Admit but emit an admission warning
- `dryrun` - Log violations in audit without affecting admissions

## Graduation: warn → deny (W3/ADR-0017)

The graduation path each constraint followed, and the gate at each step:

```
warn     admit + emit warning            ──►  soak: collect violations in audit
deny     reject non-compliant resource   ──►  promoted once audit was clean
```

Each constraint carries a `policy.qbiq.io/enforcement-graduation` annotation
recording its transition, and an inline comment on `spec.enforcementAction`
describing the rollback/escape (below).

## Rollback / dry-run escape hatch

`spec.enforcementAction` is a **single per-constraint field** — promotion and
rollback are one-line changes with **no ConstraintTemplate change** and no blast
radius beyond that one policy:

1. **Dry-run escape (preferred, non-disruptive):** set
   `enforcementAction: dryrun` on the affected constraint. Admissions are **no
   longer blocked**, but violations are **still recorded in audit**, so the
   signal is preserved while you investigate. Use this first if a deny is
   suspected of blocking a legitimate workload.
2. **Warn (soft revert):** set `enforcementAction: warn` to admit with a visible
   admission warning — louder than dryrun, still non-blocking.
3. **Re-promote:** set `enforcementAction: deny` again once the violation is
   fixed or the carve-out (`excludedNamespaces` / `allowedRegistries` /
   `allowedImages`) is updated.

Prefer narrowing a carve-out over a blanket dryrun/warn revert when only a
specific namespace or image is affected — the carve-outs already exempt
`kube-system`, `kube-public`, `gatekeeper-system` (and per-constraint extras
like `monitoring`, `external-secrets`, AWS system registries, and CNI images).

## Exempted Namespaces

The following namespaces are exempt from policy enforcement:
- `kube-system`
- `kube-public`
- `kube-node-lease`
- `gatekeeper-system`
- `cert-manager`
- `external-secrets`

## Viewing Violations

```bash
# List all constraint violations
kubectl get constraints -A -o yaml | grep -A5 "violations:"

# Check specific constraint
kubectl describe k8srequiresecuritycontext require-security-context
```

## Adding New Policies

1. Create a ConstraintTemplate in `templates/constraints/`
2. Create a Constraint that references the template
3. Start with `enforcementAction: dryrun` (audit-only) or `warn`
4. Soak and fix violations until audit is clean
5. Promote to `deny` (record the transition in the
   `policy.qbiq.io/enforcement-graduation` annotation)

## Metrics

Gatekeeper exposes Prometheus metrics on port 8888:
- `gatekeeper_violations` - Current violation count
- `gatekeeper_constraint_templates` - Template count
- `gatekeeper_audit_duration_seconds` - Audit duration
