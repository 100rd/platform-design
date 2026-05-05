# `_envcommon/` — Shared per-module Terragrunt configs

Per-module includes that fix the **module source**, **default inputs**, and
**common dependency declarations** for every per-environment unit that
deploys that module. Mirrors the `qbiq-ai/infra` skeleton and follows the
[Terragrunt "keep your remote state configuration DRY"][1] +
[`include` pattern][2] guidance.

[1]: https://terragrunt.gruntwork.io/docs/features/keep-your-remote-state-configuration-dry/
[2]: https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#include

## Why this exists

Without `_envcommon`, every per-environment unit duplicates:

- the module path (`source = "${get_repo_root()}/.../modules/eks"`)
- the dependency block(s) (`dependency "vpc" { ... }`)
- the cross-cutting input defaults (`enabled_cluster_log_types`, flow-log
  knobs, KMS key inventories, lifecycle days, etc.)

Bumping a default — for example, adding a new EKS cluster log type — would
require touching every env unit. With `_envcommon`, the bump lives in one
file and is inherited by every consumer.

## Contents

| File                          | Module                                                       | Used by (per-env units)             |
|-------------------------------|--------------------------------------------------------------|--------------------------------------|
| `eks.hcl`                     | `terraform/modules/eks`                                      | `<env>/<region>/eks`                |
| `vpc.hcl`                     | `terraform/modules/vpc`                                      | `<env>/<region>/vpc`                |
| `kms.hcl`                     | `terraform/modules/kms`                                      | `<env>/<region>/kms`                |
| `transit-gateway.hcl`         | `terraform/modules/transit-gateway`                          | `network/<region>/transit-gateway`  |
| `budgets.hcl`                 | `terraform/modules/budgets`                                  | `<env>/_global/budgets`             |
| `centralized-logging.hcl`     | `terraform/modules/centralized-logging`                      | `log-archive/<region>/centralized-logging` |

The list will grow as new modules land (issues #170, #171, #175, #178, #182).

## How to consume from a unit

Inside `terragrunt/<env>/<region>/<module>/terragrunt.hcl`:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = find_in_parent_folders("_envcommon/eks.hcl")
  expose         = true
  merge_strategy = "deep"
}

# Inputs from `_envcommon/eks.hcl` are inherited; only override what differs.
inputs = {
  cluster_name = "platform-dev-euw1"

  # Override sizing (fewer nodes in dev).
  node_groups = {
    general = {
      instance_types = ["m6i.large"]
      desired_size   = 2
      min_size       = 1
      max_size       = 4
    }
  }
}
```

`merge_strategy = "deep"` makes top-level keys (like `inputs`) merge instead
of overwrite. The unit can also append additional `dependency` blocks; they
combine with the ones declared in `_envcommon`.

## When NOT to use `_envcommon`

- A module that is only deployed once globally (`_org/_global/...` org-wide
  resources). Their per-env knobs already live in the unit itself; an
  `_envcommon` would be a single-consumer indirection.
- One-off / experimental units that aren't part of the canonical platform
  layout.

## Bump policy

- **Adding a default** (e.g. a new optional input): no ADR required, just a
  PR + green CI. Defaults must be backwards-compatible.
- **Changing an existing default**: requires a PR comment listing every
  current consumer (use `grep -r "_envcommon/<module>.hcl" terragrunt/`)
  and a soak in non-prod.
- **Changing the module `source` path**: ADR required; this affects every
  consumer's state.
