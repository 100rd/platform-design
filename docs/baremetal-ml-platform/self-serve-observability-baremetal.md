# Self-Serve Observability — Bare-Metal (Talos) Platform

> **Plan-only document.** This runbook describes the **target state** for
> WS-D of the Bare-Metal ML Platform. No `helm install`, `kubectl apply`, or
> `terraform apply` is implied. All steps are apply-gated and require human
> review + CI go-ahead before execution. Nothing is ever applied to real
> hardware in this mock/emulation repo.
>
> For the cloud (EKS/GCP) self-serve runbook see
> [`docs/self-serve-observability.md`](../self-serve-observability.md).

---

## Overview

WS-D delivers **templated per-team Grafana folders + alert-rules-as-code** for
teams running workloads on the Talos Linux bare-metal cluster (UK primary +
standby DCs). It **reuses** `apps/infra/grafana-self-serve` (ADR-0039) and the
existing Prometheus / Grafana / Loki / Tempo / Alertmanager observability stack
already specified in `docs/transaction-analytics/06-uk-datacenters.md`.

The bare-metal delta over the cloud plan is a set of **bare-metal-specific
starter panels and alert groups** that the cloud plan did not need:

| Panel group | Substrate reason |
|---|---|
| Talos node health | Self-operated immutable OS; no managed node-health API |
| IB / RoCE fabric + NVLink | 400 Gbps InfiniBand + NVSwitch (ADR-0053); no cloud NIC abstraction |
| Cilium BGP sessions | Cilium LB-IPAM + BGP to ToR switches (ADR-0051); no cloud LB |
| Ceph cluster health | Rook-Ceph block/FS/RGW (ADR-0052); no managed object store |
| etcd + control plane | Self-operated control plane + etcd (ADR-0049); no managed API server |

---

## Architecture

```
Team PR (values.yaml + argocd-application.yaml)
    │
    ▼
ArgoCD syncs grafana-self-serve Helm chart (sync-wave 30)
    │
    ├── ConfigMap  <team-slug>-grafana-folder          (grafana_namespace)
    ├── ConfigMap  <team-slug>-grafana-dashboard       (grafana_namespace)
    ├── ConfigMap  <team-slug>-grafana-baremetal-dashboard  (grafana_namespace; baremetal.enabled=true)
    ├── PrometheusRule  <team-slug>-alerts             (team_namespace)
    ├── PrometheusRule  <team-slug>-baremetal-alerts   (team_namespace; baremetal.enabled=true)
    ├── Role / RoleBinding — PrometheusRule mgmt       (team_namespace; if ciServiceAccount set)
    └── Role / RoleBinding — Grafana ConfigMap writer  (grafana_namespace; if ciServiceAccount set)

Terraform module baremetal-grafana-self-serve (optional, for Loki access):
    └── ClusterRole / ClusterRoleBinding  <team-slug>-loki-log-reader
```

### Reused stack (do not redeploy)

The following are already provisioned by the platform team:

- Prometheus 3.x / Thanos — scraping `talos-nodes`, `node-exporter`,
  `dcgm-exporter`, `ceph-mgr`, `etcd`, `kube-apiserver`, `cilium-agent` endpoints
- Grafana — sidecar watching `grafana_dashboard: "1"` ConfigMaps
- Loki — `talos-log-shipper` ships Talos machine logs (as specified in
  `docs/transaction-analytics/06-uk-datacenters.md`)
- Tempo — OTel traces
- Alertmanager — routes to PagerDuty per existing config

---

## Team onboarding path (template PR)

### Step 1 — Copy the example team

```bash
cp -r apps/infra/grafana-self-serve/example-teams/team-baremetal-gpu \
       apps/infra/grafana-self-serve/example-teams/team-<your-slug>
```

### Step 2 — Edit `values.yaml`

Minimum required fields:

```yaml
team:
  name: "My Team"
  slug: "team-my-team"        # lowercase, hyphens only
  namespace: "my-team"        # must already exist on the cluster
  system: "my-system"         # ADR-0028 platform:system value
  owner: "team-my-team"       # ADR-0028 platform:owner value
  env: "production"
  ciServiceAccount: "my-team-ci"

baremetal:
  enabled: true
  nodeSelectorRegex: "uk-primary-gpu-.*"  # scope to your nodes
  bgpPeerFilter: "10\\.0\\.200\\.(1|2)"   # scope to your ToR peers
```

Set `ml.enabled: true` additionally if your team runs ML models (adds ADR-0038
drift + accuracy panels and ML alert groups).

All available options and their defaults are documented in
`apps/infra/grafana-self-serve/values.yaml`.

### Step 3 — Edit `argocd-application.yaml`

Replace:
- `metadata.name`: `grafana-self-serve-team-<your-slug>`
- `metadata.labels["platform.owner"]`: your slug
- `spec.source.helm.valueFiles[-1]`: `example-teams/team-<your-slug>/values.yaml`
- `spec.destination.server`: the registered cluster server URL for your DC
- `spec.destination.namespace`: your team's namespace

The destination server URL is the URL registered in the ArgoCD cluster secret
for the UK DC cluster (not `https://kubernetes.default.svc`).

### Step 4 — Open a template PR

Title format: `feat(observability): onboard team-<your-slug> self-serve (baremetal)`

PR checklist:

- [ ] `helm lint apps/infra/grafana-self-serve --values apps/infra/grafana-self-serve/values.yaml --values apps/infra/grafana-self-serve/example-teams/team-<your-slug>/values.yaml` passes
- [ ] `helm template ...` renders the expected ConfigMaps and PrometheusRules
- [ ] `baremetal.enabled: true` produces a `<team-slug>-grafana-baremetal-dashboard` ConfigMap and a `<team-slug>-baremetal-alerts` PrometheusRule in rendered output
- [ ] ArgoCD Application has `CreateNamespace=false`
- [ ] All ADR-0028 labels present: `platform.system`, `platform.component`, `platform.env`, `platform.owner`, `platform.managed-by`
- [ ] sync-wave annotation is `"30"`

### Step 5 — Loki access (optional Terraform)

On the bare-metal cluster, Loki log access is RBAC-gated (unlike cloud deployments
that use IAM). If your team needs Grafana Loki panel editing:

1. Add a `self_serve_config` block in the live-tree `dc.hcl` for your DC:

   ```hcl
   locals {
     self_serve_config = {
       enabled            = true
       team_slug          = "team-my-team"
       team_namespace     = "my-team"
       ci_service_account = "my-team-ci"
       create_loki_access = true
       loki_namespace     = "observability"
     }
   }
   ```

2. Add a Terragrunt unit directory `terragrunt/uk/primary/platform/baremetal-grafana-self-serve/`
   sourcing `catalog/units/baremetal-grafana-self-serve`.

3. CI runs `terraform validate` + `terraform test` — both must pass before merge.

---

## Bare-metal panels reference

### Talos node health (ADR-0049)

| Panel | Metric | Purpose |
|---|---|---|
| Talos Nodes Up | `up{job="talos-nodes", node=~"..."}` | Count of reachable Talos scrape targets |
| Talos Version Distribution | `count by (version) (talos_version{...})` | Detect version skew during rolling A/B upgrades |
| Talos machined API Errors | `talos_apid_request_total{code!="OK"}` | Config + upgrade errors on the immutable OS |

Default alerts: `TalosNodeDown` (critical, 5m), `TalosVersionSkew` (warning, 30m),
`TalosAPIdErrors` (warning, 5m).

### IB / RoCE fabric + NVLink (ADR-0053)

| Panel | Metric | Purpose |
|---|---|---|
| InfiniBand Port Throughput | `node_infiniband_port_data_{transmitted,received}_bytes_total` | Fabric saturation and asymmetry |
| NVLink Bandwidth per GPU | `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` | NVSwitch utilisation per H100/H200 |
| IB Constraint Errors | `node_infiniband_port_error_receive_constraint_errors_total` | MTU/credit errors that silently degrade NCCL to TCP |

Default alerts: `IBConstraintErrors` (warning, 5m), `NVLinkBandwidthLow` (warning, 10m).

See `ai-sre/knowledge/nccl-troubleshooting.md` for the NCCL all-reduce bandwidth
acceptance test procedure (ADR-0053 gate).

### Cilium BGP sessions (ADR-0051)

| Panel | Metric | Purpose |
|---|---|---|
| Cilium BGP Peer State Table | `cilium_bgp_peer_state` | Live session state per ToR peer |
| BGP Announced Prefixes | `cilium_bgp_announced_prefixes` | Prefix count relative to ToR max-prefix limit |

Default alerts: `CiliumBGPSessionDown` (critical, 5m), `CiliumBGPPrefixCountHigh` (warning, 5m).

Runbook: `ai-sre/knowledge/cilium-bgp-issues.md`. Fallback: MetalLB L2 (ADR-0051).

### Ceph cluster health (ADR-0052)

| Panel | Metric | Purpose |
|---|---|---|
| Ceph Health Status | `ceph_health_status` | HEALTH_OK / HEALTH_WARN / HEALTH_ERR |
| Ceph OSD up / in | `ceph_osd_up`, `ceph_osd_in` | OSD reachability and pool participation |
| Ceph Placement Groups | `ceph_pg_active`, `ceph_pg_degraded`, `ceph_pg_undersized` | Replication health |
| Ceph RGW S3 Throughput | `ceph_osd_op_{r_out,w_in}_bytes` | Artifact store I/O (WS-B MLflow / Airflow) |

Default alerts: `CephHealthError` (critical, 5m), `CephHealthWarn` (warning, 30m),
`CephOSDDown` (warning, 5m), `CephPGsDegraded` (warning, 15m).

### etcd + control plane (ADR-0049)

| Panel | Metric | Purpose |
|---|---|---|
| etcd Quorum | `count(etcd_server_has_leader == 1)` | Raft quorum health |
| etcd Disk Latency P99 | `etcd_disk_wal_fsync_duration_seconds_bucket` | WAL + backend commit latency |
| etcd Proposals Failed + Leader Changes | `etcd_server_proposals_failed_total`, `etcd_server_leader_changes_seen_total` | Raft instability |
| Kubernetes API Server Latency P99 | `apiserver_request_duration_seconds_bucket` | Control-plane responsiveness |

Default alerts: `EtcdNoLeader` (critical, 1m), `EtcdHighWALFsyncLatency` (warning, 10m),
`EtcdLeaderChanges` (warning, 5m), `KubeAPIServerLatencyHigh` (warning, 10m).

> **IMPORTANT (ADR-0049):** Before any control-plane MachineConfig change or
> Talos upgrade, take an etcd snapshot and verify quorum. The self-operated
> control plane has no managed fallback.

---

## Alert routing

All bare-metal alerts carry these labels, enabling Alertmanager route separation
from cloud alerts:

```yaml
substrate: baremetal
adr: "<0049|0051|0052|0053>"
team: "<team-slug>"
namespace: "<team-namespace>"
platform_system: observability
platform_owner: "<team-slug>"
```

Alertmanager routes to PagerDuty per the existing config in
`apps/infra/observability/alertmanager/`. Teams may add custom routes in their
own PrometheusRule objects.

---

## Troubleshooting

### Bare-metal dashboard does not appear in Grafana

1. Verify `baremetal.enabled: true` is set in the team's `values.yaml`.
2. Verify Grafana sidecar is running: `kubectl get pods -n observability -l app=grafana`.
3. Verify the ConfigMap exists: `kubectl get configmap -n observability | grep <team-slug>-grafana-baremetal`.
4. Check sidecar logs: `kubectl logs -n observability -l app=grafana -c grafana-sc-dashboard --tail=50`.

### Talos metrics missing

1. Verify `talos-log-shipper` is running on all nodes (exports Talos machine metrics).
2. Verify the Prometheus `talos-nodes` scrape job: `kubectl get configmap -n observability prometheus-config -o yaml | grep talos-nodes`.
3. Verify the `nodeSelectorRegex` matches actual node names: `kubectl get nodes --show-labels | grep gpu`.

### IB metrics missing (`node_infiniband_port_*`)

1. Verify `node-exporter` is deployed with `--collector.infiniband` (enabled by default in the observability chart).
2. Verify IB kernel modules are loaded (declared in `talos-machineconfig` per ADR-0050): `talosctl get extensions` on a GPU node.
3. Verify IB devices: `talosctl read /sys/class/infiniband` on a GPU node.

### BGP sessions not showing in dashboard

1. Verify Cilium BGP mode: `cilium bgp peers`.
2. Verify Prometheus scrapes Cilium agent: `curl http://localhost:9962/metrics | grep cilium_bgp`.
3. Verify `bgpPeerFilter` regex matches actual peer addresses from `cilium bgp peers`.

### Ceph metrics missing

1. Verify Ceph MGR Prometheus module: `kubectl exec -n rook-ceph deploy/rook-ceph-mgr -- ceph mgr module ls | grep prometheus`.
2. Verify Prometheus `ceph` scrape job exists.

### etcd metrics missing

1. Verify etcd is exposing metrics: `talosctl service etcd status` on a control-plane node.
2. Verify Prometheus scrapes the etcd metrics endpoint (port 2381) with client TLS (cert/key from the kubeconfig).

---

## ADR references

| ADR | Topic |
|---|---|
| [ADR-0028](../adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md) | Platform taxonomy labels (mandatory on every resource) |
| [ADR-0034](../adrs/0034-backstage-deferred.md) | Backstage deferred — self-serve via template PR instead |
| [ADR-0039](../adrs/0039-self-serve-observability.md) | Self-serve Grafana + alert-rules-as-code (base design, reused here) |
| [ADR-0049](../adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md) | Talos foundation, self-operated control plane + etcd |
| [ADR-0051](../adrs/0051-baremetal-networking-cilium-lb-bgp.md) | Cilium BGP / LB-IPAM |
| [ADR-0052](../adrs/0052-baremetal-storage-rook-ceph.md) | Rook-Ceph storage (Ceph health panels) |
| [ADR-0053](../adrs/0053-baremetal-gpu-fabric-roce-infiniband.md) | RoCE / InfiniBand GPU fabric (IB / NVLink panels) |

---

*Planning-only document. Apply-gated. Nothing is deployed to real hardware.*
*Drafted 2026-06-15 as part of the Bare-Metal ML Platform WS-D implementation.*
