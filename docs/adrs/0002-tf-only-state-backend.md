# ADR-0002: Terraform-only state backend bootstrap

- Status: **Accepted**
- Date: 2026-05-04
- Authors: platform-team
- Related issues: #159, #160
- Supersedes: (none)
- Superseded by: (none)

## Context

The Terraform state backend (S3 bucket + DynamoDB lock table) is a
chicken-and-egg problem: the state for all other modules lives in the
backend, but the backend itself has to be created somewhere. The repo
needs a deterministic, idempotent way to provision that backend so a
fresh AWS account can be onboarded without manual console clicks.

The natural Terragrunt answer is "let Terragrunt auto-create the backend
on first init" — but that makes the bootstrap implicit, opaque to audit,
and impossible to manage as code (no version history of the bucket
configuration, lifecycle policies, encryption, etc.).

Issue #159 asks for a Terraform-only bootstrap module + script.

## Decision

The state backend (S3 bucket + DynamoDB table per account, per region)
is provisioned by a **Terraform-only module** at `terraform/modules/state-backend`,
invoked from `bootstrap/state-backend/` via `terraform init` + `terraform
apply` (no Terragrunt wrapper). State is local-only for this module
(`terraform.tfstate` lives in `bootstrap/state-backend/<account>/`); a
deploy script (`scripts/deploy-state-backends.sh`) iterates accounts and
applies. After bootstrap, every other module uses Terragrunt with the
S3 backend pointing at the bucket created here.

The bootstrap state file is intentionally NOT migrated into S3 itself
(would re-create the chicken-and-egg). It's checked into git via
`.gitignore` exception for `bootstrap/state-backend/<account>/terraform.tfstate*`.

DR-replicated state (issue #160) is provisioned by a sibling module
`terraform/modules/state-backend-dr` with aliased providers; it depends
on streams being enabled on the source DynamoDB table, gated by
`enable_dynamodb_streams = false` (default) for backwards compatibility.

## Alternatives considered

### Alternative A: Terragrunt auto-bootstrap
Let Terragrunt create the bucket and table on first `init` via the
`generate "remote_state"` block that already exists in `root.hcl`.

Rejected because: implicit creation gives no auditable IaC trail of the
bucket configuration (versioning, KMS, lifecycle, public-access-block).
Terragrunt's auto-create only sets minimal defaults — KMS-SSE, Object
Lock, lifecycle aren't configured.

### Alternative B: CloudFormation bootstrap
Use a CloudFormation template applied via the AWS console or CLI for
the bootstrap.

Rejected because: introduces a second IaC tool just for one module,
splits the team's mental model, and the rest of the org is Terraform-only
by convention.

### Alternative C: Shell script with AWS CLI
Hand-roll the bucket and table creation in a bash script.

Rejected because: not idempotent without significant work, and not
revisable as code (drift detection harder).

## Consequences

### Positive
- Bootstrap is reproducible and reviewable as code.
- Bucket configuration (versioning, KMS, lifecycle, Object Lock) is
  versioned in git.
- DR replication (#160) layers cleanly on top.

### Negative
- The bootstrap state file lives in the repo (committed) — it's a small
  JSON file containing only the bucket and table ARN/name, no secrets.
  We accept this trade-off rather than add yet another circular dependency.
- The deploy script needs AWS credentials with `s3:CreateBucket`,
  `dynamodb:CreateTable`, `iam:CreateRole`, etc. — typically run by an
  org admin during onboarding only.

### Risks
- An accidental commit to the bootstrap state file (`terraform apply`
  during local development) would create unintended buckets. Mitigated
  by `bootstrap/state-backend/README.md` documentation and the deploy
  script's `--account` flag enforcement.

## Implementation notes

- Files added in #159:
  - `terraform/modules/state-backend/` — module
  - `bootstrap/state-backend/` — root configuration
  - `scripts/deploy-state-backends.sh` — orchestrator
- Files added in #160:
  - `terraform/modules/state-backend-dr/` — DR sibling module
  - Extended `state-backend` with `enable_dynamodb_streams` toggle
- Rollback: revert PRs #189 / #190 separately. The buckets and tables
  remain in AWS unless explicitly destroyed (no `terraform destroy` is
  invoked from CI).

## References

- Issues #159, #160
- PRs #189, #190
- `bootstrap/state-backend/README.md`
- `docs/runbooks/state-backend-failover.md`
