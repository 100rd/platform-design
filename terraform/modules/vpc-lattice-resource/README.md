# Module: `vpc-lattice-resource`

Identity-scoped, cross-account/cross-VPC **TCP resource connectivity** via AWS
**VPC Lattice**. Implements
[ADR-0023 — VPC Lattice resource connectivity](../../../docs/adrs/0023-vpc-lattice-resource-connectivity.md):
expose an individual resource (e.g. an **RDS DB ARN**) as an IAM-authorized
endpoint reachable cross-account **without an NLB** and, intra-region, **without
threading the flow through Transit Gateway**.

**Complements** ADR-0013 (the TGW segmentation stays the general inter-VPC
substrate). VPC Lattice resource connectivity is **TCP-only** and
**single-region only** — non-TCP or cross-region flows stay on the ADR-0013 path.

Style and conventions ported from the sibling [`ram-share`](../ram-share) and
[`transit-gateway`](../transit-gateway) modules. No real account IDs, ARNs, org
IDs, or VPC/subnet IDs are embedded; callers pass representative/placeholder
values.

## What it creates

| Resource | When | Purpose |
|---|---|---|
| `aws_vpclattice_resource_gateway.this` | always | Multi-AZ NAT-style ingress in the resource-owning VPC, fronting the shared resource. |
| `aws_vpclattice_resource_configuration.this` | always | **`type = ARN`** config whose `arn_resource.arn` points at the target resource ARN (e.g. the RDS DB). TCP-only. |
| `aws_vpclattice_service_network.this` | always | The carrier (`auth_type = AWS_IAM`); the unit shared cross-account via RAM. |
| `aws_vpclattice_service_network_resource_association.this` | always | Associates the Resource Configuration to the Service Network. |
| `aws_vpclattice_auth_policy.this[0]` | `enable_auth_policy` (default on) | IAM auth policy on the Service Network, scoped via `aws:PrincipalOrgID`. |
| `aws_ram_resource_share.this[0]` + associations | `enable_ram_share` | Cross-account share of the Service Network (org-wide or specific accounts). |

## Connectivity flow

```
Resource Gateway (resource-owning VPC, multi-AZ)
  -> Resource Configuration (type = ARN -> RDS DB ARN, TCP)
    -> Service Network (AWS_IAM)  <-- SN <-> Resource association
      -> RAM share (cross-account)
        -> consumer reaches resource via a service-network VPC association/endpoint
   Authorization: IAM auth policy (aws:PrincipalOrgID-scoped) on the Service Network.
```

## Inputs (most-used)

| Variable | Default | Purpose |
|---|---|---|
| `name` | (required) | Name prefix for all resources. |
| `vpc_id` | (required) | Resource-owning VPC for the Resource Gateway. |
| `subnet_ids` | (required) | Multi-AZ subnets for the Resource Gateway ingress. |
| `security_group_ids` | `[]` | SGs on the Resource Gateway — scope to the resource port (e.g. 5432/tcp). |
| `resource_arn` | placeholder RDS ARN | The target resource ARN exposed via `type = ARN`. |
| `resource_port` | `5432` | TCP port of the shared resource. |
| `enable_auth_policy` | `true` | Attach the IAM auth policy. |
| `principal_org_id` | placeholder `o-...` | Org ID for the `aws:PrincipalOrgID` condition. |
| `allowed_principal_arns` | `[]` | Optional narrowing to specific principal ARNs. |
| `enable_ram_share` | `false` | Share the Service Network cross-account via RAM. |
| `share_with_organization` / `organization_arn` | `true` / `""` | Org-wide RAM share target. |
| `share_with_accounts` | `{}` | Targeted RAM share (when not org-wide). |

## Outputs

`resource_gateway_id` / `resource_gateway_arn`, `resource_configuration_id` /
`resource_configuration_arn`, `service_network_id` / `service_network_arn`,
`service_network_resource_association_id`, `auth_policy_id`, `ram_share_arn`.

Consumers create a **service-network VPC association/endpoint** in their own VPC
against `service_network_id` to reach the resource.

## Authorization (identity-scoped)

The auth policy allows `vpc-lattice-svcs:Invoke` only for principals whose
`aws:PrincipalOrgID` matches `principal_org_id`. Set `allowed_principal_arns` to
narrow further to specific roles. This is the **second authorization surface**
ADR-0023 calls out — keep it consistent with the resource's security groups.

## Conformance check

A reviewer confirms conformance (per ADR-0023) by verifying: a Resource Gateway
exists in the owning VPC, a `type = ARN` Resource Configuration points at the RDS
DB ARN, the Service Network is shared via RAM, the consumer reaches it via a
service-network VPC association/endpoint, and access is gated by `vpc-lattice:*`
IAM auth policies.

## Testing

`vpc-lattice-resource.tftest.hcl` runs plan-only with `mock_provider "aws" {}` —
no credentials, no real resources. Run from the module directory:

```bash
terraform init -backend=false
terraform validate
terraform test
```

**Never `terraform apply` from CI feature branches** — apply is CI/CD-only from
`main` after merge.
