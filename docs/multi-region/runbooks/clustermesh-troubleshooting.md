# Runbook: ClusterMesh Troubleshooting

## Overview

This runbook covers common issues with Cilium ClusterMesh connectivity between the `eu-west-1` and `eu-central-1` EKS clusters, including diagnostic commands and resolution steps.

## Diagnostic Commands

### Check ClusterMesh Status

```bash
# From any Cilium agent pod
kubectl --context <CLUSTER> -n kube-system exec ds/cilium -- cilium clustermesh status

# Expected output when healthy:
#   eu-central-1:
#     status: connected
#     ...
```

### Check Cilium Agent Health

```bash
kubectl --context <CLUSTER> -n kube-system exec ds/cilium -- cilium-health status
```

### Check ClusterMesh API Server

```bash
kubectl --context <CLUSTER> -n kube-system get pods -l app.kubernetes.io/name=clustermesh-apiserver

# Check logs
kubectl --context <CLUSTER> -n kube-system logs -l app.kubernetes.io/name=clustermesh-apiserver --tail=100
```

### Check Global Services

```bash
kubectl --context <CLUSTER> -n kube-system exec ds/cilium -- cilium service list --clustermesh-only
```

### Check Hubble Flows Across Clusters

```bash
kubectl --context <CLUSTER> -n kube-system exec ds/cilium -- hubble observe --from-label "io.cilium.k8s.policy.cluster=<REMOTE_CLUSTER>" --last 20
```

## Common Issues

### 1. Security Group Rules Missing

**Symptom**: `cilium clustermesh status` shows `not connected` or `connection refused`.

**Cause**: The ClusterMesh security group rules are not applied. ClusterMesh requires four ports open between the VPCs:

| Port | Protocol | Purpose |
|---|---|---|
| 2379 | TCP | ClusterMesh etcd API |
| 4240 | TCP | Cilium health checks |
| 51871 | UDP | WireGuard encrypted tunnel |
| 4244 | TCP | Hubble relay |

**Diagnosis**:

```bash
# Check SG rules on the EKS node security group
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=<NODE_SG_ID>" \
  --region <REGION> \
  --query 'SecurityGroupRules[?contains(Description, `ClusterMesh`)]'
```

**Resolution**:

Verify the `clustermesh-sg-rules` Terraform module is applied with the correct peer VPC CIDRs:

```hcl
module "clustermesh_sg_rules" {
  source = "../../modules/clustermesh-sg-rules"

  node_security_group_id = module.eks.node_security_group_id
  peer_vpc_cidrs = {
    eu-central-1 = "10.13.0.0/16"  # For eu-west-1 cluster
  }
}
```

Run `terragrunt apply` in the relevant region's stack to create the rules.

### 2. Transit Gateway Routing Issues

**Symptom**: `cilium clustermesh status` shows `connection timed out`. SG rules are correct.

**Cause**: Transit Gateway routes are missing or misconfigured, preventing cross-VPC traffic.

**Diagnosis**:

```bash
# Check TGW route tables
aws ec2 describe-transit-gateway-route-tables \
  --region <REGION>

# Check routes in the TGW route table
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <TGW_RT_ID> \
  --filters "Name=route-search.exact-match,Values=10.13.0.0/16" \
  --region eu-west-1
```

Verify VPC route tables have a route to the peer VPC CIDR via the TGW:

```bash
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --region <REGION> \
  --query 'RouteTables[].Routes[?DestinationCidrBlock==`10.13.0.0/16`]'
```

**Resolution**:

1. Confirm the TGW peering attachment is `available`:
   ```bash
   aws ec2 describe-transit-gateway-peering-attachments --region eu-west-1
   ```
2. Confirm routes exist in both TGW route tables pointing to the peering attachment.
3. Confirm VPC subnet route tables have a route to the peer CIDR via the TGW.
4. If routes are missing, run `terragrunt apply` on the `tgw-peering` stack in both regions.

### 3. CA Certificate Mismatch

**Symptom**: `cilium clustermesh status` shows `TLS handshake failure` or `certificate verify failed`.

**Cause**: Each cluster's Cilium installation generated its own CA. For ClusterMesh to work, both clusters must trust each other's CA.

**Diagnosis**:

```bash
# Check the ClusterMesh API server TLS secret
kubectl --context <CLUSTER> -n kube-system get secret cilium-clustermesh -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -text -noout
```

Compare the CA certificates on both clusters. If they differ and are not cross-signed, the connection will fail.

**Resolution**:

With `tls.auto.method = "helm"` (our configuration), Cilium auto-generates TLS certificates per cluster. ClusterMesh handles CA exchange during the mesh connection process. If the CA is stale:

1. Restart the ClusterMesh API server on both clusters:
   ```bash
   kubectl --context eu-west-1 -n kube-system rollout restart deployment clustermesh-apiserver
   kubectl --context eu-central-1 -n kube-system rollout restart deployment clustermesh-apiserver
   ```
2. Wait for pods to be Ready.
3. Re-check `cilium clustermesh status`.

If the issue persists, re-enable ClusterMesh by toggling the Helm values:

```bash
# In the affected cluster's Cilium Helm values:
cilium upgrade --set clustermesh.useAPIServer=true
```

### 4. WireGuard Tunnel Not Established

**Symptom**: Pods can reach services in the remote cluster on port 2379 (etcd), but pod-to-pod traffic is encrypted incorrectly or dropped. `cilium-health status` shows connectivity issues.

**Cause**: UDP port 51871 (WireGuard) is blocked, or WireGuard keys are not synchronized.

**Diagnosis**:

```bash
# Check WireGuard status
kubectl --context <CLUSTER> -n kube-system exec ds/cilium -- cilium encrypt status

# Check WireGuard interfaces
kubectl --context <CLUSTER> -n kube-system exec ds/cilium -- wg show
```

**Resolution**:

1. Verify UDP 51871 is open in the node security group (see issue #1 above).
2. Verify the TGW allows UDP traffic (NACLs default to allow all, but confirm).
3. If WireGuard keys are stale, restart Cilium agents:
   ```bash
   kubectl --context <CLUSTER> -n kube-system rollout restart ds/cilium
   ```

### 5. ClusterMesh API Server Not Running

**Symptom**: `cilium clustermesh status` shows `connection refused` on port 2379.

**Diagnosis**:

```bash
kubectl --context <CLUSTER> -n kube-system get pods -l app.kubernetes.io/name=clustermesh-apiserver
kubectl --context <CLUSTER> -n kube-system describe pod -l app.kubernetes.io/name=clustermesh-apiserver
```

Check for:
- `CrashLoopBackOff` -- inspect logs
- `Pending` -- check node resources and PVC availability
- Image pull errors

**Resolution**:

1. Check logs for the root cause:
   ```bash
   kubectl --context <CLUSTER> -n kube-system logs -l app.kubernetes.io/name=clustermesh-apiserver --previous
   ```
2. If etcd data is corrupted, delete the PVC and restart:
   ```bash
   kubectl --context <CLUSTER> -n kube-system delete pvc data-clustermesh-apiserver-0
   kubectl --context <CLUSTER> -n kube-system rollout restart statefulset clustermesh-apiserver
   ```
3. Re-check `cilium clustermesh status` after the pod is Running.

### 6. Global Services Not Appearing in Remote Cluster

**Symptom**: A service annotated with `service.cilium.io/global: "true"` is visible locally but not in the remote cluster.

**Diagnosis**:

```bash
# Check local service list
kubectl --context eu-west-1 -n kube-system exec ds/cilium -- cilium service list | grep <SERVICE_NAME>

# Check remote service list (should show the same service with remote backends)
kubectl --context eu-central-1 -n kube-system exec ds/cilium -- cilium service list | grep <SERVICE_NAME>
```

**Resolution**:

1. Confirm ClusterMesh is connected (`cilium clustermesh status` shows `connected`).
2. Confirm the Service has the correct annotations:
   ```bash
   kubectl --context eu-west-1 get svc <SERVICE_NAME> -n <NAMESPACE> -o jsonpath='{.metadata.annotations}'
   ```
3. Confirm the Service has endpoints (pods are Running and Ready):
   ```bash
   kubectl --context eu-west-1 get endpoints <SERVICE_NAME> -n <NAMESPACE>
   ```
4. If all looks correct, restart the Cilium agent to force a resync:
   ```bash
   kubectl --context eu-west-1 -n kube-system rollout restart ds/cilium
   ```

## Escalation

If none of the above steps resolve the issue:

1. Collect a Cilium sysdump from both clusters:
   ```bash
   cilium sysdump --output-filename sysdump-eu-west-1
   cilium sysdump --output-filename sysdump-eu-central-1
   ```
2. Check the [Cilium ClusterMesh documentation](https://docs.cilium.io/en/v1.16/network/clustermesh/) for known issues.
3. Open a support ticket with the sysdumps attached.
