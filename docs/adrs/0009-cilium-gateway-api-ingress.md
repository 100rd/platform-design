# ADR-0009: Cilium Gateway API as the cluster ingress controller

- Status: **Accepted** — decision is *adopted (live in source estate)*
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

The shared EKS cluster needs an ingress solution for workloads delivered via
ArgoCD (ADR-0006) — the observability surfaces (Grafana), the inference-gateway
front-end, and platform tooling. The cluster already runs Cilium as its CNI
(ADR-0003), which supports the Kubernetes Gateway API natively. Three options
were evaluated:

1. **AWS Load Balancer Controller (ALB Ingress)** — tight ALB integration but
   per-Ingress ALB provisioning; cost scales with service count.
2. **NGINX Ingress Controller** — widely adopted, but a separate Deployment and
   extra attack surface.
3. **Cilium Gateway API** — built into the existing Cilium CNI, uses the
   Kubernetes Gateway API standard, no additional Deployment.

Gateway API v1.x graduated `GatewayClass`/`HTTPRoute` to stable, and Cilium
exposes it via `gatewayAPI.enabled`.

## Decision

Enable **Cilium Gateway API** (`gatewayAPI.enabled = true`) as the ingress
controller for the shared cluster. Workloads expose themselves with `Gateway` +
`HTTPRoute` objects. A reviewer can check conformance by confirming new ingress
is authored as Gateway API resources, not `Ingress` objects or per-service ALBs.

## Alternatives considered

### Alternative A: AWS Load Balancer Controller (ALB Ingress)
Provision an ALB per Ingress.
Rejected because: cost scales linearly with the number of exposed services, and
it is a separate controller to operate. Gateway API on the existing Cilium has no
such per-service cost.

### Alternative B: NGINX Ingress Controller
Run NGINX as a separate ingress Deployment.
Rejected because: it is an additional component and attack surface, and locks the
platform into the legacy `Ingress` API just as the ecosystem migrates to Gateway
API.

### Alternative C: Status quo (no ingress / direct LoadBalancer Services)
Expose each service with its own `Service type=LoadBalancer`.
Rejected because: it multiplies load balancers and offers no shared routing,
TLS termination, or host/path policy layer.

## Consequences

### Positive
- No additional component: Cilium already runs as a DaemonSet; enabling Gateway
  API adds a watch loop in the existing operator — zero extra pods.
- Cost: load balancers are provisioned per `Gateway`, not per `Ingress`.
- Standards alignment: Gateway API is the upstream replacement for `Ingress`;
  adopting now avoids a future migration.
- Hubble observability: Gateway API traffic is visible in Hubble flow logs (ties
  back to ADR-0003's observability story).

### Negative
- Gateway API CRDs (`gateway.networking.k8s.io`) must be installed before the
  Cilium Helm release; ordering handled via ArgoCD `dependencies` /
  sync-waves.
- Team learns `GatewayClass`/`Gateway`/`HTTPRoute` instead of `Ingress`.
- Not all NGINX `Ingress` annotations are supported; annotation-heavy configs
  must be ported to `HTTPRoute` filters.

### Risks
- An environment without the CRDs installed would fail the Cilium upgrade.
  Mitigated by a default-off module flag (`enable_gateway_api = false`) preserving
  backward compatibility, and a runbook pinning the CRD install manifest.

## Implementation notes

- CRDs installed ahead of the Cilium chart (sync-wave / `dependencies`).
- `Gateway` objects own the load balancers; `HTTPRoute` objects own host/path
  routing. The Argo Rollouts canary plugin (ADR-0014) manipulates `HTTPRoute`
  backend weights.

## References

- Kubernetes Gateway API: <https://gateway-api.sigs.k8s.io/>
- Ported from `qbiq-ai/infra` ADR-008 and `qbiq-ai/argocd` Gateway API usage
- Related: ADR-0003 (Cilium CNI), ADR-0014 (Argo Rollouts canary)

---
*Ported from qbiq-ai/infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live).*
