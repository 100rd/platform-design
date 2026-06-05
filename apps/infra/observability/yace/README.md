# YACE - Yet Another CloudWatch Exporter

Wrapper chart for [`yet-another-cloudwatch-exporter`](https://github.com/nerdswords/yet-another-cloudwatch-exporter)
(nerdswords chart `0.38.0`, YACE app `v0.61.2`). YACE polls AWS CloudWatch and
re-exposes the metrics in Prometheus format so the prometheus-stack can scrape
them via a ServiceMonitor. It feeds the **AWS Infrastructure Overview** Grafana
dashboard (`grafana-dashboards` chart).

## Discovery jobs

Four CloudWatch discovery jobs are configured (period/length `300`, delay `120`
for the 5-min-resolution jobs):

| Namespace             | Key metrics                                                           |
|-----------------------|-----------------------------------------------------------------------|
| `AWS/NetworkELB`      | HealthyHostCount, UnHealthyHostCount, ActiveFlowCount, NewFlowCount, ProcessedBytes |
| `AWS/ApplicationELB`  | HealthyHostCount, UnHealthyHostCount, RequestCount, TargetResponseTime (p99), HTTPCode_Target_5XX_Count |
| `AWS/S3`              | BucketSizeBytes, NumberOfObjects (24h resolution)                     |
| `AWS/EBS`             | BurstBalance, VolumeReadOps, VolumeWriteOps, VolumeQueueLength        |

Deliberately **dropped** (see provenance commits #58/#59 in the source repo):

- **`AWS/EKS`** - not a YACE-supported discovery service in v0.61.2; EKS
  node/pod CPU & memory are already collected in-cluster by node-exporter and
  kube-state-metrics, so CloudWatch EKS metrics would be redundant.
- **`AWS/CertificateManager` (ACM)** - this platform uses an internal CA
  (cert-manager private issuer), not ACM, so there are no certs to discover.

## IRSA

The ServiceAccount `yace` (namespace `observability`) is annotated with a
**placeholder** IAM role ARN:

```
arn:aws:iam::<AWS_ACCOUNT_ID>:role/platform-observability-yace
```

Replace `<AWS_ACCOUNT_ID>` and, if needed, the role name with the IRSA role that
grants CloudWatch read access (`cloudwatch:GetMetricData`,
`cloudwatch:ListMetrics`, `tag:GetResources`, `apigateway:GET`, etc.). The role's
trust policy must allow `sub = system:serviceaccount:observability:yace`. Until
the role exists, YACE starts but CloudWatch calls fail with
`AccessDeniedException` - non-fatal (metrics absent, no crashloop).

## Cost control

CloudWatch `GetMetricData` is billed per 1000 metrics requested. Discovery jobs
cache results for the `period` window, so YACE makes ~1 CloudWatch call per
period regardless of the 60s Prometheus scrape interval.

## Provenance

Ported from `argocd@c364c6c` `apps/observability/yace`, 2026-06 sync.
Adapted to platform-design conventions: placeholder IRSA role/account (no
hardcoded org identifiers), region `eu-central-1` to match the prometheus-stack
ClusterSecretStore default.
