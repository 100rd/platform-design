# gateway-api-crds — Gateway API CRDs + Cilium GatewayClass

Installs the Kubernetes **Gateway API** standard-channel CRDs (v1.4.0) and the
Cilium **GatewayClass** (`cilium`). This is the foundation for ADR-0009 (Cilium
Gateway API as the cluster ingress controller).

## Provenance

- **Tier-1 ingress component** (ADR-0009 + ADR-0009 follow-on, refs #252)
- `crds/standard-install.yaml` sourced from:
  `https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml`
- Cilium 1.19 passes v1.4 conformance.
- v1.4.0 graduated **BackendTLSPolicy** to the Standard channel (was Experimental
  in v1.2.x). See `apps/infra/gateways` for the BackendTLSPolicy manifest.

## What it ships

- `crds/standard-install.yaml` — Gateway API standard channel CRDs v1.4.0:
  `BackendTLSPolicy`, `GatewayClass`, `Gateway`, `GRPCRoute`, `HTTPRoute`,
  `ReferenceGrant` — vendored so ArgoCD applies them with ServerSideApply.
- `templates/gatewayclass.yaml` — a cluster-scoped `GatewayClass` named `cilium`
  with `controllerName: io.cilium/gateway-controller`.

## Ordering (critical)

This app **must sync before**:

1. `apps/infra/cilium` — which sets `gatewayAPI.enabled: true`; the Cilium
   operator fails to start its Gateway controller if the CRDs are missing.
2. `apps/infra/gateways` — which creates `Gateway`, `HTTPRoute`, and
   `BackendTLSPolicy` objects.

Ordering is enforced with `argocd.argoproj.io/sync-wave` annotations: the CRDs
and GatewayClass land at the earliest waves (`-1` / `0`); Gateways and routes
follow at later waves.

## Conformance (ADR-0009)

New cluster ingress is authored as Gateway API resources (`Gateway` +
`HTTPRoute`), **not** `Ingress` objects or per-service ALBs. See
`apps/infra/gateways` for the cluster's `gw-external` / `gw-internal` Gateways
and the `BackendTLSPolicy` encrypting the gateway-to-backend hop.

## Verify

```bash
kubectl get crd | grep gateway.networking.k8s.io
kubectl get gatewayclass cilium -o wide
# BackendTLSPolicy CRD present in v1.4.0+:
kubectl get crd backendtlspolicies.gateway.networking.k8s.io
```
