# Kyverno

Kubernetes Native Policy Management engine for validating, mutating, and generating resources.

## Overview

Kyverno is a policy engine designed specifically for Kubernetes. Unlike OPA Gatekeeper, policies are written as Kubernetes resources (no Rego required).

## Features

- **Validate**: Block non-compliant resources
- **Mutate**: Modify resources on creation/update
- **Generate**: Create resources automatically
- **Verify Images**: Validate container image signatures
- **Cleanup**: Automatically delete resources based on policies

## Status

**Disabled by default.** Enable by setting `kyverno.enabled: true` in values.yaml.

## Comparison with OPA Gatekeeper

| Feature | Kyverno | Gatekeeper |
|---------|---------|------------|
| Policy Language | YAML (native K8s) | Rego |
| Learning Curve | Lower | Higher |
| Mutation Support | Native | Experimental |
| Generation | Yes | No |
| Image Verification | Built-in | External |
| Policy Reports | Native | Requires add-on |

**Recommendation**: Choose one policy engine. If already using Gatekeeper, evaluate migration vs running both.

## Quick Start

1. Enable Kyverno:
   ```yaml
   # values.yaml
   kyverno:
     enabled: true
   ```

2. Deploy a sample policy:
   ```yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata:
     name: require-labels
   spec:
     validationFailureAction: Audit
     rules:
       - name: check-team-label
         match:
           any:
             - resources:
                 kinds:
                   - Pod
         validate:
           message: "Label 'team' is required"
           pattern:
             metadata:
               labels:
                 team: "?*"
   ```

3. Check policy reports:
   ```bash
   kubectl get policyreport -A
   kubectl get clusterpolicyreport
   ```

## Architecture

```
                    +-----------------------+
                    |   Admission Webhook   |
                    |   (Validate/Mutate)   |
                    +-----------+-----------+
                                |
        +-----------------------+-----------------------+
        |                       |                       |
+-------v-------+       +-------v-------+       +-------v-------+
|  Background   |       |   Cleanup     |       |   Reports     |
|  Controller   |       |  Controller   |       |  Controller   |
| (Generate)    |       | (TTL cleanup) |       | (PolicyReport)|
+---------------+       +---------------+       +---------------+
```

## Monitoring

Kyverno exposes Prometheus metrics:

- `kyverno_policy_results_total` - Policy evaluation results
- `kyverno_admission_review_duration_seconds` - Webhook latency
- `kyverno_controller_reconcile_total` - Controller reconciliation

## Resources

- [Documentation](https://kyverno.io/docs/)
- [Policy Library](https://kyverno.io/policies/)
- [Helm Chart](https://github.com/kyverno/kyverno/tree/main/charts/kyverno)
