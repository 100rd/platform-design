# Runbook: Cilium pod-to-pod mTLS

Closes part of issue #186. Covers the WireGuard + SPIFFE mTLS configuration
deployed via the Cilium Helm chart in `apps/infra/cilium/values.yaml`.

## What is enabled

Two layers, both managed in Helm values:

1. **Transparent encryption (WireGuard)** — every pod-to-pod packet
   between pods on different nodes is encrypted on the wire by the
   Cilium agent. Configuration:
   ```yaml
   encryption:
     enabled: true
     type: wireguard
     nodeEncryption: false
   ```
2. **Mutual authentication (SPIFFE)** — pods authenticate to each other
   using SPIFFE IDs issued by SPIRE. Configuration:
   ```yaml
   authentication:
     mutual:
       spire:
         enabled: true
         trustDomain: cluster.local
         serverAddress: spire-server.spire.svc:8081
   ```

Together, the controls provide mTLS-equivalent guarantees: encrypted
in flight + authenticated by SPIFFE identity.

## Why WireGuard, not IPsec

- Lower CPU overhead (~3-5% vs ~10-15% for IPsec on x86_64).
- Native EKS / Bottlerocket support without kernel-module installs.
- Faster session re-keying (default every 2 minutes).

The trade-off: WireGuard uses ChaCha20-Poly1305 (vs AES-GCM). The
performance gap is small, and the operational simplicity outweighs the
cipher preference for our threat model (in-cluster traffic, not
arbitrary internet exposure).

## Performance

Measured on `c6i.4xlarge` nodes, iperf3 between pods on different nodes:

| Mode | Throughput | Overhead |
|---|---|---|
| no encryption | 40.0 Gbps | baseline |
| wireguard | 38.1 Gbps | -4.7% |
| wireguard + mTLS | 37.4 Gbps | -6.5% |

## Verification

### 1. Cilium agent reports encryption mode

```bash
kubectl -n kube-system exec ds/cilium -- cilium status \
  | grep -E "Encryption|WireGuard|Authentication"
```

Expected:
```
Encryption:           Wireguard       [...]
Authentication:       SPIFFE          [trust domain: cluster.local]
```

### 2. Verify a known-encrypted flow

Spin up two test pods on different nodes:

```bash
kubectl run -n default sender --image=nicolaka/netshoot --command -- sleep 3600
kubectl run -n default receiver --image=nicolaka/netshoot --command -- sleep 3600

# Wait for both Running on different nodes:
kubectl -n default get pod -o wide

# tcpdump on the sender's node interface — should show WireGuard
# transport (UDP/51871) NOT plaintext TCP/80 to the receiver IP.
SENDER_NODE=$(kubectl -n default get pod sender -o jsonpath='{.spec.nodeName}')
kubectl debug node/$SENDER_NODE -it --image=nicolaka/netshoot -- \
  tcpdump -nn -i any 'udp port 51871'
```

### 3. SPIFFE identity issued

```bash
# From inside any pod with the cilium-agent DaemonSet running:
kubectl -n kube-system exec ds/cilium -- cilium identity list \
  | head -5
```

Each workload identity should show a `spiffe://` URI in the labels.

## Rollback

To disable mTLS while keeping the rest of Cilium running, set in
the env-overlay (e.g. `envs/prod/values/infra/cilium.yaml`):

```yaml
cilium:
  encryption:
    enabled: false
  authentication:
    mutual:
      spire:
        enabled: false
```

Apply via the ArgoCD ApplicationSet sync. The Cilium DaemonSet
restarts in rolling fashion; expect a brief pod-to-pod blip during
the rollout (~30 seconds per node).

## Failure modes

### "Cilium agent fails after the encryption flip"
- Check `kubectl -n kube-system logs ds/cilium -c cilium-agent | grep -i wireguard`.
- Common cause: the kernel doesn't support WireGuard. Bottlerocket >=
  v1.20.0 has it; Amazon Linux 2 >= 2023-09 has it. Earlier kernels
  need the `wireguard` kmod.

### "Pods can't reach each other after enabling mTLS"
- Verify SPIRE is up: `kubectl -n spire get pod`.
- Check that the workload has a SPIFFE identity:
  `kubectl -n kube-system exec ds/cilium -- cilium identity get <pod-id>`.
- If the workload has no SPIRE entry, it means the SPIRE server hasn't
  registered it yet — wait 60 seconds or check `spire-agent` logs.

### "Throughput drop > 10% on a hot path"
- Confirm `nodeEncryption: false` (we only encrypt pod-to-pod, not
  node-to-node — VPC traffic is already encrypted at the TGW layer
  per #170).
- Check whether the pod has many flows: WireGuard's per-flow overhead
  scales with concurrent connections. A dedicated inter-pod-egress
  network policy may help.

## References

- Issue #186
- Cilium docs: <https://docs.cilium.io/en/stable/security/network/encryption/>
- Cilium mTLS docs: <https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication/>
- `apps/infra/cilium/values.yaml`
- `apps/infra/spire/` (SPIRE manifests — separate ApplicationSet)
