# Cilium CNI

Deploys [Cilium](https://cilium.io/) as the Container Network Interface (CNI) for EKS clusters, replacing AWS VPC CNI.

## Why Cilium?

- **eBPF-powered**: High-performance networking and observability without iptables overhead
- **Hubble**: Built-in network observability with flow visibility, service maps, and metrics
- **Network Policies**: Advanced L3-L7 policies with DNS-aware filtering
- **Bottlerocket native**: Optimized for immutable container OS
- **Service Mesh ready**: Foundation for sidecar-free service mesh (Cilium Mesh)

## Architecture

### ENI IPAM Mode

Cilium runs in ENI IPAM mode, providing the same networking model as AWS VPC CNI:
- Pods get VPC-routable IP addresses
- No overlay/tunneling overhead
- Native AWS security group integration
- Prefix delegation support for high pod density

### Components

| Component | Replicas | Purpose |
|-----------|----------|---------|
| cilium-agent | DaemonSet | Per-node networking and policy enforcement |
| cilium-operator | 2 | Cluster-wide operations (IPAM, CRDs) |
| hubble-relay | 2 | Aggregates flow data from agents |
| hubble-ui | 2 | Web UI for network visualization |

## Bottlerocket Integration

Cilium is optimized for [Bottlerocket](https://bottlerocket.dev/) nodes:
- Native Cilium support (no bootstrap scripts needed)
- Faster node startup (~30s vs ~2-3min with AL2)
- Smaller attack surface (minimal OS)
- Automatic security updates

### Node Taints

Nodes start with a taint that's removed once Cilium is ready:
```yaml
taints:
  - key: node.cilium.io/agent-not-ready
    value: "true"
    effect: NoSchedule
```

## Hubble Observability

### Accessing Hubble UI

Port-forward to access the UI:
```bash
kubectl port-forward -n kube-system svc/hubble-ui 8080:80
# Open http://localhost:8080
```

### Hubble CLI

Install and use the Hubble CLI:
```bash
# Install
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-amd64.tar.gz
tar xzvf hubble-linux-amd64.tar.gz
sudo mv hubble /usr/local/bin

# Port-forward relay
kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &

# Observe flows
hubble observe --namespace default
hubble observe --verdict DROPPED
hubble observe --protocol HTTP
```

### Prometheus Metrics

Cilium and Hubble expose metrics at:
- `cilium-agent:9962/metrics` - Agent metrics
- `cilium-operator:9963/metrics` - Operator metrics
- `hubble-relay:9966/metrics` - Flow metrics

## Network Policies

### Kubernetes NetworkPolicy

Standard Kubernetes NetworkPolicies work with Cilium:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - port: 80
```

### CiliumNetworkPolicy

For advanced features, use CiliumNetworkPolicy:
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-http-get
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
          rules:
            http:
              - method: GET
                path: "/api/.*"
```

## Environment Overrides

| Environment | kube-proxy Replacement | Operator Replicas |
|-------------|------------------------|-------------------|
| dev | false | 1 |
| staging | false | 2 |
| prod | true (after validation) | 2 |

## Troubleshooting

### Check Cilium Status
```bash
kubectl -n kube-system exec ds/cilium -- cilium status
```

### Check Connectivity
```bash
kubectl -n kube-system exec ds/cilium -- cilium connectivity test
```

### View BPF Maps
```bash
kubectl -n kube-system exec ds/cilium -- cilium bpf lb list
kubectl -n kube-system exec ds/cilium -- cilium bpf endpoint list
```

### Debug Network Issues
```bash
# Check if endpoints are healthy
kubectl -n kube-system exec ds/cilium -- cilium endpoint list

# Check policy verdicts
hubble observe --verdict DROPPED --last 100
```

## Migration from VPC CNI

See [CNI Migration Runbook](../../docs/runbooks/CNI_MIGRATION.md) for detailed migration steps.
