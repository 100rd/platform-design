# securityhub-org

Organization-wide AWS Security Hub: account enablement, AWS Foundational +
CIS + PCI-DSS standards, org auto-enrollment, delegated administration to
the security account, and cross-region finding aggregation.

Closes #164. Thin alias around the existing `security-hub` module which
now exposes the delegated-admin and finding-aggregator additions.

## Coverage

| #164 acceptance criterion | How it's met |
|---|---|
| `modules/securityhub-org` module | This wrapper |
| Delegated admin = security account | **NEW**: `delegated_admin_account_id` -> `aws_securityhub_organization_admin_account` |
| AWS Foundational Security Best Practices standard | already in `security-hub` (`enable_aws_foundational_standard = true` default) |
| CIS AWS Foundations Benchmark standard | already in `security-hub` (`enable_cis_standard = true` default) |
| All member accounts enrolled | already in `security-hub` (`auto_enable_org = true`) |
| Aggregation across regions | **NEW**: `enable_finding_aggregator = true` -> `aws_securityhub_finding_aggregator` |

Plus PCI-DSS v3.2.1 standard subscription (defaults on, beyond the issue).

## Why a wrapper, not a rename?

Same logic as #161 (cloudtrail-org) and #162 (config-org). Renaming
`security-hub` would force state moves and break BDD compliance tests.
The wrapper gives the canonical name without churn.

## Usage — admin account (security account)

```hcl
module "security_hub_admin" {
  source = "../../terraform/modules/securityhub-org"

  delegated_admin_account_id = "111122223333"  # security account itself

  enable_finding_aggregator         = true
  finding_aggregator_linked_regions = []   # [] -> ALL_REGIONS

  enable_aws_foundational_standard = true
  enable_cis_standard              = true
  enable_pci_dss_standard          = true   # default

  auto_enable_org                = true
  auto_enable_default_standards  = true

  tags = {
    Environment = "security"
    ManagedBy   = "terragrunt"
  }
}
```

## Usage — member account

In each member account (typically via per-account terragrunt fan-out):

```hcl
module "security_hub" {
  source = "../../terraform/modules/securityhub-org"

  # Don't set delegated_admin_account_id or enable_finding_aggregator —
  # those run only in the admin account.

  enable_aws_foundational_standard = true
  enable_cis_standard              = true

  tags = { Environment = "dev" }
}
```

## Inputs

| Name | Default | Description |
|---|---|---|
| `enable_pci_dss_standard` | `true` | Subscribe to PCI-DSS v3.2.1 |
| `enable_cis_standard` | `true` | Subscribe to CIS AWS Foundations Benchmark v1.4.0 |
| `enable_aws_foundational_standard` | `true` | Subscribe to AWS Foundational Security Best Practices |
| `auto_enable_org` | `true` | Auto-enable for new org member accounts |
| `auto_enable_default_standards` | `false` | Auto-enable default standards for new members |
| `delegated_admin_account_id` | `""` | **NEW** — admin account; empty / equal-to-caller -> no delegation |
| `enable_finding_aggregator` | `false` | **NEW** — cross-region aggregation; admin account only |
| `finding_aggregator_linked_regions` | `[]` | **NEW** — empty -> ALL_REGIONS |
| `tags` | `{}` | Tags |

## Outputs

| Name | Description |
|---|---|
| `delegated_admin_account_id` | Configured delegated admin (empty if not set) |
| `finding_aggregator_enabled` | Whether the aggregator is enabled |

## Pre-conditions

- AWS Config (#162) must be enabled in the home region — Security Hub's
  control checks rely on Config. The CIS and AWS Foundational standards
  call out specific Config rules that must be present.
- The security account must be registered as a Security Hub delegated
  administrator from the management account (provision via
  `aws_organizations_delegated_administrator` with
  `service-principal=securityhub.amazonaws.com`).
- The finding aggregator should be created only in the admin account;
  member accounts should NOT enable it (would create per-account
  aggregators that don't see cross-account data).

## Cost

Security Hub charges per finding ingested. Most volume comes from the
default standards' control checks (~one finding per evaluated resource
per check). Expect $50-300/month at modest scale (~5 accounts × few
hundred resources). The aggregator is free; only the underlying findings
are billed.

## Related

- [`terraform/modules/security-hub/`](../security-hub/) — underlying module
- [`terraform/modules/config-org/`](../config-org/) — Config dependency (#162)
- [`docs/scps.md#denyguarddutychanges`](../../../docs/scps.md) — neighbour
  SCPs that protect security tooling from being disabled
