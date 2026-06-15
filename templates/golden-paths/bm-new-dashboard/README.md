# Golden Path: New Team Dashboard (Bare-Metal / Talos)

**Substrate:** Owned bare-metal GPU cluster on Talos Linux, two UK DCs.
See `docs/transaction-analytics/06-uk-datacenters.md`.

**ADRs cited:**
- ADR-0049 -- Talos foundation, immutability, multi-DC
- ADR-0051 -- Cilium LB-IPAM + BGP (Cilium BGP session panel)
- ADR-0052 -- Rook-Ceph (Ceph health panel)
- ADR-0041 -- Golden paths and collaboration (this document)
- ADR-0028 -- Platform taxonomy labels (mandatory on every resource)
- ADR-0039 -- Self-serve observability (WS-D, reused + BM panels)

This template onboards a new team into the WS-D (ADR-0039) self-serve
observability layer on the bare-metal cluster: one Grafana folder + starter
dashboard + PrometheusRule alert groups, delivered in a single PR.

The BM version adds **bare-metal-specific starter panels** absent from GCP/AWS paths:
- **Talos node health** (machine API liveness, kubelet ready)
- **InfiniBand/RoCEv2 fabric** (NCCL all-reduce bandwidth, NVLink counters)
- **Cilium BGP session state** (ToR peering; per `cilium-bgp-issues.md`)
- **Ceph cluster health** (HEALTH_OK/HEALTH_WARN, OSD up/in)
- **etcd control-plane** (latency + quorum -- absent on managed K8s)

**Key differences from the GCP golden path (`templates/golden-paths/new-dashboard/`):**

| Concern | GCP path | This bare-metal path |
|---------|---------|----------------------|
| BM-specific panels | None | baremetal.enabled: true in values |
| etcd panel | Absent (managed K8s) | Required (self-operated control plane, ADR-0049) |
| BGP panel | Absent (cloud LB) | Cilium BGP session state (ADR-0051) |
| Ceph panel | Absent (cloud storage) | Rook-Ceph health (ADR-0052) |

Backstage scaffolder mapping: `spec.type: team-dashboard` (future, ADR-0034 deferred)

---

## When to use this template

Use this golden path when:
- A team is new to the bare-metal cluster and needs a scoped Grafana folder
- The team does not need ML drift panels (use `bm-new-model-service` for ML)
- You want to start from the standard RED + saturation + BM-specific alerts dashboard

---

## Prerequisites

- [ ] Tenant namespace `tenant-{{TENANT_ID}}` exists (provisioned by `bm-new-tenant`)
- [ ] Grafana service account `grafana-sa-{{TEAM_SLUG}}` exists in Grafana
  (create via Grafana UI or API before ArgoCD sync)
- [ ] CI service account `{{TEAM_SLUG}}-ci` exists in namespace `{{TEAM_NAMESPACE}}`
  (for PrometheusRule RBAC; omit `ciServiceAccount` if not needed)

---

## Step 1 -- Substitute placeholders

```bash
export TEAM_NAME="Checkout UK"        # human-readable
export TEAM_SLUG="team-checkout-uk"   # lower-kebab
export TENANT_ID="acme"               # tenant ID (namespace: tenant-acme)
export TEAM_NAMESPACE="tenant-${TENANT_ID}"
export TEAM_SYSTEM="checkout"         # ADR-0028 platform.system
export TEAM_OWNER="team-checkout-uk"  # ADR-0028 platform.owner
export PLATFORM_ENV="production"      # production | staging | dev | sandbox

mkdir -p out
for f in values.yaml argocd-application.yaml; do
  envsubst < "$f" > "out/${f}"
done

# Verify no raw {{}} remain
grep -r '{{' out/ && echo "UNSUBSTITUTED PLACEHOLDERS FOUND" || echo "OK"
```

---

## Step 2 -- Commit the files

Place the substituted files in the PR at:
```
apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/values.yaml
apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/argocd-application.yaml
```

ArgoCD (wave 30) will pick them up and provision the Grafana folder.

---

## Step 3 -- Verify ADR-0028 labels

The BM OPA profile (`tests/opa/platform_tags_baremetal.rego`) checks all K8s
resources at plan time. Ensure your committed values carry:

```yaml
team:
  system: "{{TEAM_SYSTEM}}"   # ADR-0028 platform.system
  owner:  "{{TEAM_OWNER}}"    # ADR-0028 platform.owner
  env:    "{{PLATFORM_ENV}}"  # ADR-0028 platform.env
```

---

## Step 4 -- Bare-metal panel customization

Enable only the BM panels relevant to your team's scope:

| Panel | Enable when... |
|-------|---------------|
| `talosNodeHealth` | Always -- all teams on BM cluster benefit |
| `gpuFabric` | Team owns GPU workloads (training or inference) |
| `ciliumBgp` | Platform/SRE teams monitoring ingress / LB VIPs |
| `cephHealth` | Teams owning persistent storage (MLflow, Postgres, MinIO) |
| `etcd` | Platform/SRE teams only -- control-plane health |

---

## References

- `docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md` (WS-A)
- `docs/adrs/0051-baremetal-networking-cilium-lb-bgp.md` (BGP panel)
- `docs/adrs/0052-baremetal-storage-rook-ceph.md` (Ceph panel)
- `docs/adrs/0039-self-serve-observability.md` (WS-D self-serve)
- `docs/adrs/0041-golden-paths-collaboration.md` (WS-F)
- `docs/golden-paths/bm-RACI-and-handoffs.md` (RACI and handoff protocol)
- `docs/transaction-analytics/06-uk-datacenters.md` (UK DC design)
- `ai-sre/knowledge/cilium-bgp-issues.md` (BGP troubleshooting)
- `ai-sre/knowledge/nccl-troubleshooting.md` (NCCL/IB metrics)
- `apps/infra/grafana-self-serve/` (WS-D self-serve chart)
- `templates/golden-paths/bm-new-tenant/` (provision tenant namespace first)
- `templates/golden-paths/bm-new-model-service/` (if you also need ML panels)
