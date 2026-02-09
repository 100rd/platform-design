# Runbook: Region Recovery

## Overview

This runbook describes how to bring a failed region back online after an outage and gradually restore traffic via Global Accelerator. It assumes the region was either automatically or manually failed over using the procedures in [failover-auto.md](failover-auto.md) or [failover-manual.md](failover-manual.md).

## Prerequisites

- The root cause of the regional failure has been identified and resolved
- AWS CLI v2 configured with permissions for EKS, EC2, and Global Accelerator
- `kubectl` contexts configured for both clusters
- Access to Grafana dashboards

## Recovery Steps

### 1. Verify Infrastructure

#### EKS Cluster

```bash
REGION="eu-west-1"  # Replace with the recovering region
CLUSTER_NAME="platform-${REGION}"

# Check cluster status
aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
  --query 'cluster.status'
# Expected: "ACTIVE"

# Check cluster endpoint connectivity
aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
  --query 'cluster.endpoint'
# Verify the endpoint is reachable
kubectl --context "${REGION}" cluster-info
```

#### Node Health

```bash
# Check all nodes are Ready
kubectl --context "${REGION}" get nodes
# All nodes should show STATUS: Ready

# Check Karpenter is operational
kubectl --context "${REGION}" -n kube-system get pods -l app.kubernetes.io/name=karpenter
# Both pods should be Running

# Check node capacity
kubectl --context "${REGION}" top nodes
```

#### Core Services

```bash
# CoreDNS
kubectl --context "${REGION}" -n kube-system get pods -l k8s-app=kube-dns
# All pods should be Running/Ready

# Cilium
kubectl --context "${REGION}" -n kube-system get pods -l k8s-app=cilium
# All pods should be Running/Ready (one per node)

# Cilium Operator
kubectl --context "${REGION}" -n kube-system get pods -l app.kubernetes.io/name=cilium-operator
```

### 2. Verify Cilium and WireGuard

```bash
# Cilium status on each node
kubectl --context "${REGION}" -n kube-system exec ds/cilium -- cilium status --brief

# WireGuard encryption is active
kubectl --context "${REGION}" -n kube-system exec ds/cilium -- cilium encrypt status
# Should show: Encryption: WireGuard, Peers: <number>

# Cilium health (all nodes reachable)
kubectl --context "${REGION}" -n kube-system exec ds/cilium -- cilium-health status
```

### 3. Verify ClusterMesh Connectivity

```bash
# ClusterMesh API server is running
kubectl --context "${REGION}" -n kube-system get pods -l app.kubernetes.io/name=clustermesh-apiserver
# Should be Running/Ready

# ClusterMesh is connected to the peer cluster
kubectl --context "${REGION}" -n kube-system exec ds/cilium -- cilium clustermesh status
# Expected: peer cluster shows "connected"

# Verify from the peer side too
PEER_REGION="eu-central-1"  # The region that stayed healthy
kubectl --context "${PEER_REGION}" -n kube-system exec ds/cilium -- cilium clustermesh status
# Should also show the recovering cluster as "connected"
```

If ClusterMesh is not connected, follow the [ClusterMesh troubleshooting runbook](clustermesh-troubleshooting.md).

### 4. Verify Application Workloads

```bash
# Check application pods in production namespace
kubectl --context "${REGION}" -n production get pods
# All pods should be Running/Ready

# Check that global services are registered
kubectl --context "${REGION}" -n kube-system exec ds/cilium -- cilium service list --clustermesh-only

# Verify NLB target health
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN> \
  --region "${REGION}"
# All targets should be "healthy"
```

### 5. Gradual Traffic Ramp-Up via Global Accelerator

If the traffic dial was manually set to 0% (manual failover), ramp it back up gradually. If failover was automatic and the region is now healthy, GA will automatically restore traffic -- skip to step 6 for verification.

```bash
GA_REGION="us-west-2"
ENDPOINT_GROUP_ARN="<RECOVERING_ENDPOINT_GROUP_ARN>"

# Step 1: 10% traffic
aws globalaccelerator update-endpoint-group \
  --endpoint-group-arn "${ENDPOINT_GROUP_ARN}" \
  --traffic-dial-percentage 10 \
  --region "${GA_REGION}"

echo "Traffic at 10%. Monitoring for 5 minutes..."
sleep 300
```

Check Grafana `multiregion-overview` dashboard:
- [ ] Request rate is appearing for the recovering region
- [ ] Error rate is within normal bounds
- [ ] Latency is acceptable

```bash
# Step 2: 50% traffic
aws globalaccelerator update-endpoint-group \
  --endpoint-group-arn "${ENDPOINT_GROUP_ARN}" \
  --traffic-dial-percentage 50 \
  --region "${GA_REGION}"

echo "Traffic at 50%. Monitoring for 5 minutes..."
sleep 300
```

Check Grafana again:
- [ ] No error rate increase
- [ ] Pod scaling is handling the load (HPA active)
- [ ] No OOMKills or CrashLoopBackOffs

```bash
# Step 3: 100% traffic (full restore)
aws globalaccelerator update-endpoint-group \
  --endpoint-group-arn "${ENDPOINT_GROUP_ARN}" \
  --traffic-dial-percentage 100 \
  --region "${GA_REGION}"

echo "Traffic fully restored."
```

### 6. Post-Recovery Verification

Confirm steady state on both dashboards:

**multiregion-overview**:
- [ ] Both regions show healthy host count > 0
- [ ] Request rates are balanced across both regions
- [ ] Processed bytes flowing through both endpoint groups
- [ ] No latency anomalies

**clustermesh-status**:
- [ ] Connected clusters = 2
- [ ] API Server healthy in both clusters
- [ ] Cross-cluster services are discovered
- [ ] Identity sync is complete

### 7. Post-Incident Review

After successful recovery:

1. Document the timeline: when the failure was detected, when failover occurred, when recovery completed.
2. Record the root cause and any infrastructure changes made.
3. Update monitoring/alerting if the detection was too slow.
4. Schedule a post-incident review within 48 hours.
5. If the failure was due to a gap in automation, create a ticket to address it.
