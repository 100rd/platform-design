# Runbook: Automatic Failover via Global Accelerator Health Checks

## Overview

AWS Global Accelerator continuously monitors the health of NLB endpoints in each region. When an NLB fails health checks, GA automatically routes traffic to the nearest healthy endpoint group. No manual intervention is needed for NLB-level failures.

## How Automatic Failover Works

### Health Check Configuration

The Global Accelerator endpoint groups are configured with the following health check parameters:

| Parameter | Value |
|---|---|
| Protocol | TCP |
| Port | 443 (NLB listener port) |
| Interval | 10 seconds |
| Threshold (unhealthy) | 3 consecutive failures |
| Threshold (healthy) | 3 consecutive successes |

With a 10-second interval and a threshold of 3, it takes approximately **30 seconds** for GA to detect an unhealthy endpoint and begin rerouting traffic.

### Failover Sequence

1. **Health check failure detected**: GA health probes to the NLB in region A fail 3 times consecutively (30 seconds).
2. **Endpoint marked unhealthy**: GA marks the endpoint group for region A as unhealthy.
3. **Traffic rerouted**: All new connections are routed to the healthy endpoint group in region B. Existing TCP connections to region A will eventually time out and reconnect to region B.
4. **No DNS change required**: GA uses anycast IPs, so clients do not need a DNS update. Rerouting happens at the network layer.

### What Triggers Automatic Failover

- NLB becomes unreachable (e.g., AZ failure affecting all NLB nodes)
- NLB target group has zero healthy targets (all pods failed readiness probes)
- Network connectivity loss between GA edge and the NLB
- Region-level outage affecting the NLB's availability

### What Does NOT Trigger Automatic Failover

- Application-level errors (5xx responses) -- GA health checks only verify TCP connectivity, not HTTP status codes
- Partial degradation where NLB is still reachable but some pods are unhealthy
- ClusterMesh disconnection (this is internal and not monitored by GA)
- High latency without packet loss

For application-level failures, use the [manual failover runbook](failover-manual.md).

## Monitoring Automatic Failover Events

### CloudWatch Metrics

Global Accelerator publishes metrics to CloudWatch in `us-west-2`:

```
Namespace: AWS/GlobalAccelerator
Metrics:
  - HealthyEndpointCount   (per endpoint group)
  - UnhealthyEndpointCount (per endpoint group)
  - NewFlowCount           (per listener)
  - ProcessedBytesIn       (per listener)
```

### CloudWatch Alarm (Recommended)

Set an alarm on `HealthyEndpointCount` dropping below 1 for any endpoint group:

```
Metric: AWS/GlobalAccelerator → HealthyEndpointCount
Dimension: EndpointGroup = <endpoint-group-arn>
Statistic: Minimum
Period: 60 seconds
Threshold: < 1
Action: SNS → ops-alerts
```

### Grafana Dashboard

The `multiregion-overview` dashboard includes panels for:
- **Healthy Host Count** per endpoint group -- drops to 0 during failover
- **New Flow Count** per region -- spikes on the healthy region during failover
- **Processed Bytes** per region -- shifts entirely to the healthy region

### CloudTrail Events

GA endpoint group state changes are logged in CloudTrail:

```
Event name: UpdateEndpointGroup
Source: globalaccelerator.amazonaws.com
```

These events are logged automatically when GA marks endpoints unhealthy, without any API call from your side.

## Recovery After Automatic Failover

When the failed region recovers:

1. GA health probes start succeeding again (3 consecutive successes = ~30 seconds).
2. GA automatically marks the endpoint group as healthy.
3. New connections are again distributed across both regions.

**Important**: Recovery is also automatic. There is no manual step to "bring the region back." If you need controlled recovery (gradual ramp-up), set the recovered region's traffic dial to a low percentage before it recovers, then ramp up manually. See [manual failover runbook](failover-manual.md) for the ramp-up procedure.

## Testing Automatic Failover

To test failover behavior without causing a real outage:

1. Scale all deployments behind the NLB to 0 in one region:
   ```bash
   kubectl --context eu-west-1 -n production scale deployment --all --replicas=0
   ```
2. Wait for NLB target group to report 0 healthy targets.
3. Observe GA health checks failing and traffic shifting on the Grafana dashboard.
4. Restore replicas:
   ```bash
   kubectl --context eu-west-1 -n production scale deployment --all --replicas=3
   ```
5. Confirm GA detects healthy targets and rebalances traffic.

Schedule regular failover tests (at least quarterly) to validate the end-to-end recovery path.
