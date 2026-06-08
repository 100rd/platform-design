# ecr-pull-through-cache

ECR **Pull-Through Cache (PTC)** for public upstream registries — mirrors
Docker Hub, Quay, GHCR, `registry.k8s.io`, `public.ecr.aws` (and optionally
GitLab) into this account's **private** ECR registry. Implements **ADR-0029**.

Defeats **Docker Hub rate-limits** and **external-registry outages**: once an
image is pulled through the cache, subsequent pulls are served from your private
ECR — no upstream round-trip, no anonymous rate-limit, no dependency on the
upstream being reachable.

## How callers consume it

Reference the upstream image under the local cache prefix:

```text
<acct>.dkr.ecr.<region>.amazonaws.com/<prefix>/<upstream-image>
```

| Upstream | Default prefix | Example pull |
|---|---|---|
| Docker Hub (`registry-1.docker.io`) | `docker-hub` | `…/docker-hub/library/nginx:1.27` |
| Quay (`quay.io`) | `quay` | `…/quay/prometheus/prometheus:v3.0.0` |
| GHCR (`ghcr.io`) | `ghcr` | `…/ghcr/external-secrets/external-secrets:v0.10.0` |
| `registry.k8s.io` | `k8s` | `…/k8s/kube-state-metrics/kube-state-metrics:v2.13.0` |
| `public.ecr.aws` | `ecr-public` | `…/ecr-public/karpenter/controller:1.0.0` |

The repository under each prefix is **created automatically on first pull** by
the repository creation template — no pre-provisioning of individual repos.

## What this module creates

| Resource | Purpose |
|---|---|
| `aws_ecr_pull_through_cache_rule` (per upstream) | Maps a local prefix → upstream registry URL |
| `aws_secretsmanager_secret` + `_version` (`ecr-pullthroughcache/…`) | Docker Hub upstream credential (placeholder; real value injected out-of-band) |
| `aws_ecr_repository_creation_template` (`ROOT`, `PULL_THROUGH_CACHE`) | Auto-config for cached repos: KMS encryption, immutable tags, lifecycle |
| `aws_iam_role` + `aws_iam_role_policy` | Custom role ECR assumes to create cached repos (required for KMS + tags) |
| `aws_ecr_registry_scanning_configuration` | Scan cached repos on push (`SCAN_ON_PUSH` / `CONTINUOUS_SCAN`) |

## Docker Hub credential (required)

AWS requires an **upstream credential** for the Docker Hub PTC rule, stored in
Secrets Manager under a name that **must** start with `ecr-pullthroughcache/`.
This module creates the secret with a **placeholder** value:

```json
{ "username": "REPLACE_ME", "accessToken": "REPLACE_ME" }
```

The real Docker Hub username + a **read-only access token** are injected
**out-of-band** (External Secrets Operator / a secure pipeline — ADR-0008). The
`secret_version` uses `ignore_changes = [secret_string]` so Terraform never
clobbers the rotated value. **Never commit real credentials.**

## Usage

```hcl
module "ecr_pull_through_cache" {
  source = "../../terraform/modules/ecr-pull-through-cache"

  kms_key_arn = module.kms.key_arns["ecr"]

  # Defaults already include ecr-public, docker-hub, quay, ghcr, k8s.
  # Override only to add/remove upstreams (e.g. add GitLab):
  upstreams = {
    ecr-public = { upstream_registry_url = "public.ecr.aws" }
    docker-hub = { upstream_registry_url = "registry-1.docker.io", requires_credential = true }
    quay       = { upstream_registry_url = "quay.io" }
    ghcr       = { upstream_registry_url = "ghcr.io" }
    k8s        = { upstream_registry_url = "registry.k8s.io" }
  }

  tags = {
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `upstreams` | Map of `prefix → { upstream_registry_url, requires_credential }` | `map(object)` | docker-hub/quay/ghcr/k8s/ecr-public |
| `kms_key_arn` | CMK for cached-repo encryption (drives the custom role) | `string` | `null` |
| `create_repository_creation_template` | Auto-config cached repos | `bool` | `true` |
| `create_registry_scanning_configuration` | Manage registry scanning (singleton) | `bool` | `true` |
| `scan_type` | `BASIC` or `ENHANCED` | `string` | `ENHANCED` |
| `image_tag_mutability` | `MUTABLE` / `IMMUTABLE` | `string` | `IMMUTABLE` |
| `max_image_count` | Tagged images retained per repo | `number` | `50` |
| `untagged_expiry_days` | Untagged image expiry | `number` | `7` |
| `dockerhub_secret_placeholder` | Placeholder JSON for the credential (sensitive) | `string` | `REPLACE_ME` JSON |
| `recovery_window_in_days` | Secret recovery window | `number` | `7` |
| `tags` | Tags for all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `pull_through_cache_prefixes` | `upstream key → local ECR prefix` |
| `pull_through_cache_rules` | `upstream key → { prefix, upstream_registry_url, registry_id }` |
| `dockerhub_credential_secret_arns` | `upstream key → credential secret ARN` |
| `repository_creation_template_role_arn` | IAM role ARN (or null) |
| `scanning_configuration_registry_id` | Registry ID for scanning (or null) |

## Notes

- The **registry scanning configuration is a singleton per registry**. If another
  unit already manages it, set `create_registry_scanning_configuration = false`
  to avoid a conflict.
- The repository creation template `prefix = "ROOT"` applies to **all** cached
  repositories created by PTC in this registry.
- `scan_on_push` for cached repos is delivered via the **registry scanning
  configuration** (not the repository creation template), per AWS.

## References

- [Using pull through cache rules](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html)
- `aws_ecr_pull_through_cache_rule`, `aws_ecr_repository_creation_template`,
  `aws_ecr_registry_scanning_configuration` (hashicorp/aws ~> 6.0)
- ADR-0029 — `docs/adrs/0029-ecr-pull-through-cache.md`
- Related: ADR-0008 (External Secrets Operator), ADR-0016 (supply-chain hardening)
