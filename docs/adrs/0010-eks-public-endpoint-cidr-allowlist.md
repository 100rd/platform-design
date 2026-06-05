# ADR-0010: EKS public API endpoint with a parameterised CIDR allow-list

- Status: **Accepted** — decision is *adopted (live in source estate)*
- platform-design status: **partial** — the CIDR allow-list is parameterised
  (`catalog/units/eks/terragrunt.hcl` sets
  `cluster_endpoint_public_access_cidrs`, defaulting to `["0.0.0.0/0"]`), so the
  variable is first-class and never relies on the implicit default. The narrow
  prod-tier allow-list / private-only endpoint remains a design-target.
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

The EKS control-plane endpoint configuration determines how operators, CI
runners, and deployers reach the Kubernetes API server. For the platform's
non-production / shared cluster, CI (GitHub Actions runners with dynamic IPs)
needs `kubectl` and `terragrunt` access to the API. Three models exist:

1. **Private only** — API reachable only inside the VPC; all external callers
   need a bastion/VPN. Highest security, highest friction.
2. **Public only** — API reachable from any IP; simplest, largest attack surface.
3. **Public + private, CIDR-restricted** — reachable privately from the VPC and
   publicly from an explicit CIDR allow-list. Balances access and security.

The previous EKS unit left `cluster_endpoint_public_access_cidrs` unset, which
AWS interprets as `0.0.0.0/0` (implicitly wide open). The goal is to make the
allow-list a first-class, tightenable Terraform variable.

## Decision

Set `cluster_endpoint_public_access = true`,
`cluster_endpoint_private_access = true`, and introduce
`cluster_endpoint_public_access_cidrs` as an explicit input variable. For the
shared/non-prod cluster it is currently `["0.0.0.0/0"]` — a known, documented
risk that preserves current CI behaviour while making the allow-list explicit and
parameterised.

A reviewer can check conformance by confirming the EKS unit sets the CIDR list
explicitly (never relies on the implicit `0.0.0.0/0` default) and keeps private
access enabled.

## Alternatives considered

### Alternative A: Private-only endpoint
Lock the API to the VPC.
Rejected because: GitHub Actions runners use dynamic IPs; reaching a private-only
endpoint requires a NAT gateway with an Elastic IP (cost + complexity) or a
bastion/VPN for every CI job. For a non-production preview cluster the friction
outweighs the benefit.

### Alternative B: Public-only endpoint
Drop private access.
Rejected because: it forces in-cluster components (Cilium operator, kube-system)
to traverse the public endpoint and removes the internal-path mitigation. Private
access must stay on.

### Alternative C: Status quo (implicit `0.0.0.0/0`)
Leave the CIDR variable unset.
Rejected because: the implicit wide-open default is invisible in review and
cannot be tightened without a module change. Externalising it is the whole point.

## Consequences

### Positive
- The CIDR list is a first-class `terragrunt.hcl` input — tightenable later (e.g.
  to GitHub Actions IP ranges via `api.github.com/meta`) without a module change.
- Private access retained: in-cluster components always use the internal
  endpoint, bounding the blast radius of a public-CIDR breach.

### Negative
- The explicit `["0.0.0.0/0"]` on the shared cluster is a documented, accepted
  risk for the non-production tier.

### Risks
- Tightening the CIDR later must be validated against every CI pipeline that
  calls `kubectl`/`terragrunt plan` against the cluster, or those jobs break.
  Mitigated by tracking the tightening as a follow-up once runner-IP stability is
  confirmed.
- **Production-tier note:** production/data-plane clusters should NOT inherit the
  `0.0.0.0/0` value. The variable exists precisely so prod can ship a narrow
  allow-list (or private-only). This is a *design-target* for the prod tier.

## Implementation notes

- `cluster_endpoint_public_access_cidrs` plumbed through `_envcommon` → the EKS
  `terragrunt.hcl` unit.
- Shared/non-prod: `["0.0.0.0/0"]` (documented). Prod: narrow allow-list /
  private — to be set when the prod cluster lands.

## References

- EKS endpoint access: <https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html>
- Ported from `infra` ADR-009 (EKS public endpoint + parameterised CIDR)
- Related: ADR-0003 (Cilium CNI), ADR-0001 (OU split / tier separation)

---
*Ported from infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live) for
the shared/non-prod cluster; narrow prod allow-list is a design-target.*
