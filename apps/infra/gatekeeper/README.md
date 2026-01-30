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

| Template | Purpose | Enforcement |
|----------|---------|-------------|
| `K8sRequireSecurityContext` | Require runAsNonRoot, block privilege escalation | warn |
| `K8sBlockPrivileged` | Block privileged containers | deny |
| `K8sRequireResourceLimits` | Require memory limits | warn |
| `K8sBlockLatestTag` | Block :latest image tag | warn |

## Enforcement Modes

- `deny` - Reject non-compliant resources
- `warn` - Allow but emit warnings
- `dryrun` - Log violations without affecting workloads

## Promoting to Production

To enforce policies strictly:

1. Monitor violations in audit logs
2. Fix existing violations
3. Change `enforcementAction: warn` to `enforcementAction: deny`
4. Apply changes

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
3. Start with `enforcementAction: warn`
4. Monitor and fix violations
5. Promote to `deny`

## Metrics

Gatekeeper exposes Prometheus metrics on port 8888:
- `gatekeeper_violations` - Current violation count
- `gatekeeper_constraint_templates` - Template count
- `gatekeeper_audit_duration_seconds` - Audit duration
