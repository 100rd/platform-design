# Runbook: Manual Regional Failover

## Overview

This runbook describes how to manually fail traffic away from a degraded region by setting the Global Accelerator traffic dial to 0% for that region's endpoint group. Use this when automated health checks have not triggered failover, or when you need a controlled maintenance window.

## Prerequisites

- AWS CLI v2 configured with permissions for `globalaccelerator:*`
- Global Accelerator ARN and endpoint group ARNs (see Terraform outputs)
- Access to Grafana dashboards: `multiregion-overview`, `clustermesh-status`

## Procedure

### 1. Identify the Failing Region

Check the multi-region overview dashboard for anomalies:
- Healthy Host Count dropping to 0 for a region
- Error rate spike on one region's request rate panel
- Pod count drop for the affected region

Confirm the affected endpoint group:

```bash
aws globalaccelerator list-endpoint-groups \
  --listener-arn <LISTENER_ARN> \
  --region us-west-2
```

Note the `EndpointGroupArn` for the affected region (e.g., `eu-west-1`).

### 2. Set Traffic Dial to 0% for the Affected Region

```bash
aws globalaccelerator update-endpoint-group \
  --endpoint-group-arn <AFFECTED_ENDPOINT_GROUP_ARN> \
  --traffic-dial-percentage 0 \
  --region us-west-2
```

Global Accelerator is a global service but the API endpoint is `us-west-2`.

### 3. Verify Traffic Has Shifted

Wait 30-60 seconds for DNS propagation, then verify:

```bash
# Check that the healthy region is receiving all traffic
aws globalaccelerator describe-endpoint-group \
  --endpoint-group-arn <HEALTHY_ENDPOINT_GROUP_ARN> \
  --region us-west-2
```

On Grafana (`multiregion-overview` dashboard):
- The healthy region's request rate should increase to absorb the failed region's traffic.
- The failed region's processed bytes should drop to zero.
- Healthy Host Count for the affected region should show 0.

### 4. Monitor the Healthy Region

After failover, monitor the healthy region for capacity stress:

- **Pod count**: Ensure HPA scales up to handle doubled traffic.
- **Node count**: Ensure Karpenter launches additional nodes if needed.
- **Latency**: Cross-region users will have higher latency; confirm it stays within SLA.
- **Error rate**: Confirm no cascading failures from the load increase.

### 5. Investigate the Root Cause

While traffic is diverted, investigate the failing region:

```bash
# Check EKS cluster status
aws eks describe-cluster --name platform-eu-west-1 --region eu-west-1

# Check node status
kubectl --context eu-west-1 get nodes

# Check Cilium health
kubectl --context eu-west-1 -n kube-system exec ds/cilium -- cilium-health status

# Check ClusterMesh status
kubectl --context eu-west-1 -n kube-system exec ds/cilium -- cilium clustermesh status
```

## Recovery Procedure

### 1. Confirm the Region is Healthy

Before restoring traffic, verify:

- [ ] All EKS nodes are `Ready`
- [ ] Cilium agents are healthy on all nodes (`cilium status --brief`)
- [ ] ClusterMesh shows `connected` to the peer cluster
- [ ] Application pods are Running and passing readiness probes
- [ ] NLB health checks are passing

### 2. Gradually Restore Traffic

Ramp traffic back gradually to avoid a thundering herd:

```bash
# 10% -- smoke test
aws globalaccelerator update-endpoint-group \
  --endpoint-group-arn <RECOVERED_ENDPOINT_GROUP_ARN> \
  --traffic-dial-percentage 10 \
  --region us-west-2
```

Wait 5 minutes and monitor error rates.

```bash
# 50%
aws globalaccelerator update-endpoint-group \
  --endpoint-group-arn <RECOVERED_ENDPOINT_GROUP_ARN> \
  --traffic-dial-percentage 50 \
  --region us-west-2
```

Wait 5 minutes and monitor.

```bash
# 100% -- full restore
aws globalaccelerator update-endpoint-group \
  --endpoint-group-arn <RECOVERED_ENDPOINT_GROUP_ARN> \
  --traffic-dial-percentage 100 \
  --region us-west-2
```

### 3. Verify Balanced Traffic

On the `multiregion-overview` dashboard, confirm:
- Both regions show healthy host counts > 0
- Request rates are balanced across both regions
- Error rates are within normal thresholds

## Rollback

If the recovered region starts failing again during the ramp-up, immediately set the traffic dial back to 0%:

```bash
aws globalaccelerator update-endpoint-group \
  --endpoint-group-arn <RECOVERED_ENDPOINT_GROUP_ARN> \
  --traffic-dial-percentage 0 \
  --region us-west-2
```

Then continue investigating the root cause before attempting recovery again.
