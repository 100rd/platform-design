# gateways -- Cluster ingress Gateways (Cilium Gateway API)

The shared cluster's ingress entrypoints, implementing **ADR-0009** (Cilium
Gateway API as the cluster ingress controller). This is the **primary, documented
ingress** for platform services.

## Provenance

- **Tier-1 ingress component** (ADR-0009 + ADR-0009 follow-on, refs #252)
- Gateway API v1.4.0 standard channel (GA 2025-10)
- Cilium 1.19 passes v1.4 conformance including BackendTLSPolicy

## What it ships

| Resource | Kind | Purpose |
|----------|------|---------|
| `gw-external` | `Gateway` | Internet-facing NLB, HTTPS:443, TLS terminated at the Gateway |
| `gw-internal` | `Gateway` | Internal (VPC-only) NLB, HTTP:80 |
| `gw-external-tls` | `Certificate` | cert-manager TLS cert for `gw-external` (self-signed issuer until DNS is wired) |
| platform HTTPRoutes | `HTTPRoute` | Route platform UIs (Grafana, ArgoCD) to `gw-external` |
| `grafana-backend-ca` | `Certificate` | Self-signed CA cert for the Grafana backend TLS chain |
| `grafana-backend-ca-issuer` | `ClusterIssuer` | CA-type issuer signing backend serving certs |
| `grafana-backend-serving` | `Certificate` | TLS serving cert for the Grafana backend pod |
| `grafana-backend-ca-cm` | `ConfigMap` | CA cert bundle used by BackendTLSPolicy for peer validation |
| `grafana` | `BackendTLSPolicy` | Encrypts the gateway->Grafana backend hop (refs #252) |

Both Gateways use `gatewayClassName: cilium` (from
`apps/infra/gateway-api-crds`). Cilium reads each Gateway's
`spec.infrastructure.annotations` and the **AWS Load Balancer Controller**
(`apps/infra/aws-lb-controller`) turns them into an NLB -- one NLB per Gateway,
not per service.

## TLS architecture

### Ingress TLS (gateway-client edge)

`gw-external-tls` is issued by cert-manager's `selfsigned` ClusterIssuer
(shipped by `apps/infra/cert-manager`, `clusterIssuers.selfSigned.enabled`).
The placeholder domain is `*.platform.internal`. To move to a real public cert:

1. Provision a Route53 hosted zone and the ACME `letsencrypt-prod` ClusterIssuer.
2. In `values.yaml` set `external.tls.issuer: letsencrypt-prod` and
   `external.tls.dnsNames` / the HTTPRoute hostnames to the real domain.

No template changes are required -- it is all values-driven.

### Backend TLS (gateway->backend hop, BackendTLSPolicy)

`backendtlspolicy-grafana.yaml` closes the encryption-in-transit gap for the
Grafana backend (ADR-0009 follow-on, refs #252):

1. A self-signed CA (`grafana-backend-ca`) is issued via the `selfsigned`
   ClusterIssuer and stored in `grafana-backend-ca-secret`.
2. A CA-type `ClusterIssuer` (`grafana-backend-ca-issuer`) signs the Grafana
   serving cert (`grafana-backend-serving-secret`).
3. The CA cert is projected into `grafana-backend-ca-cm` ConfigMaps in both
   the `gateways` and `monitoring` namespaces (BackendTLSPolicy requires the
   ConfigMap in the same namespace as the targetRef Service).
4. `BackendTLSPolicy/grafana` (namespace: `monitoring`) targets the
   `kube-prometheus-stack-grafana` Service, instructs Cilium to use SNI
   `grafana.platform.internal`, and validates the backend cert against the CA.

**Bootstrap required**: after cert-manager issues `grafana-backend-ca`, copy
`ca.crt` from `grafana-backend-ca-secret` into both `grafana-backend-ca-cm`
ConfigMaps (or use an ESO ExternalSecret -- see the inline comment in
`templates/backendtlspolicy-grafana.yaml`).

**Grafana config required**: the Grafana Deployment must be switched to HTTPS
(mount `grafana-backend-serving-secret` and set `grafana.ini` `[server]
protocol=https`). Wire this in `apps/infra/observability`.

## Adding a platform UI

Add an entry to `.Values.httpRoutes`; an `HTTPRoute` attaching to `gw-external`
is generated automatically:

```yaml
httpRoutes:
  - name: my-ui
    hostname: my-ui.platform.internal
    backend:
      name: my-ui-svc
      namespace: my-ns
      port: 80
```

To add BackendTLSPolicy for the new UI, duplicate
`templates/backendtlspolicy-grafana.yaml` and adjust names/namespaces.

## Ordering

Sync-waves: CRDs/GatewayClass (`apps/infra/gateway-api-crds`, wave <=0) ->
selfsigned ClusterIssuer (wave 1) -> Certificate (wave 2) -> Gateways (wave 3)
-> HTTPRoutes (wave 4). BackendTLSPolicy resources follow the same wave scheme
(CA cert wave 1, CA issuer wave 2, serving cert + CA ConfigMap wave 3,
BackendTLSPolicy wave 4). Prereqs: `gateway-api-crds`, `cilium`
(`gatewayAPI.enabled`, `gatewayAPI.enableAlpn`), `aws-lb-controller`,
`cert-manager`.

## Relationship to `nlb-ingress` (legacy)

> **`terraform/modules/nlb-ingress` is legacy / deprecated for cluster ingress.**

Per ADR-0009, **Cilium Gateway API (this app) is the cluster ingress**. The
Terraform `nlb-ingress` module and its `catalog/units/nlb-ingress` unit predate
Gateway API and provision a standalone public NLB with ACM TLS termination.

- **Do not** add new platform ingress via `nlb-ingress` -- author a `Gateway` /
  `HTTPRoute` here instead.
- `nlb-ingress` is **retained, not removed**: it may still back **product-fiction**
  workloads and the Global Accelerator regional-endpoint wiring.

## Verify

```bash
kubectl get gateway -n gateways
kubectl get certificate gw-external-tls -n gateways
kubectl get httproute -A
# BackendTLSPolicy (v1.4.0+ Standard channel):
kubectl get backendtlspolicy -n monitoring
kubectl get certificate grafana-backend-ca -n gateways
kubectl get certificate grafana-backend-serving -n monitoring
kubectl get configmap grafana-backend-ca-cm -n monitoring
```
