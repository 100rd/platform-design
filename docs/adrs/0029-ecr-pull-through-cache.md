# ADR-0029: ECR Pull-Through Cache for public upstream registries

- Status: **Accepted** — proposal, doc-verified; ratified, not yet implemented.
- Ratified: 2026-06-08 by platform owner.
- platform-design status: **pending** — the `ecr-pull-through-cache` module and
  the shared-account terragrunt unit land in this PR, but nothing is applied yet.
- Date: 2026-06-08
- Authors: platform-team
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)
- Related: ADR-0008 (External Secrets Operator), ADR-0016 (supply-chain hardening).

## Context

Cluster and CI workloads pull base/tooling images directly from **public upstream
registries** — **Docker Hub** (`registry-1.docker.io`), **Quay** (`quay.io`),
**GHCR** (`ghcr.io`), **`registry.k8s.io`**, and **`public.ecr.aws`**. This
couples our availability to theirs and exposes two recurring failure modes:

1. **Docker Hub anonymous/free rate-limits** throttle image pulls. On a busy node
   fleet (Karpenter scale-up, ADR-0007) a burst of cold pulls hits the limit and
   pods get stuck in `ImagePullBackOff` — a self-inflicted outage on a third
   party's throttle.
2. **External-registry outages / network reachability**: when an upstream is down
   or unreachable, *new* image pulls fail even though the same image was pulled
   minutes earlier on another node. There is no local durable copy.

There is no account-local, durable, scanned mirror of these public images today,
and no single place to attach Docker Hub credentials or image scanning for them.

## Decision

Adopt **Amazon ECR Pull-Through Cache (PTC)** to mirror the public upstreams into
this account's **private** ECR registry, fronted by a **repository creation
template** that auto-configures each cached repository:

- **One `aws_ecr_pull_through_cache_rule` per upstream**, each mapping a stable
  local **prefix** to its upstream registry URL:
  - `ecr-public` → `public.ecr.aws`
  - `docker-hub` → `registry-1.docker.io`
  - `quay` → `quay.io`
  - `ghcr` → `ghcr.io`
  - `k8s` → `registry.k8s.io`
  - (`gitlab` → `registry.gitlab.com` is supported and available behind the same
    variable when needed.)
- **Docker Hub upstream credential** in **Secrets Manager** under the
  AWS-required `ecr-pullthroughcache/` name prefix. The value is a **placeholder**
  in code; the real username + **read-only access token** are injected
  **out-of-band** (External Secrets Operator, ADR-0008) and never committed.
- **`aws_ecr_repository_creation_template`** (`prefix = "ROOT"`,
  `applied_for = ["PULL_THROUGH_CACHE"]`) that auto-creates each cached repo on
  first pull with **KMS (CMK) encryption**, **immutable tags**, and a
  **lifecycle policy** (retain last N tagged, expire untagged after M days). KMS
  encryption + resource tags require a **custom IAM role**, which the module
  provisions and ECR assumes to create the repositories.
- **`aws_ecr_registry_scanning_configuration`** so cached repositories are
  **scanned** (scan-on-push under BASIC, or continuous Inspector scanning under
  ENHANCED) over the cache prefixes.

**Callers reference cached images** as:

```text
<acct>.dkr.ecr.<region>.amazonaws.com/<upstream-prefix>/<image>
# e.g. <acct>.dkr.ecr.eu-west-1.amazonaws.com/docker-hub/library/nginx:1.27
```

The module is deployed in the **shared-services account** (which already hosts the
central ECR registry per `account.hcl`), in the primary region.

A reviewer can check conformance by confirming: a PTC rule exists per upstream;
the Docker Hub rule has a `credential_arn` pointing at an `ecr-pullthroughcache/`
secret; a `ROOT` repository creation template applies for `PULL_THROUGH_CACHE`
with KMS encryption + immutable tags + a lifecycle policy and a custom role; and
the registry scanning configuration covers the cache prefixes.

## Alternatives considered

### Alternative A: Status quo — pull straight from public registries
Keep pulling images directly from Docker Hub / Quay / GHCR / k8s / ECR Public.
Rejected because: it leaves us exposed to **Docker Hub rate-limits** and
**upstream outages**, with no durable local copy and no central place to attach
credentials or scanning. Scale-up storms turn a third-party throttle into our
`ImagePullBackOff`.

### Alternative B: Manually mirror images into per-image private ECR repos
Run a job that `docker pull`/`docker push`-mirrors each needed image into a
hand-managed private repo.
Rejected because: it is **toil** — every new image/tag needs a pipeline change,
mirrors drift from upstream, and it duplicates exactly what PTC does natively
(on-demand, transparent, with auto-created repos).

### Alternative C: Run a self-hosted pull-through proxy (e.g. a registry mirror)
Stand up and operate a registry mirror (Harbor proxy cache, registry mirror, etc.).
Rejected because: it adds an **operational component** (HA, storage, upgrades,
its own credentials and scanning) to solve a problem ECR already solves natively
with IAM-scoped access, KMS encryption, and Inspector scanning — more moving
parts for no added benefit on AWS.

## Consequences

### Positive
- **Rate-limit immunity**: after the first pull, images are served from private
  ECR — no anonymous Docker Hub throttle on scale-up.
- **Outage resilience**: a durable account-local copy survives upstream outages.
- **Scanned + encrypted by default**: cached repos auto-created with KMS
  encryption, immutable tags, lifecycle, and registry scanning.
- **One place** for Docker Hub credentials and image policy across the estate.

### Negative
- Cached images are **mirrors of upstream `latest`-style tags at first pull** —
  consumers should pin digests/immutable tags to avoid surprise drift.
- The Docker Hub credential must be **provisioned and rotated** out-of-band; a
  missing/expired token silently degrades the Docker Hub rule back toward
  anonymous rate-limits.

### Risks
- A mis-scoped credential secret or custom IAM role over-grants. Mitigated by the
  least-privilege role (only ECR create/replicate + scoped KMS) and storing the
  credential via ESO (ADR-0008), never in git.
- The **registry scanning configuration is a singleton per registry** — two
  owners conflict. Mitigated by the `create_registry_scanning_configuration`
  toggle so exactly one unit owns it.
- Stale cache vs. moving upstream tags. Mitigated by the lifecycle policy +
  recommending digest/immutable-tag pinning for consumers.

## Implementation notes

- Files / modules touched: new `terraform/modules/ecr-pull-through-cache`
  (`aws_ecr_pull_through_cache_rule` per upstream, the
  `ecr-pullthroughcache/` Secrets Manager credential, the
  `aws_ecr_repository_creation_template`, the custom IAM role, and the
  `aws_ecr_registry_scanning_configuration`), plus a shared-account terragrunt
  unit `terragrunt/shared/eu-west-1/ecr-pull-through-cache`.
- Migration: deploy the rules + template + scanning, inject the Docker Hub token
  via ESO, then repoint workload/CI image references from public registries to
  the `<acct>.dkr.ecr.<region>.amazonaws.com/<prefix>/…` form.
- Rollback: cached repos and rules can be removed; consumers fall back to direct
  public pulls (reverting to the status quo).
- CI/test: terraform-checks (`fmt`, `validate`, `terraform test` with a mock
  provider) over the module; no apply in CI for this account.

Effort: **M**.

## References

- Using pull through cache rules (supported upstreams, Docker Hub credential):
  <https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html>
- ECR repository creation templates:
  <https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-creation-templates.html>
- ECR enhanced/basic scanning:
  <https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html>
- Terraform: `aws_ecr_pull_through_cache_rule`, `aws_ecr_repository_creation_template`,
  `aws_ecr_registry_scanning_configuration` (hashicorp/aws ~> 6.0)
- Related: ADR-0008 (External Secrets Operator — delivers the Docker Hub token),
  ADR-0016 (Tier-1 supply-chain hardening), ADR-0007 (Karpenter — scale-up pull bursts)

---
*Proposal — doc-verified 2026-06-08 (official AWS / Terraform AWS provider docs) —
2026 platform modernization; grounded in infra@572b54d / argocd@c364c6c. Accepted,
ratified 2026-06-08 by platform owner; not yet implemented in platform-design.*
