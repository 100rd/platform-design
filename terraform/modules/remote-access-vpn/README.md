# Module: `remote-access-vpn`

Management / remote-access VPN host for the **Network account**, joined to the
hub Transit Gateway estate. Implements the VPN side of
[ADR-0013 — Inter-VPC access security model](../../../docs/adrs/0013-inter-vpc-access-security-model.md).

Ported and genericised from the infra source-of-truth `modules/pritunl-vpn`
(infra ADR-012). No real account IDs, IPs, or product-specific identifiers are
embedded — everything is driven by variables/placeholders. The default VPN
software is Pritunl OSS, but the module is product-neutral: the only public
surface is `internet -> NLB` on the VPN data port.

## What it creates

| Resource | Notes |
|---|---|
| `aws_instance.vpn` | AL2023 x86_64 (SSM param AMI), IMDSv2 required, `source_dest_check=false` for client forwarding |
| `aws_lb.vpn` + `aws_eip.nlb` | Public NLB with a static EIP — the stable VPN endpoint |
| `aws_lb_target_group.vpn_data` / `aws_lb_listener.vpn_data` | One **TCP_UDP** target group + listener on the data port (UDP + TCP fallback), `target_type=ip` |
| `aws_security_group.nlb` / `aws_security_group.instance` | NLB SG is the only public surface; the instance SG admits the data plane via an SG-reference to the NLB SG — **no `0.0.0.0/0` on the host** |
| `aws_ebs_volume.datastore` + root EBS | KMS-encrypted; dedicated datastore volume for isolated snapshots |
| `aws_cloudwatch_metric_alarm.*` | EC2 auto-recovery + NetworkOut anomaly-detection egress alarm |
| `aws_dlm_lifecycle_policy.vpn` | Daily EBS snapshots |
| `aws_flow_log.vpn_vpc` + log groups | VPC flow logs + app logs (KMS) |
| `aws_secretsmanager_secret.*` | Secret *shells* only; values injected out-of-band |

## Trust model (ADR-0013)

The VPN client pool is sub-divided by trust level:

| Sub-pool | Variable | Reaches |
|---|---|---|
| **ops** | `vpn_ops_subpool_cidr` | new prod + shared + network + all legacy ranges |
| **standard** | `vpn_standard_subpool_cidr` | the shared range **only** |

Only the **ops** sub-pool is routed/propagated to production. Enforcement is
layered and does **not** rely on the VPN host alone:

1. **TGW route-table segmentation** (primary) — see the sibling
   [`inter-vpc-security`](../inter-vpc-security/README.md) module. Prod-tier
   route tables carry a return route only for the ops sub-pool (asymmetric
   return), so standard-tier clients have no TGW return path from prod.
2. **Security groups** (this module) — default-deny; the data-plane source is
   the NLB SG; routed egress is an explicit per-CIDR allow-list
   (`reachable_cidrs`) that must agree with the TGW routes.
3. **Prod NACL backstop** — prod subnets deny the standard sub-pool (a
   cross-account, *design-target* control, modelled in `inter-vpc-security`).
4. **Centralized inspection** (future) — route inter-segment traffic through
   the inspection VPC.

The **negative test** is an acceptance requirement: a non-ops VPN client must
NOT reach prod.

## Inputs (most-used)

| Variable | Default | Purpose |
|---|---|---|
| `name` | (required) | Prefix for resource names. Use `<account>-<region>`. |
| `vpc_id` / `private_subnet_ids` / `public_subnet_ids` | (required) | Network-account VPC + subnets. |
| `kms_key_arn` | (required) | Encrypts EBS + log groups. |
| `vpn_client_cidr` | `10.100.0.0/20` | Full client pool (placeholder range). |
| `vpn_ops_subpool_cidr` | `10.100.0.0/24` | Ops tier — routed to prod. |
| `vpn_standard_subpool_cidr` | `10.100.1.0/24` | Standard tier — shared only. |
| `reachable_cidrs` | `[]` | Per-CIDR egress allow-list (must agree with TGW routes). |
| `secrets_arn_prefix` / `secrets_path_prefix` | placeholder | Scopes the IAM read + names the secret shells. |

## Security posture

- **No SSH** — SSM Session Manager only.
- **No public UI** — the web UI is reachable only from the VPN client pool over the TGW.
- **IMDSv2 required**, `hop_limit=1`.
- The NLB must be public to accept VPN connections; this is intentional and
  scoped to the data port only.

## Wiring

Deployed via the `remote-access-vpn` catalog unit in the network connectivity
stack (`terragrunt/network/<region>/connectivity`). TGW routes + the prod NACL
backstop are wired by the `inter-vpc-security` unit, which depends on this
module's `vpn_*_cidr` and `instance_security_group_id` outputs.
