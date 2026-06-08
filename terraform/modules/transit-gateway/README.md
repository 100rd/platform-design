# Module: `transit-gateway`

Hub-and-spoke Transit Gateway for the network account. Creates the TGW,
segmented route tables (prod / nonprod / shared / optional inspection),
optional blackhole isolation routes, and an optional RAM share to spread
TGW use to workload accounts.

Closes part of issue #170.

## Resources

| Resource | When created |
|---|---|
| `aws_ec2_transit_gateway.this` | always |
| `aws_ec2_transit_gateway_route_table.this[*]` | per entry in `var.route_tables` (default: prod, nonprod, shared) |
| `aws_ec2_transit_gateway_route.blackhole_cross_env[*]` | per entry in `var.blackhole_cidrs` |
| `aws_ram_resource_share.tgw[0]` | when `length(var.ram_principals) > 0` |
| `aws_ram_resource_association.tgw[0]` | when share exists — associates TGW ARN |
| `aws_ram_principal_association.tgw[*]` | one per principal in `var.ram_principals` |

## Inputs (most-used)

| Variable | Default | Purpose |
|---|---|---|
| `name` | (required) | Prefix for resource names. Use `<account>-<region>`. |
| `amazon_side_asn` | `64512` | RFC-6996 private ASN for BGP. Use a per-region offset for multi-region. |
| `route_tables` | `{prod, nonprod, shared}` | Map of route-table-name -> empty object. Add `inspection` when #171 lands. |
| `blackhole_cidrs` | `{}` | Map of route-table-name -> CIDR for explicit isolation. |
| `ram_principals` | `[]` | List of account IDs or OU/Org ARNs to RAM-share the TGW with. Empty disables sharing. |

## Default posture

- `default_route_table_association = "disable"` and
  `default_route_table_propagation = "disable"` — every attachment
  picks its RT explicitly. No leakage.
- `auto_accept_shared_attachments = "enable"` — workload accounts can
  create attachments without round-tripping through the network team.
- `multicast_support` off by default; flip on per-region if needed.
- `vpn_ecmp_support = "enable"` for HA VPN.
- `dns_support = "enable"` so cross-account Route53 resolution works.

## Spoke attachment pattern

Workload accounts use the sibling `tgw-attachment` module. Example unit
at `terragrunt/dev/eu-west-1/tgw-attachment/terragrunt.hcl` reads the
TGW ID + route-table ID from this unit's outputs, attaches the local
VPC, and adds a `/8` route in the VPC's private subnets pointing back
at the TGW.

## Outputs

- `transit_gateway_id`, `transit_gateway_arn`, `transit_gateway_owner_id`
- `route_table_ids` — map keyed by RT name
- `ram_resource_share_arn` — `null` when `ram_principals` is empty

## Cost

Transit Gateway: \$0.05/attachment-hour + \$0.02/GB processed. With 4
spoke VPCs attached at all hours = ~\$144/month attachment cost; data
processing scales with traffic.

## Rollback

`terraform destroy` against the consuming unit. Order: destroy spoke
attachments first (otherwise TGW won't release), then the TGW unit.
The RAM share unwinds with the TGW.
