# bootstrap/state-backend

First-time provisioning of the Terraform/Terragrunt remote-state backend
(S3 bucket + DynamoDB lock table) for a single AWS account.

Closes #159: TF-only state backend bootstrap (no CloudFormation).

## Why this is a separate stack

Every Terragrunt unit in `terragrunt/` resolves its state location to
`s3://tfstate-<account>-<region>` and `dynamodb://terraform-locks-<account>`
(see `terragrunt/root.hcl`'s `remote_state` block). Until those resources
exist, no Terragrunt unit can run.

This stack creates them. Its own state is **local** (no backend block in
`main.tf`) — it's the only stack in the repo that doesn't depend on remote
state already existing.

## Usage

The stack is normally invoked via `scripts/deploy-state-backends.sh`, which
handles role assumption into each member account. You can also run it
directly if you've already configured AWS credentials for the target
account.

### Via the script (recommended)

Authenticate to the **management account** first, then:

```bash
# Plan all member accounts
./scripts/deploy-state-backends.sh plan

# Apply to all accounts
./scripts/deploy-state-backends.sh apply

# Single account
./scripts/deploy-state-backends.sh plan dev
./scripts/deploy-state-backends.sh apply dev
```

The script assumes `OrganizationAccountAccessRole` in each target account
(this role is created by AWS Organizations when an account is invited or
created). It copies this directory to a temp workspace, symlinks
`terraform/modules/`, and runs `terraform init/plan/apply`.

### Direct invocation (advanced)

```bash
cd bootstrap/state-backend
terraform init
terraform plan -var=account_name=dev -var=aws_region=eu-west-1
terraform apply -var=account_name=dev -var=aws_region=eu-west-1
```

## Idempotency

Re-running `apply` on an account that already has the backend is a no-op.
Both resources carry `lifecycle.prevent_destroy = true`, so accidental
destroys fail loudly. Lifecycle changes that would force replacement are
also blocked.

## Verification

After apply, confirm the resources exist:

```bash
aws s3 ls "s3://tfstate-${ACCOUNT}-${REGION}/"
aws dynamodb describe-table --table-name "terraform-locks-${ACCOUNT}"
```

Then any Terragrunt unit in `terragrunt/${ACCOUNT}/...` should `init`
cleanly and `terragrunt plan` without errors.

## Bootstrapping order

| # | Account | Reason |
|---|---------|--------|
| 1 | management | Hosts org-wide units (`_org`), needed first to enable Organizations / SSO / SCPs |
| 2 | network | Hosts Transit Gateway, shared VPCs |
| 3 | dev / staging / prod / dr | Workload accounts, each gets its own backend |

`management` is bootstrapped first because subsequent steps need it (e.g.
SCPs and SSO require management-account state). The remaining accounts can
be bootstrapped in any order.

## Rollback

To tear down a backend (rare — typically only when retiring an account):

1. Empty the bucket (all object versions, all delete markers).
2. Remove `lifecycle.prevent_destroy = true` from
   `terraform/modules/state-backend/main.tf` (or set it via a `var.` toggle
   in a follow-up PR).
3. Run `terraform destroy` against this stack.

This is intentionally painful — losing the state bucket means losing every
unit's state in that account.

## What this stack does NOT do

- Cross-region replication (DR for state itself) — see #160.
- KMS CMK creation — pass an existing CMK via `kms_key_arn` if you want CMK
  encryption today; otherwise AWS-managed keys are used.
- Account creation — `OrganizationAccountAccessRole` must already exist
  (i.e. the account must be a member of the organization).
