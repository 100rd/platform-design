# Organizational Unit (OU) Structure

This document describes the AWS Organizations OU hierarchy enforced by the
`terraform/modules/organization` module and consumed by the `scps`,
`security-hub`, `guardduty-org`, and `aws-config` modules.

Closes part of issue #158.

## Hierarchy

```
Root
├── Security                    (top-level)
├── Infrastructure              (top-level)
├── Workloads                   (top-level)
│   ├── NonProd                 (nested — alias: Non-Production)
│   └── Prod                    (nested — alias: Production)
├── Deployments                 (top-level — issue #158)
├── Sandbox                     (top-level — issue #158)
└── Suspended                   (top-level — created by module directly)
```

**8 OUs total.** Five are top-level (`Security`, `Infrastructure`, `Workloads`,
`Deployments`, `Sandbox`, `Suspended`). Two are nested under `Workloads`
(`NonProd`, `Prod`).

## OU intent

| OU | Intent | Account placement |
|---|---|---|
| `Security` | Audit and security-tooling accounts. Read-only access to other accounts; cross-region SecurityHub aggregator lives here. | `security`, `log-archive`, `third-party` |
| `Infrastructure` | Shared platform tooling. Networking hub (TGW, Route53), shared services (ECR, ACM CA). | `network`, `shared` |
| `Workloads` | Container OU for application accounts. SCPs that apply to all workloads attach here. | (no direct accounts; only nested OUs) |
| `Workloads/NonProd` | Non-production workload accounts (dev/staging). Region-restricted, deny-root, no production secrets. | `dev`, `staging` |
| `Workloads/Prod` | Production workload accounts. Strict SCPs, MFA-protected break-glass, full SecurityHub coverage. | `prod`, `dr` |
| `Deployments` | AFT (Account Factory for Terraform) account, CI/CD automation, deployment-specific service accounts. SCPs deny direct workload data plane access. | (filled when AFT lands — #168) |
| `Sandbox` | Developer experimentation. Region-restricted, deny-root, hard spend caps via Budgets (#175), no shared services. | (filled per-developer on demand) |
| `Suspended` | Quarantine OU for compromised, decommissioned, or under-investigation accounts. `deny-all-suspended` SCP blocks all actions except by `OrganizationAccountAccessRole`. | (filled via incident response) |

## Canonical-name mapping

Issue #158 calls for OUs named `Production`, `Non-Production`, `Deployments`,
`Suspended`, `Sandbox`. This repo uses shorter names for backwards compatibility
with already-deployed SCPs and SSO permission-set assignments
(see PRs #191, #192). The mapping:

| Canonical (#158) | This repo | Notes |
|---|---|---|
| Production | `Prod` | Nested under `Workloads`, not top-level — capacity to add `Prod-EU`, `Prod-US` siblings later. |
| Non-Production | `NonProd` | Nested under `Workloads`. |
| Deployments | `Deployments` | Top-level (matches canonical). |
| Suspended | `Suspended` | Top-level (matches canonical). Created hard-coded by the organizations module. |
| Sandbox | `Sandbox` | Top-level (matches canonical). |

The `Security`, `Infrastructure`, and `Workloads` OUs in this repo are
**additional** — they organise accounts by function, on top of the
environment-/lifecycle-axis defined by the canonical 5.

## SCP attachment matrix

The `scps` module attaches SCPs by `for_each` over the `ou_ids` map. Every OU
defined in the `organizational_units` input automatically receives the
appropriate guardrails:

| SCP | Root | Security | Infrastructure | Workloads | NonProd | Prod | Deployments | Sandbox | Suspended |
|---|---|---|---|---|---|---|---|---|---|
| `DenyLeaveOrganization` | – | yes | yes | yes | yes | yes | yes | yes | yes |
| `DenyDisableCloudTrail` | – | yes | yes | yes | yes | yes | yes | yes | yes |
| `DenyRootAccount` | – | – | – | – | yes | yes | – | yes | yes (via `DenyAllSuspended` umbrella) |
| `RestrictRegions` | – | yes | yes | yes | yes | yes | yes | yes | yes |
| `DenyDisableGuardDuty` | – | yes | yes | yes | yes | yes | yes | yes | yes |
| `DenyExternalPrincipals` | – | yes | yes | yes | yes | yes | yes | yes | yes |
| `DenyS3Public` | yes | – | – | – | – | – | – | – | – |
| `RequireEbsEncryption` | yes | – | – | – | – | – | – | – | – |
| `DenyAllSuspended` | – | – | – | – | – | – | – | – | yes |

`workload_ou_names` controls the `DenyRootAccount` attachment list. After #158
this is `["NonProd", "Prod", "Sandbox"]` — Sandbox is bias-toward-defence,
Deployments is excluded because its accounts run AFT/CI tooling under
programmatic IAM principals (no human root usage expected).

AWS limits 5 SCPs per OU including the inherited `FullAWSAccess` from root.
Each non-Suspended OU currently has 5 SCPs attached + `FullAWSAccess` from
root = 6 entries in the policy chain, which fits AWS's effective limit
because `FullAWSAccess` is inheritance-only and doesn't count against the OU
attachment cap.

## Operational notes

### Adding a new OU
1. Add to `organizational_units` in
   `terragrunt/_org/_global/organization/terragrunt.hcl`.
2. Add to the `mock_outputs.ou_ids` map in
   `terragrunt/_org/_global/scps/terragrunt.hcl` (so plan-with-mocks works).
3. If the OU is workload-bearing, add it to `workload_ou_names` in the SCPs
   unit so `DenyRootAccount` attaches.
4. Run `terragrunt plan` from the management account and verify the new
   `aws_organizations_policy_attachment` resources.
5. Update this document with the OU's intent and SCP coverage.

### Moving an account between OUs
```bash
aws organizations move-account \
  --account-id 111111111111 \
  --source-parent-id ou-current-id \
  --destination-parent-id ou-target-id
```
The Organization unit's state-file does NOT track membership of accounts —
account-to-OU placement is managed via the `member_accounts` map's `ou` field.
Edit that, then `terragrunt apply`.

### Quarantining an account
```bash
aws organizations move-account \
  --account-id 111111111111 \
  --source-parent-id $CURRENT_OU \
  --destination-parent-id $SUSPENDED_OU_ID
```
The `DenyAllSuspended` SCP prevents all actions except those by
`OrganizationAccountAccessRole` — which is reserved for break-glass
operations and offboarding runbooks.

## References

- Issue #158 (this implementation)
- Issue #157 (Control Tower account structure)
- Source repo: `qbiq-ai/infra` issues #114, #115, #116, #117
- AWS docs: <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_ous.html>
- AWS Control Tower OU best practices:
  <https://docs.aws.amazon.com/controltower/latest/userguide/organizations.html>
