# EKS Upgrade Checklist

## Pre-Upgrade Verification
1. Check API deprecations: `kubectl deprecations` or Pluto scan
2. Verify all addons compatible with target version
3. Check Karpenter version compatibility matrix
4. Ensure PodDisruptionBudgets are configured for critical workloads
5. Verify etcd snapshot exists (AWS manages, but confirm backup)
6. Run `kubectl get nodes` — all nodes should be Ready
7. Check cluster autoscaler / Karpenter has spare capacity for rolling update

## During Upgrade
1. Control plane upgrade first (AWS-managed, ~15 min)
2. Monitor API server availability: `apiserver_request_duration_seconds`
3. After control plane: upgrade managed node groups
4. Watch for pod disruption: `kube_pod_status_phase{phase="Pending"}`
5. Karpenter nodes: drift detection will roll nodes automatically

## Post-Upgrade Verification
1. `kubectl get nodes` — all nodes on target version
2. ArgoCD sync status — all apps healthy
3. GPU operator — DCGM exporter running on all GPU nodes
4. Network policies — Cilium agent running on all nodes
5. VictoriaMetrics — metrics flowing from all clusters
6. Run smoke tests for critical services

## Rollback Triggers
- API server error rate > 1% sustained for 5 minutes
- More than 10% of pods in Pending/CrashLoopBackOff
- GPU operator unable to schedule on any node
- Cilium agent CrashLoopBackOff on multiple nodes
