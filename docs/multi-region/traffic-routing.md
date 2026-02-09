# Multi-Region Traffic Routing

How traffic reaches the right cluster based on geography, health, and service type.

## Architecture Overview

```
                    Internet
                       │
              ┌────────▼────────┐
              │ Global Accelerator│  ← Anycast IPs, geo-routing
              │  (AWS edge POPs)  │
              └───┬──────────┬───┘
                  │          │
           ┌──────▼──┐  ┌───▼──────┐
           │  NLB    │  │  NLB     │
           │ eu-west │  │ eu-centr │  ← Per-region NLBs
           └────┬────┘  └────┬─────┘
                │             │
           ┌────▼────┐  ┌────▼─────┐
           │  EKS    │  │  EKS     │  ← Identical workloads
           │ euw1    │◄►│ euc1     │
           └─────────┘  └──────────┘
                  ClusterMesh
            (internal service mesh)
```

## External Traffic (Client → Service)

### How Global Accelerator Routes Traffic

AWS Global Accelerator uses **anycast routing** via AWS edge locations. When a client sends a request:

1. **DNS resolution**: Client resolves the GA DNS name to anycast IPs
2. **Edge routing**: Request enters the AWS network at the nearest edge POP
3. **Health-based routing**: GA checks NLB health in each region
4. **Region selection**: Traffic goes to the healthiest, nearest region

Configuration (from `terragrunt/staging/_global/global-accelerator/`):
- Both regions: `traffic_dial_percentage = 100` (true active-active)
- Health checks: TCP/443, 10s interval, 3 threshold
- Client affinity: `SOURCE_IP` (same client hits same region consistently)

### Geo-Location Behavior

| Client Location | Primary Region | Failover Region |
|-----------------|---------------|-----------------|
| Western Europe (UK, FR, ES, PT, NL, BE) | eu-west-1 (Ireland) | eu-central-1 (Frankfurt) |
| Central Europe (DE, AT, CH, PL, CZ) | eu-central-1 (Frankfurt) | eu-west-1 (Ireland) |
| Nordics (SE, NO, FI, DK) | eu-west-1 (Ireland) | eu-central-1 (Frankfurt) |
| Eastern Europe (RO, BG, HU) | eu-central-1 (Frankfurt) | eu-west-1 (Ireland) |
| Africa | eu-west-1 (Ireland) | eu-central-1 (Frankfurt) |
| Middle East | eu-central-1 (Frankfurt) | eu-west-1 (Ireland) |

> **Note**: Exact routing depends on AWS edge POP topology, which optimizes for lowest latency. The table above is approximate.

### Manual Traffic Shifting

To shift traffic away from a region (e.g., during maintenance):

```bash
# Send all traffic to eu-central-1 only
# In terragrunt/staging/_global/global-accelerator/terragrunt.hcl:
# Set eu-west-1 traffic_dial_percentage = 0
terragrunt apply

# Gradual ramp-up (canary):
# Set eu-west-1 traffic_dial_percentage = 10, then 25, 50, 100
```

### Automatic Failover

When NLB health checks fail in a region:
1. GA detects 3 consecutive failures (30s detection time)
2. GA stops routing new connections to the unhealthy region
3. Existing connections may timeout (client retry handles this)
4. 100% of traffic goes to the healthy region
5. When health recovers, GA resumes routing (within 10-30s)

## Internal Traffic (Service → Service)

### Cilium ClusterMesh Global Services

For pod-to-pod communication across clusters, Cilium ClusterMesh provides transparent service discovery.

A Kubernetes Service annotated with `service.cilium.io/global: "true"` becomes discoverable in **all meshed clusters**.

#### Affinity Modes

| Mode | Annotation | Behavior |
|------|-----------|----------|
| **Local-first** (default) | `service.cilium.io/affinity: "local"` | Route to local pods; failover to remote only if ALL local pods are unhealthy |
| **Remote-first** | `service.cilium.io/affinity: "remote"` | Route to remote pods first (useful for cross-region DB read replicas) |
| **None** | `service.cilium.io/affinity: "none"` | Round-robin across all pods in all clusters |

#### Shared Services

Add `service.cilium.io/shared: "true"` to load-balance across local AND remote pods simultaneously (weighted by endpoint count).

### How to Enable for Your App

In the Helm values for your team (e.g., `envs/staging/values/mono/values.yaml`):

```yaml
service:
  global: true           # Makes service discoverable cross-cluster
  globalAffinity: local  # local-first with remote failover
```

The `helm/app` chart v0.3.0 renders these as Cilium annotations on the Service resource.

### What Happens During Failover

1. All pods in eu-west-1 become unhealthy (node failure, cluster issue)
2. Cilium agent in eu-central-1 detects remote endpoints are gone
3. Local pods in eu-central-1 already handle local traffic (affinity: local)
4. Remote clients that were hitting eu-west-1 via GA get rerouted by GA to eu-central-1
5. Internal services in eu-central-1 that depended on eu-west-1 services via ClusterMesh were already preferring local — no impact

## ApplicationSet Deployment Model

### How Workloads Are Deployed

The `applicationset-multicluster.yaml` uses a **matrix generator**:

```
Teams (mono, chains, direct, protocols, listeners)
  ×
Clusters (staging-euw1, staging-euc1)
  =
10 Applications (e.g., mono-euw1, mono-euc1, chains-euw1, chains-euc1, ...)
```

Each Application:
- Deploys the same Helm chart (`helm/app`)
- Uses the same image tag (from Kargo promotion)
- Gets region injected via Helm values: `region`, `regionShort`, `cluster`
- Has `service.global: true` to enable ClusterMesh discovery
- Supports region-specific value overrides: `values-euw1.yaml`, `values-euc1.yaml`

### RollingSync Strategy

The ApplicationSet deploys to eu-west-1 first, then eu-central-1:

```yaml
strategy:
  type: RollingSync
  rollingSync:
    steps:
      - matchExpressions: [{key: region, values: [eu-west-1]}]
      - matchExpressions: [{key: region, values: [eu-central-1]}]
```

This provides a natural canary: if deployment to eu-west-1 fails, eu-central-1 is not affected.

### Region-Specific Overrides

To customize behavior per region, create a file at:
```
envs/staging/values/<team>/values-<regionShort>.yaml
```

Example — different replica count per region:
```yaml
# envs/staging/values/mono/values-euw1.yaml
replicaCount: 3

# envs/staging/values/mono/values-euc1.yaml
replicaCount: 2
```

## Adding a New Region

When adding eu-west-2 or eu-west-3:

1. Create cluster secret with labels `region: eu-west-2`, `region-short: euw2`
2. Uncomment/add to `argocd/bootstrap/cluster-secrets/kustomization.yaml`
3. The multicluster ApplicationSets auto-discover new clusters via label selectors
4. Optionally add region-specific value overrides: `values-euw2.yaml`
5. Update Global Accelerator endpoint groups to include the new region's NLB

No ApplicationSet YAML changes needed — new clusters are picked up automatically by the `clusters` generator with `region: Exists` selector.

## Monitoring

- **Grafana dashboard**: `multiregion-overview` — GA metrics, per-region health, traffic split
- **Grafana dashboard**: `clustermesh-status` — mesh connectivity, cross-cluster flows
- **ArgoCD UI**: Applications grouped by `region` label — filter to see per-region status
