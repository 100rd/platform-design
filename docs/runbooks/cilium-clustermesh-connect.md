# Runbook: connect two EKS clusters with Cilium ClusterMesh (WireGuard)

Implements **ADR-0043 D2** for the staging cross-region pair:

| | Cluster A | Cluster B |
|---|---|---|
| Stack | `staging/eu-west-1/platform` | `staging/eu-central-1/platform` |
| Cilium cluster name / id | `staging-euw1` / **1** | `staging-euc1` / **2** |
| VPC CIDR | 10.10.0.0/16 | 10.13.0.0/16 (non-overlapping ✓) |

Encryption: **WireGuard** pod-to-pod is already on (`enable_encryption=true`,
`encryption_type=wireguard` in `catalog/units/cilium`), so all cross-cluster pod traffic
is encrypted. ClusterMesh adds cross-cluster service discovery + identity policy on top.

## What the IaC already wires (this PR)

- `enable_clustermesh=true` (staging `account.hcl`) → the `cilium` module renders the
  clustermesh-apiserver behind an **internal NLB**, distinct `cluster.id` per region (from
  `clustermesh_cluster_ids`), TLS auto, and `hubble.peerService`.
- `clustermesh-sg-rules` opens the peer VPC CIDRs on the node SG for the four ports:
  **2379** (etcd API), **4240** (health), **4244** (Hubble relay), **51871/UDP** (WireGuard).
- `clustermesh-connect` (added to both stacks) writes the `cilium-clustermesh-<remote>`
  secret on each cluster, reading the peer's CA/cert/key from **AWS Secrets Manager**.
  Gated by `clustermesh_connect_enabled` (default **false**).

## Prerequisites (substrate — ADR-0005 / 0013)

1. **L3 reachability** between the two VPCs over the **peered Transit Gateway**
   (cross-region TGW peering + routes in the network account). Verify a pod IP in A can
   reach a pod IP in B before enabling the mesh.
2. **Non-overlapping pod CIDRs** — guaranteed here by Cilium ENI mode + the deterministic
   `cidr_map` (10.10 vs 10.13). Do not enable ClusterMesh if a future pair overlaps.

## One-time bring-up (apply-gated, run from CI on `main`)

1. **Apply both stacks with `enable_clustermesh=true`** (already set). This brings up the
   clustermesh-apiserver + internal NLB + WireGuard in each region. `clustermesh_connect_enabled`
   stays **false** for now.

2. **Capture each cluster's apiserver endpoint** (internal NLB DNS) and update the
   `endpoint` fields in `account.hcl > clustermesh_remote_clusters` if they differ from the
   `clustermesh-apiserver.<name>.internal:2379` convention.

3. **Exchange certs into Secrets Manager.** On each cluster, export the etcd CA + a client
   cert/key for the remote and store them as the secrets named in `clustermesh_remote_clusters`:

   ```sh
   # On cluster B (staging-euc1), publish B's material for A to consume:
   kubectl --context staging-euc1 -n kube-system get secret clustermesh-apiserver-remote-cert -o json \
     | jq -r '.data["tls.crt"] | @base64d' > euc1-client.crt
   #   ...ca.crt, tls.key similarly...
   aws secretsmanager put-secret-value --secret-id staging/eu-central-1/clustermesh/ca-cert     --secret-string file://euc1-ca.crt
   aws secretsmanager put-secret-value --secret-id staging/eu-central-1/clustermesh/client-cert --secret-string file://euc1-client.crt
   aws secretsmanager put-secret-value --secret-id staging/eu-central-1/clustermesh/client-key  --secret-string file://euc1-client.key
   # Repeat on cluster A → staging/eu-west-1/clustermesh/*
   ```

   The repo's secrets stack already replicates Secrets Manager across regions, so each
   cluster's connect unit can read its peer's secrets locally.

   > Shared CA: both clusters must trust the same Cilium CA. Either install a shared
   > `cilium-ca` into both before first apiserver start, or use the per-cluster cert flow
   > above. Full CA-rotation procedure stays in `docs/runbooks/cilium-clustermesh-ca-rotation.md`.

4. **Flip `clustermesh_connect_enabled = true`** in `staging/account.hcl`, re-plan, review,
   and apply. Each connect unit now writes the `cilium-clustermesh-<remote>` secret and the
   clusters join the mesh.

## Verify

```sh
# Mesh is up from each side
cilium --context staging-euw1 clustermesh status --wait
cilium --context staging-euc1 clustermesh status --wait

# WireGuard is carrying the traffic (encrypted peers > 0)
kubectl --context staging-euw1 -n kube-system exec ds/cilium -- cilium status | grep -i Encryption
# Expect: Encryption: Wireguard ...

# End-to-end (after applying apps/infra/clustermesh-demo):
kubectl --context staging-euw1 -n clustermesh-demo logs deploy/frontend --tail=5
# Expect successful GET responses served by backend pods in cluster B.

# Connectivity test across the mesh
cilium --context staging-euw1 connectivity test --multi-cluster staging-euc1
```

## Rollback

- Set `clustermesh_connect_enabled = false` → connect secrets removed; clusters leave the
  mesh (same-cluster policies unaffected).
- Set `enable_clustermesh = false` → apiserver + cross-cluster SG rules removed. WireGuard
  pod encryption stays on (independent of ClusterMesh).

## References

- ADR-0043 (cross-cluster connectivity), ADR-0019 (ClusterMesh pilot), ADR-0005 (TGW),
  ADR-0013 (inter-VPC security), ADR-0003 (Cilium).
- Cilium ClusterMesh: <https://docs.cilium.io/en/stable/network/clustermesh/clustermesh/>
- Demo manifests: `apps/infra/clustermesh-demo/`.
