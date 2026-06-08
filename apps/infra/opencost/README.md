# opencost

Per-namespace Kubernetes cost allocation reconciled to the real AWS bill.
Implements **ADR-0027** (OpenCost + AWS CUR/Athena cloud-integration).

## What this installs

| Component | Purpose |
|-----------|---------|
| OpenCost exporter | Allocates node cost across namespaces / workloads / labels |
| OpenCost UI | Optional web UI for ad-hoc cost investigation |
| ServiceMonitor | Exposes `/metrics` to the kube-prometheus-stack Prometheus |
| ExternalSecret | Materialises `cloud-integration.json` from AWS Secrets Manager (ESO v1, ADR-0008) |
| NetworkPolicy | Guards exporter and UI egress/ingress |

## Why amortized cost matters

Naive cost tools price allocation against **on-demand list rates**.
That overstates real spend on an estate running Reserved Instances, Savings Plans,
and Spot.  The CUR/Athena cloud-integration pulls the actual AWS bill so allocation
reflects what you *pay*, not what you would pay without discounts.

## Dependencies

AWS infrastructure must exist before deploying this chart:

```
terraform/modules/cost-cur-export
├── S3 bucket        — CUR delivery destination
├── Glue database    — schema-on-read over Parquet CUR files
├── Athena workgroup — query workgroup
└── IAM role         — IRSA role for OpenCost (read-only Athena/Glue/S3)
```

After running the Terraform module, populate the Secrets Manager secret at
`/opencost/cloud-integration` with the JSON payload documented in
`templates/external-secret.yaml`.

## IRSA

Annotate the ServiceAccount with the IAM role output by the Terraform module:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
```

Set this via an ArgoCD ApplicationSet `parameters` patch so the value stays
cluster-specific and out of this chart's values.

## Evolutionary path (ADR-0027)

```
Phase 1 (this chart):  OpenCost + CUR  →  discount-aware per-namespace allocation
Phase 2 (optional):    + Kubecost Free →  UI right-sizing ≤ 250 cores / 15-day retention
Phase 3 (if needed):   + Kubecost Enterprise  →  long retention / multi-cluster / RBAC
                        (only justified when Free tier bounds are demonstrably crossed)
```
