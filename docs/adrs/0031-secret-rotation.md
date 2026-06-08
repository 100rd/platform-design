# ADR-0031: Automated secret rotation via Secrets Manager rotation Lambda + ESO auto-refresh

- Status: **Accepted** — doc-verified; ratified, not yet implemented.
- Ratified: 2026-06-08 by platform owner.
- platform-design status: **pending** — module and Terragrunt unit exist in this
  repo but no rotation Lambda is deployed and no live secret is wired to a rotation
  schedule yet.
- Date: 2026-06-08
- Authors: platform-team, security
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)

## Context

Database (RDS) credentials and upstream API keys are stored in AWS Secrets Manager
and surfaced into clusters by External Secrets Operator (ESO, ADR-0008). Today those
values are **static and long-lived**: a credential set once stays in place until
someone rotates it by hand. That is the classic standing-credential risk — a leaked
DB password or model-provider API key is valid until manually noticed and replaced,
and PCI-DSS Req 3.6.4 / 8.3.9 explicitly require credentials to be cycled on a
defined cryptoperiod.

The existing `modules/secrets` module already wires `aws_secretsmanager_secret_rotation`
**if a rotation Lambda ARN is handed to it**, but nothing in the repo actually
**produces** that Lambda. So the rotation hook is present but dead — there is no
function to call, no schedule running, and no least-privilege IAM/VPC plumbing for
the rotator to reach a private RDS instance.

There is also a second half of the problem: even if Secrets Manager rotates a value,
**running pods keep the old value** unless something re-pulls and re-rolls them. ESO
caches the materialized `Secret`; pods read it once at start. Rotation that the
workload never picks up is worse than no rotation — it silently breaks auth on the
next connection.

## Decision

Adopt **automated, scheduled rotation of DB and API credentials** using a **Secrets
Manager rotation Lambda** plus **ESO auto-refresh of consuming pods**, replacing the
static long-lived secret model:

- **A dedicated `modules/secret-rotation` Terraform module** provisions the missing
  half:
  - `aws_secretsmanager_secret` (KMS-encrypted with a customer-managed CMK) for the
    credential it owns,
  - `aws_secretsmanager_secret_rotation` with `rotation_rules`
    (`automatically_after_days` **or** a `schedule_expression` cron/rate window, plus
    an optional `duration` window),
  - the **rotation `aws_lambda_function`** itself — either a **custom handler** or one
    of the **AWS-provided RDS rotation templates** (single-user or
    alternating-user). The module ships a placeholder handler and accepts an override
    package so a real RDS template can be dropped in,
  - **least-privilege IAM** for the rotator: `secretsmanager:GetSecretValue` /
    `PutSecretValue` / `DescribeSecret` / `UpdateSecretVersionStage` scoped to **this
    secret's ARN only**, `secretsmanager:GetRandomPassword`, and `kms:Decrypt` /
    `kms:GenerateDataKey` scoped to the secret's CMK,
  - **VPC config** (`vpc_config` subnets + security group) so the Lambda can reach a
    **private** RDS instance, with the AWS-managed
    `AWSLambdaVPCAccessExecutionRole` for ENI management.

- **ESO auto-refresh** closes the loop on the workload side. Each `ExternalSecret`
  sets a **`refreshInterval`** so ESO **re-pulls the rotated `SecretString`** from
  Secrets Manager on that cadence and updates the materialized K8s `Secret`. To roll
  the **pods** that mounted it, use **Stakater Reloader** (watches the `Secret` and
  triggers a rolling restart of annotated Deployments) — equivalently, ESO can stamp
  a content checksum the Deployment template references so a value change forces a new
  pod template hash.

A reviewer can check conformance by confirming: a rotation Lambda exists and is wired
to the secret via `aws_secretsmanager_secret_rotation`; the rotator's IAM is scoped to
that single secret ARN + its CMK (not `*`); the Lambda has VPC config reaching the
RDS subnets; the `ExternalSecret` for the rotated credential sets a bounded
`refreshInterval`; and the consuming Deployment is annotated for Reloader (or carries
a checksum) so rotation actually reaches the pods.

## Alternatives considered

### Alternative A: Status quo — static long-lived secrets, manual rotation
Keep credentials in Secrets Manager but rotate by hand when someone remembers.
Rejected because: standing credentials are valid until manually replaced — the core
risk PCI-DSS Req 3.6.4/8.3.9 targets. Manual rotation does not scale across many DBs
and API keys and is the step most often skipped.

### Alternative B: Rotation Lambda but no ESO refresh (no `refreshInterval`/Reloader)
Rotate the value in Secrets Manager but leave pods to pick it up only on the next
deploy/restart.
Rejected because: the materialized K8s `Secret` and the running pods keep the **old**
value until an unrelated restart — auth breaks on the next reconnect after the old
credential is retired. Rotation the workload never observes is a regression, not a fix.
The `refreshInterval` + Reloader (or checksum) pattern is what makes rotation safe.

### Alternative C: Short-lived dynamic credentials via Vault DB secrets engine
Issue ephemeral DB credentials on demand instead of rotating a stored one.
Rejected because: it reintroduces a self-managed Vault (HA, unseal, backup) that
ADR-0008 already declined in favor of managed Secrets Manager. Secrets Manager
rotation gives a managed cryptoperiod cycle without running Vault.

### Alternative D: AWS-managed rotation only, never a custom handler
Use only the AWS-provided RDS rotation templates and forbid custom rotators.
Rejected as the *blanket* rule because: DB creds map cleanly to the RDS templates, but
**upstream model-provider API keys** have no AWS template — they need a custom handler
that calls the provider's key-rotation API. The module supports **both**: RDS template
for databases, custom handler for API keys.

## Consequences

### Positive
- DB and API credentials are cycled on a defined cryptoperiod automatically
  (PCI-DSS Req 3.6.4/8.3.9), shrinking the window a leaked credential is usable.
- The rotation hook in `modules/secrets` is no longer dead — `modules/secret-rotation`
  produces the Lambda + IAM + VPC plumbing it needed.
- Rotation actually reaches running pods via ESO `refreshInterval` + Reloader, so the
  rotated value is used instead of silently breaking auth.
- Least-privilege: the rotator can touch only its own secret ARN and that secret's CMK.

### Negative
- A rotation Lambda is real code to own, deploy, and keep current (handler, VPC ENIs,
  dependency on RDS/provider reachability from the Lambda subnets).
- `refreshInterval` adds steady Secrets Manager `GetSecretValue` traffic (and cost) per
  `ExternalSecret`; the interval must be tuned, not set to seconds.
- The first rotation happens **as soon as rotation is enabled** (Secrets Manager
  behavior, and `rotate_immediately` defaults to `true`) — all consumers must already
  pull from Secrets Manager before enabling, or they break.

### Risks
- A mis-scoped rotator IAM policy (e.g. `secretsmanager:*` on `*`). Mitigated by the
  module scoping every statement to the single secret ARN + its CMK and a Checkov gate.
- The Lambda cannot reach a private RDS from its subnets/SG, leaving rotation stuck in
  `AWSPENDING`. Mitigated by explicit `vpc_config` inputs and a security group rule to
  the DB port, validated before enabling.
- Rotation succeeds but pods never refresh (`refreshInterval` too long or Reloader
  missing), so auth breaks at the old-credential retirement. Mitigated by requiring a
  bounded `refreshInterval` and Reloader annotation (or checksum) on consumers, and the
  conformance check above.

## Implementation notes

- Files / modules touched: a new `terraform/modules/secret-rotation`
  (`aws_secretsmanager_secret` + `aws_secretsmanager_secret_rotation` + rotation
  `aws_lambda_function` + scoped IAM + `vpc_config`), a Terragrunt unit wiring it for a
  given environment/region (RDS subnets/SG + KMS CMK as dependencies), and an
  `apps/infra/external-secrets` README note on `refreshInterval` + the Reloader pattern.
- Migration: ensure every consumer already reads the credential from Secrets Manager
  via ESO; deploy the rotation Lambda; enable rotation (the secret rotates once
  immediately); confirm ESO re-pulls within `refreshInterval` and Reloader rolls the
  pods; only then retire the old static value.
- Rollback: remove the `aws_secretsmanager_secret_rotation` wiring to stop scheduled
  rotation (note: an in-flight rotation can leave `AWSPENDING` staging labels that may
  need manual cleanup — provider docs warn on this); the secret and ESO sync remain.
- CI/test: `terraform test` (mock provider) over the module; Checkov over the IAM and
  Lambda config; manifest-validate (ADR-0016) over any `ExternalSecret`/Reloader
  annotation changes.

Effort: **M**.

## References

- Terraform `aws_secretsmanager_secret_rotation`:
  <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_rotation>
- AWS Secrets Manager — Rotate secrets (custom + RDS templates):
  <https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html>
- AWS rotation Lambda function requirements (single-user / alternating-user):
  <https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets-required-lambda-function.html>
- AWS-provided RDS rotation templates:
  <https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_available-rotation-templates.html>
- External Secrets Operator `refreshInterval`:
  <https://external-secrets.io/latest/api/externalsecret/>
- Stakater Reloader (rolling restart on Secret/ConfigMap change):
  <https://github.com/stakater/Reloader>
- Lambda VPC access execution role:
  <https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html>
- Related: ADR-0008 (External Secrets Operator — delivers the rotated value to pods),
  the existing `modules/secrets` rotation hook this module feeds.

---
*Doc-verified 2026-06-08 (HashiCorp registry provider docs + official AWS Secrets
Manager rotation docs) — 2026 platform modernization; grounded in
infra@572b54d / argocd@c364c6c. Accepted, ratified 2026-06-08 by platform owner; not
yet implemented in platform-design.*
