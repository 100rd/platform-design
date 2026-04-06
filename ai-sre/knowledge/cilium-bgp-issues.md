# Cilium BGP Session Issues

## BGP Session Flap Diagnosis

### Symptoms
- Cilium BGP peer state alternating between Established and Active
- Pod-to-pod connectivity intermittent across nodes
- `cilium_bgp_peer_status` metric flapping between 1 and 0

### Investigation Steps
1. Check BGP peer status: `cilium bgp peers`
2. Look at BGP session logs: `kubectl logs -n kube-system -l k8s-app=cilium | grep BGP`
3. Check for MTU issues: ensure MTU consistent across path
4. Verify ToR switch BGP config matches Cilium peering config

### Common Causes

#### Hold Timer Too Aggressive
- Default: 90s hold, 30s keepalive
- If CPU pressure on node, keepalives may be delayed
- Fix: Increase hold timer to 180s

#### Route Limit Exceeded
- Large clusters may exceed default route table limits on ToR
- Fix: Increase max-prefix on ToR BGP config

#### Network Partition
- AWS AZ partition can break BGP peering
- Check: `aws ec2 describe-instance-status` for AZ health
- Cilium will re-establish after partition heals
