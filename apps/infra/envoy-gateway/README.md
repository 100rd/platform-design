# envoy-gateway — Secondary L7 GatewayClass (ADR-0025)

## Overview

Envoy Gateway v1.8.x deployed as a **secondary GatewayClass** alongside Cilium.

**Cilium stays the CNI and primary GatewayClass** (`io.cilium/gateway-controller`).
Envoy Gateway is a separate control-plane that provisions its own Envoy proxy
data-plane pods. It is NOT a CNI and does NOT replace Cilium's networking layer.

## Why

Cilium Gateway API lacks several capabilities needed by platform services:

| Capability | Cilium Gateway API | Envoy Gateway |
|---|---|---|
| Global rate-limiting (cross-pod shared counter, Redis-backed) | No | Yes (`BackendTrafficPolicy`) |
| External processing (`ext_proc` gRPC filter) | No | Yes (`EnvoyExtensionPolicy`) |
| WASM HTTP filters | No | Yes (`EnvoyExtensionPolicy`) |
| Circuit-breaking per upstream | No | Yes (`BackendTrafficPolicy`) |
| Per-route retry budgets | Partial | Yes |

ADR-0025 documents the full decision record and trade-offs.

## GatewayClass separation

| GatewayClass | controllerName | Data-plane |
|---|---|---|
| `cilium` | `io.cilium/gateway-controller` | Cilium eBPF |
| `envoy-gateway` | `gateway.envoyproxy.io/gatewayclass-controller` | Envoy proxy pods |

Workloads choose the class that fits their needs. The two classes are
fully independent and can run on the same cluster simultaneously.

## What is NOT in scope (ADR-0025)

- **AWS Load Balancer Controller + Gateway API (AWS-LBC-GW)** — AWS-native L4/L7
  integration; candidate for future ADR once GA.
- **GAMMA (Gateway API for Mesh Management and Administration)** — east-west mesh
  traffic via Gateway API; not required in the current platform topology.

## Contents

```
apps/infra/envoy-gateway/
├── Chart.yaml                            # Helm chart, depends on oci://docker.io/envoyproxy/gateway-helm:v1.8.0
├── values.yaml                           # Controller config + Gateway API object values
├── README.md                             # This file
└── templates/
    ├── _helpers.tpl                      # Shared label/name helpers
    ├── gatewayclass.yaml                 # GatewayClass (cluster-scoped)
    ├── gateway.yaml                      # Example Gateway (namespace-scoped)
    ├── backendtrafficpolicy.yaml         # Global rate-limit example
    ├── networkpolicy.yaml                # Controller pod network isolation
    └── servicemonitor.yaml               # Prometheus scrape config
```

## ArgoCD wiring

The `infra-appset.yaml` ApplicationSet (`argocd/bootstrap/applicationsets/infra-appset.yaml`)
uses a Git directory generator on `apps/infra/*`. Adding this directory is
sufficient — no manual Application YAML is needed.

## Validation

```bash
cd apps/infra/envoy-gateway

# Lint
helm lint .

# Render (no chart dependencies needed for template validation)
helm template envoy-gateway . --set envoyGateway.enabled=false \
  | python3 -c "import sys, yaml; list(yaml.safe_load_all(sys.stdin))" && echo "YAML OK"
```

## Upgrading

1. Update `dependencies[0].version` in `Chart.yaml` to the new `v1.8.x` patch.
2. Run `helm dep update` to refresh `Chart.lock` and the pinned digest.
3. Update `appVersion` to match.
4. Validate with `helm lint` + `helm template`.
5. Raise a PR; ArgoCD will apply after merge.
