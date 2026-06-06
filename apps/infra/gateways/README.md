# gateways — Cluster ingress Gateways (Cilium Gateway API)

The shared cluster's ingress entrypoints, implementing **ADR-0009** (Cilium
Gateway API as the cluster ingress controller). This is the **primary, documented
ingress** for platform services.

## What it ships

| Resource | Kind | Purpose |
|----------|------|---------|
| `gw-external` | `Gateway` | Internet-facing NLB, HTTPS:443, TLS terminated at the Gateway |
| `gw-internal` | `Gateway` | Internal (VPC-only) NLB, HTTP:80 |
| `gw-external-tls` | `Certificate` | cert-manager TLS cert for `gw-external` (self-signed issuer until DNS is wired) |
| platform HTTPRoutes | `HTTPRoute` | Route platform UIs (Grafana, ArgoCD) to `gw-external` |

Both Gateways use `gatewayClassName: cilium` (from
`apps/infra/gateway-api-crds`). Cilium reads each Gateway's
`spec.infrastructure.annotations` and the **AWS Load Balancer Controller**
(`apps/infra/aws-lb-controller`) turns them into an NLB — one NLB per Gateway,
not per service.

## TLS

`gw-external-tls` is issued by cert-manager's `selfsigned` ClusterIssuer
(shipped by `apps/infra/cert-manager`, `clusterIssuers.selfSigned.enabled`).
The placeholder domain is `*.platform.internal`. To move to a real public cert:

1. Provision a Route53 hosted zone and the ACME `letsencrypt-prod` ClusterIssuer.
2. In `values.yaml` set `external.tls.issuer: letsencrypt-prod` and
   `external.tls.dnsNames` / the HTTPRoute hostnames to the real domain.

No template changes are required — it is all values-driven.

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

## Ordering

Sync-waves: CRDs/GatewayClass (`apps/infra/gateway-api-crds`, wave ≤0) →
ClusterIssuer (wave 1) → Certificate (wave 2) → Gateways (wave 3) → HTTPRoutes
(wave 4). Prereqs: `gateway-api-crds`, `cilium` (`gatewayAPI.enabled`),
`aws-lb-controller`, `cert-manager`.

## Relationship to `nlb-ingress` (legacy)

> **`terraform/modules/nlb-ingress` is legacy / deprecated for cluster ingress.**

Per ADR-0009, **Cilium Gateway API (this app) is the cluster ingress**. The
Terraform `nlb-ingress` module and its `catalog/units/nlb-ingress` unit predate
Gateway API and provision a standalone public NLB with ACM TLS termination.

- **Do not** add new platform ingress via `nlb-ingress` — author a `Gateway` /
  `HTTPRoute` here instead.
- `nlb-ingress` is **retained, not removed**: it may still back **product-fiction**
  workloads and the Global Accelerator regional-endpoint wiring. It is demoted in
  documentation only; no Terraform was changed by ADR-0009.

## Verify

```bash
kubectl get gateway -n gateways
kubectl get certificate gw-external-tls -n gateways
kubectl get httproute -A
```
