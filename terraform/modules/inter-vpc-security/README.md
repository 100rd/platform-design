# Module: `inter-vpc-security`

Inter-VPC access security wiring for the hub Transit Gateway. Implements the
**segmentation** side of
[ADR-0013 — Inter-VPC access security model](../../../docs/adrs/0013-inter-vpc-access-security-model.md):
TGW route-table segmentation per the trust model, the **legacy-side routes**
(cross-estate VPN join), and the **prod-side NACL backstop** — the two parts
ADR-0013 flags as design-targets.

Pairs with the [`remote-access-vpn`](../remote-access-vpn/README.md) module
(the VPN host) and builds on the existing `transit-gateway` module (ADR-0005
hub-spoke). Ported and genericised from infra `modules/tgw-routing` (infra
ADR-012) — no real account IDs, CIDRs, or attachment IDs are embedded; callers
pass representative/placeholder values.

## Why TGW routes are not enough on their own

TGW route tables filter by **destination**, not by source IP within an
attachment. The ops/standard trust split is therefore enforced by **three
layered controls**:

| Control | Where | This module |
|---|---|---|
| (a) VPN route-push | VPN host profiles advertise different CIDRs per tier | `remote-access-vpn` |
| (b) Prod NACL backstop | prod subnets deny the standard sub-pool | **here** |
| (c) Asymmetric return routes | prod-tier RTs return only to the ops sub-pool | **here** |

## What it creates

| Resource | When | Purpose |
|---|---|---|
| `aws_ec2_transit_gateway_route_table.network_vpn` | `enable_vpn_routing` | The VPN attachment's own isolated RT (no default route) |
| `aws_ec2_transit_gateway_route_table_association.network_vpn` | `enable_vpn_routing` | Associates the VPN attachment with its RT |
| `aws_ec2_transit_gateway_route.vpn_forward[*]` | `enable_vpn_routing` | Outbound allow-list — one route per permitted destination (incl. **legacy-side routes** via the legacy admin-VPC attachment) |
| `aws_ec2_transit_gateway_route.vpn_return[*]` | `enable_vpn_routing` | Return routes on spoke RTs — **ops sub-pool only** for prod-tier (asymmetric), full pool for shared/dev |
| `aws_network_acl_rule.prod_allow_ops_subpool[*]` | `enable_prod_nacl_backstop` | ALLOW the ops sub-pool on prod subnets (lower rule number) |
| `aws_network_acl_rule.prod_deny_standard_subpool[*]` | `enable_prod_nacl_backstop` | **DENY the standard sub-pool** on prod subnets (the backstop) |

## Legacy-side routes (the cross-estate seam)

The legacy estate is reachable **via the Transit Gateway** using the legacy
admin-VPC's *existing* attachment — **no new VPC peering** (ADR-0013 Alternative
A, ADR-0005). Pass the legacy ranges as `vpn_forward_routes` entries whose
`tgw_attachment_id` is the legacy admin-VPC attachment ID. The matching *return*
routes on the legacy side are owned by legacy-ops (out-of-repo) and tracked as a
cross-account follow-up in ADR-0013.

## Sequencing gate (read before enabling)

`enable_vpn_routing = true` must be flipped **only after**:

1. the network VPC + its TGW attachment are applied, **and**
2. the prod NACL backstop (`enable_prod_nacl_backstop = true`) is in place,

otherwise the standard sub-pool transiently reaches prod via the TGW. Both
flags default to `false`. The NACL backstop is intentionally independent of
`enable_vpn_routing` so it can be applied *first*.

## Inputs (most-used)

| Variable | Default | Purpose |
|---|---|---|
| `transit_gateway_id` | (required) | Hub TGW ID. |
| `enable_vpn_routing` | `false` | Master gate for VPN TGW routing. |
| `network_vpc_id` | `""` | VPN VPC, used to look up its attachment. |
| `vpn_forward_routes` | `{}` | `key -> { destination_cidr, tgw_attachment_id }` allow-list (incl. legacy). |
| `vpn_return_routes` | `{}` | `key -> { route_table_id, vpn_pool_cidr }` (ops sub-pool for prod). |
| `enable_prod_nacl_backstop` | `false` | Apply the prod NACL deny of the standard sub-pool. |
| `prod_subnet_nacl_ids` | `[]` | Prod subnet NACL IDs (from the prod-account VPC unit). |
| `vpn_ops_subpool_cidr` / `vpn_standard_subpool_cidr` | placeholders | Trust sub-pools. |

## Conformance check

A reviewer confirms conformance by verifying that every attachment is
associated with an explicit custom route table and that **no route table grants
a dev/standard source a path into prod**. The acceptance test is a **negative
test**: a non-ops VPN client must NOT reach prod, verified end-to-end.
