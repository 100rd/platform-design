# SPEC-02 — Network Topology & DNS

> Portable reverse-engineering of the platform's network and DNS design. A senior
> platform team can rebuild the same connectivity substrate for a new client from this
> spec alone. Global placeholders (`{{…}}`) are defined in `SPEC-00-overview.md` and shared
> with `SPEC-01`; spec-local placeholders are registered in the Parameterization table (§5).
> No real account IDs, ARNs, hostnames, or non-documentation IPs appear.

---

## 1. Scope & non-goals

This spec covers the **AWS network substrate** and the **DNS control plane** for a
multi-account, multi-region platform: the hub-and-spoke Transit Gateway (TGW) topology,
the deterministic per-environment/region VPC CIDR allocation scheme, subnet/AZ layout,
egress/ingress paths, VPC interface/gateway endpoints, cross-account Route 53 Resolver,
the inter-VPC segmentation security model, cross-region TGW peering, the multi-geo /
multi-cloud edges (bare-metal DC, GCP), and the DNS stack — authoritative-zone sync across
two providers (octoDNS), a DNS health monitor, and a registrar-level DNS failover
controller. It states the **CNI network rationale** (Cilium) only at the level that shapes
VPC/CIDR/east-west design.

**Non-goals.** Cluster-internal networking detail — Cilium install, `CiliumNetworkPolicy`
authoring, Gateway API `HTTPRoute` mechanics, ClusterMesh operational runbooks — belong to
**SPEC-03 (Compute Clusters)**; this spec sets the substrate and stops at that
boundary. Account/OU structure, Terragrunt orchestration, remote state, and version pins
belong to **SPEC-01 (Foundation: IaC, Account Topology & State)**. Secrets, KMS, IAM
identity, SCP/GuardDuty *contents*, and WAF/CDN edge security are only cross-referenced.

---

## 2. Architecture

### 2.1 Component map

```
                          Registrar (nameserver authority for {{DOMAIN}})
                               ▲  UpdateNameservers()  (failover / failback)
                               │
                    ┌──────────┴───────────┐
                    │  failover-controller │  Go, 30s tick, 5-state machine + safety guards
                    │ HEALTHY→…→FAILED_OVER │  reads health scores from Postgres
                    └──────────┬───────────┘
                               │ reads dns_provider_health_score (0–100)
                    ┌──────────┴───────────┐        ┌───────────────────────┐
                    │     dns-monitor      │───────▶│  Postgres (health DB) │
                    │ Go, 30s, dig NS TXT, │        └───────────────────────┘
                    │ score 0–100, Prom    │
                    └──────────────────────┘
    authoritative zone data (YAML)                 in-cluster record automation
        │  octoDNS plan/apply                         │  external-dns (Route53), upsert-only
        ▼                                             ▼
 ┌─────────────────┐   ┌─────────────────┐     ┌──────────────────────────────┐
 │ {{PRIMARY_DNS}} │   │ {{SECONDARY_DNS}}│     │  EKS clusters (Cilium CNI)   │
 │  (cloudflare)   │   │   (route53)     │     │  Gateway API → NLB (SPEC-03) │
 └─────────────────┘   └─────────────────┘     └──────────────────────────────┘

 AWS network substrate (Network account owns the hub):

   Internet                                          Internet
      │ ingress (NLB per Gateway)                        ▲ egress
      ▼                                                  │
 ┌──────────────────────────────── Spoke VPC (per env × region) ─────────────────┐
 │  public /20 × AZ   private /20 × AZ   database /20 × AZ                        │
 │      │ IGW              │ NAT GW (1/AZ, HA)      │                             │
 │      └── ALB/NLB        └── nodes/pods ──────────┴── RDS                       │
 │                          │  (2 gateway + 13 interface VPC endpoints)          │
 │                          └──────────── TGW attachment (inert until routed) ───┼──┐
 └───────────────────────────────────────────────────────────────────────────────┘  │
                                                                                       ▼
                      ┌───────────────── Transit Gateway (Network acct) ──────────────┐
                      │  ASN {{TGW_ASN}} · default assoc/propagation = DISABLE        │
                      │  custom route tables:  prod  |  nonprod  |  shared            │
                      │  RAM-shared to all workload accounts                          │
                      │  blackhole CIDRs enforce env isolation                        │
                      └───────┬───────────────────────────┬──────────────────────────┘
              route53-resolver│ (inbound+outbound, DNS 53)│ TGW peering (cross-region, scaffolded)
              remote-access-VPN│ (ops/standard sub-pools)  ▼
                               │                   TGW (peer region euc1) — staging CIDRs
                               ▼
                       Legacy estate (admin VPC already attached; join via TGW, no new peering)
```

### 2.2 Layers

1. **L3 substrate — hub-and-spoke TGW.** One TGW per region in the Network account, hub
   for all inter-VPC/inter-account traffic. Reachability is an **explicit allow-list**
   (`default_route_table_association = disable`, `default_route_table_propagation =
   disable`); three custom route tables (`prod`, `nonprod`, `shared`) enforce environment
   isolation. Cross-region is a **second TGW + peering attachment**, not a global mesh.
2. **VPC plane.** Each `environment × region` pair owns a deterministic `/16`. Subnets are
   `/20` slices (private/public/database) derived by `cidrsubnet`. NAT is HA (one per AZ)
   by default. VPC Flow Logs on (PCI-DSS Req 10, 365-day retention). Two gateway endpoints
   (S3, DynamoDB) + 13 interface endpoints keep AWS-API traffic off the NAT path.
3. **Segmentation security model.** Deny-by-default TGW route tables (Layer 1) + security
   groups (Layer 2) + NACL backstop (Layer 3) + future centralized inspection VPC
   (Layer 4). A cross-estate remote-access VPN joins a legacy flat-peering estate through
   the TGW with **trust sub-pools** (ops vs standard) so a standard client can never
   transit to prod.
4. **Identity-scoped resource access.** VPC Lattice resource gateway (TCP-only,
   single-region) exposes a shared resource (e.g. RDS) by **IAM identity**, bypassing the
   NLB and — intra-region — the TGW for that flow. Complements, does not replace, the TGW
   model.
5. **East-west between clusters.** Default is **Cilium ClusterMesh** over the peered TGW
   (non-overlapping routable pod CIDRs, ENI/native mode); SG ports `2379` (etcd), `4240`
   & `4244` (health), `51871` (WireGuard). A selection matrix falls back to PrivateLink /
   VPC Lattice / internal-NLB+Route53-PHZ / private ingress per flow shape. The
   GPU-inference cluster instead joins the TGW via **TGW Connect (GRE+BGP)** propagating
   its pod CIDR `100.64.0.0/10`.
6. **DNS control plane.** Authoritative zones are declared as YAML and pushed to **two**
   providers by octoDNS. `dns-monitor` scores each provider's health; `failover-controller`
   swaps registrar nameservers when the primary degrades. In-cluster records are automated
   by `external-dns` (upsert-only). Cross-account private resolution uses Route 53 Resolver
   inbound/outbound endpoints in the Network VPC.

---

## 3. Decision record

| Decision | Rationale | Trade-off accepted | Source ADR |
|---|---|---|---|
| Hub-and-spoke **Transit Gateway**, owned by the Network account; custom route tables, no default assoc/propagation | Scales past peering combinatorics (N·(N-1)/2); segmentation becomes route-table policy, not per-pair bookkeeping; single point for future inspection VPC | ~$36/mo per attachment + inter-VPC data-processing charge; RT bookkeeping grows; cross-region needs a 2nd TGW | `ADR-0005 Hub-and-spoke connectivity via AWS Transit Gateway` |
| **Deny-by-default inter-VPC model**: TGW route-table segmentation + SG + NACL backstop + (future) inspection VPC; cross-estate VPN via TGW with ops/standard **trust sub-pools** | Guarantees prod isolation even with a cross-estate VPN + legacy flat peering; "who can reach prod" is a one-line answer; incremental | More RT/SG/NACL bookkeeping; VPN allow-list is change-controlled; sequencing gate before enabling routing | `ADR-0013 Inter-VPC access security model` |
| **VPC Lattice resource connectivity** for cross-account/VPC TCP resource access (RDS), alongside the TGW model | Unit of control becomes the **IAM identity**, not the network path; drops NLB + intra-region TGW from that flow; centralized RAM sharing | TCP-only, **single-region only**; a second authZ surface to keep consistent with SGs | `ADR-0023 VPC Lattice resource connectivity` |
| **Cilium** as EKS CNI (over aws-vpc-cni / Calico) | eBPF dataplane; transparent WireGuard pod-to-pod encryption (data-in-transit baseline); L3/L4/L7 DNS-aware policy; Hubble flow logs; higher pod density; **ClusterMesh** | Team learns Cilium CRDs; upgrade lifecycle decoupled from EKS add-ons; kernel ≥5.10 | `ADR-0003 Cilium over aws-vpc-cni` |
| **Cilium Gateway API** ingress; one NLB per `Gateway`, TLS terminated at edge | No extra controller/pods; LB provisioned per Gateway not per Ingress; standards-aligned; Hubble-visible | Team learns Gateway API; CRDs must precede the Cilium chart; not all NGINX annotations port | `ADR-0009 Cilium Gateway API ingress` |
| **EKS public endpoint + parameterised CIDR allow-list**, fail-closed `[]` default, private access always on | Makes the allow-list a first-class tightenable variable instead of an invisible implicit `0.0.0.0/0`; prod ships private-only / narrow corp-CIDR | Non-prod ships a documented `0.0.0.0/0`; tightening must be validated against every CI runner IP | `ADR-0010 EKS public endpoint CIDR allow-list` |
| Cross-cluster: **peered TGW substrate + Cilium ClusterMesh default**, PrivateLink / Lattice / NLB+Route53 / ingress fallback matrix | Non-overlapping routable pod CIDRs (ENI/native) enable zero-proxy-hop pod-to-pod routing; one substrate reused; identity-first fallbacks for overlap/vendor cases | ClusterMesh valid **only** while pod CIDRs stay non-overlapping & routable; cert exchange + apply gate | `ADR-0043 EKS cross-cluster connectivity`, `ADR-0019 Harvest Cilium eBPF capabilities` |
| Multi-region parity as a **per-region stamp** (VPC+TGW+ClusterMesh), active/active with an asymmetric (scale-to-zero, spot-first) secondary; **no cross-region GPU pool**; serving failover is DNS-level, batch is region-pinned | Mirrors the GKE etalon; bounds per-region GPU cost/quota; region drops out of rotation on health-signal loss | Extra per-region TGW/peering cost; cross-region cert-exchange overhead; batch re-queues rather than fails over | `ADR-0044 AWS EKS GPU ML foundation multiregion`, `ADR-0036 GKE ML infra parity multiregion` |
| **Bare-metal DC networking** via Cilium kube-proxy-less + LB-IPAM + BGP control-plane to ToR (no cloud LB) | On-prem has no cloud NLB; BGP advertises service VIPs to the DC fabric; keeps one CNI/policy model across cloud and metal | DC BGP peering to operate (hold-timer 180s), MTU 9000 end-to-end; MetalLB only as documented fallback | `ADR-0051 Bare-metal networking Cilium LB + BGP` |

---

## 4. Implementation blueprint

### 4.1 Directory layout

```
terragrunt/
  root.hcl                       # backend (S3 native lock), provider-generate, ADR-0028 tags
  versions.hcl                   # tool + provider version pins (single source of truth)
  common.hcl                     # region catalog (4-region EU footprint), tag defaults
  _org/account.hcl               # org-wide admin_cidr_allowlist placeholder (10.0.0.0/8)
  network/                       # THE HUB — Network account
    account.hcl                  # tgw_peers, vpn_connections, dns_forwarding_rules, inter_vpc_security
    eu-west-1/                   # ANCHOR region — richest topology
      region.hcl                 # aws_region, region_short, azs[]
      connectivity/terragrunt.stack.hcl   # 8 units: vpc, transit-gateway, ram-share,
                                 #   tgw-route-tables, vpn-connection, route53-resolver,
                                 #   + remote-access-vpn, inter-vpc-security (ADR-0013)
      transit-gateway/terragrunt.hcl      # standalone TGW unit (pins ASN 64512)
      lattice-resource/terragrunt.hcl     # ADR-0023 VPC Lattice resource GW
    {eu-west-2,eu-west-3,eu-central-1}/connectivity/terragrunt.stack.hcl  # 6 units (no VPN/inter-VPC-sec)
    _global/iam/terragrunt.hcl   # cross-account networking roles
  {dev,staging,prod,dr}/<region>/…         # spoke VPCs (attach to hub TGW; attach gated off)
  uk/{primary,standby}/…         # bare-metal Talos DC estate (ADR-0049/0051), dc.hcl hierarchy
  gcp-staging/europe-west9/…     # GCP GKE estate (project.hcl), independent cross-cloud edge
catalog/units/                   # reusable Terragrunt units (thin; config via inputs)
  vpc, transit-gateway, tgw-route-tables, tgw-attachment, tgw-peering, ram-share,
  route53-resolver, vpn-connection, remote-access-vpn, inter-vpc-security, vpc-endpoints,
  vpc-lattice-resource, global-accelerator, nlb-ingress, gpu-inference-tgw-connect,
  clustermesh-connect, clustermesh-sg-rules
terraform/modules/               # the modules the units source
dns-sync/                        # octoDNS: zones/*.yaml, config/octodns-config.yaml, scripts/
dns-monitor/                     # Go: dig-based provider health scorer → Postgres + Prom
failover-controller/             # Go: registrar-nameserver failover state machine
apps/infra/external-dns/         # in-cluster Route53 record automation (GitOps, default off)
```

**Regional asymmetry:** all four EU regions run the same 6-unit connectivity stack; only
`eu-west-1` adds `remote-access-vpn` + `inter-vpc-security` and standalone
`transit-gateway`/`lattice-resource` units. The catalog `transit-gateway` unit does **not**
pin `amazon_side_asn` (module default `64512`); only the standalone eu-west-1 unit pins it.

**Ordering / dependencies (what must exist before what):**

1. `root.hcl` backend bootstrapped (`--backend-bootstrap`) — S3 native locking.
2. Network VPC → TGW → RAM-share → **then** workload spoke attachments (attachments are
   **inert** until `inter-vpc-security` / `tgw-route-tables` add routes).
3. `remote-access-vpn` before `inter-vpc-security` (needs trust sub-pool CIDRs); TGW before both.
4. **Sequencing gate:** keep `enable_vpn_routing = false` until (a) network VPC + attachment
   applied **and** (b) `enable_prod_nacl_backstop` applied — else the standard VPN sub-pool
   transiently reaches prod through the TGW.
5. Cross-region: both regional TGWs exist → `tgw-peering` → routes → ClusterMesh cert
   exchange into Secrets Manager → flip `clustermesh_connect_enabled = true`.
6. DNS: authoritative zones exist at both providers → `dns-monitor` seeded with provider
   rows → `failover-controller` starts in `HEALTHY`.

### 4.2 CIDR allocation scheme (deterministic, overlap-free)

Each `environment × region` pair maps to a unique `/16` so VPCs can peer/attach without
overlap. From `catalog/units/vpc/terragrunt.hcl`:

```hcl
# Second octet block encodes environment; third the region index within the block.
#   dev: 10.0-3 · staging: 10.10-13 · prod: 10.20-23 · dr: 10.30-33
#   network: 10.40-43 · management: 10.50-53 · reserved: 10.54-99 (future accounts)
cidr_map = {
  dev-eu-west-1     = "10.0.0.0/16"    staging-eu-west-1    = "10.10.0.0/16"
  dev-eu-west-2     = "10.1.0.0/16"    staging-eu-central-1 = "10.13.0.0/16"
  prod-eu-west-1    = "10.20.0.0/16"   dr-eu-west-1         = "10.30.0.0/16"
  network-eu-west-1 = "10.40.0.0/16"   management-eu-west-1 = "10.50.0.0/16"
  # …full dev/staging/prod/dr/network/management × eu-west-1/2/3 + eu-central-1 grid
}
vpc_cidr = cidr_map["${environment}-${aws_region}"]

# Subnets: /20 slices of the /16 via cidrsubnet(cidr, 4, index)
private_subnets  = [for i,az in azs : cidrsubnet(vpc_cidr, 4, i)]      # idx 0..N
public_subnets   = [for i,az in azs : cidrsubnet(vpc_cidr, 4, i + 4)]  # idx 4..N+4
database_subnets = [for i,az in azs : cidrsubnet(vpc_cidr, 4, i + 8)]  # idx 8..N+8
```

For a 3-AZ region on `10.20.0.0/16` (prod-eu-west-1): private `10.20.0/20, .16/20, .32/20`;
public `.64/20, .80/20, .96/20`; database `.128/20, .144/20, .160/20`. VPC module:
`terraform-aws-modules/vpc/aws` **v6.6.0**; NAT HA (`single_nat_gateway = false`, but DR/dev
flip to `true`); Flow Logs → CloudWatch, `ALL` traffic, 365-day retention, 60s aggregation.
The GPU-inference cluster's pod CIDR `100.64.0.0/10` (CGNAT) is deliberately outside the
`10/8` VPC plan so it can be BGP-propagated without collision.

### 4.3 TGW hub + route tables (sanitized)

`terraform/modules/transit-gateway/main.tf` — the load-bearing isolation defaults:

```hcl
resource "aws_ec2_transit_gateway" "this" {
  amazon_side_asn                 = var.amazon_side_asn   # {{TGW_ASN}}, default 64512
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "disable"             # <- explicit allow-list
  default_route_table_propagation = "disable"             # <- no implicit leakage
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
}
resource "aws_ec2_transit_gateway_route_table" "this" { for_each = var.route_tables }  # prod|nonprod|shared
resource "aws_ec2_transit_gateway_route" "blackhole_cross_env" { for_each = var.blackhole_cidrs }  # blackhole = true
# RAM share to workload accounts; allow_external_principals = false (stay in-org)
```

Unit inputs (`network/eu-west-1/transit-gateway/terragrunt.hcl`): `amazon_side_asn = 64512`;
`route_tables = { prod = {}, nonprod = {}, shared = {} }`; `ram_principals =
[{{DEV_ACCOUNT_ID}}, {{STAGING_ACCOUNT_ID}}, {{PROD_ACCOUNT_ID}}, {{DR_ACCOUNT_ID}},
{{SECURITY_ACCOUNT_ID}}, {{LOGARCHIVE_ACCOUNT_ID}}, {{SHARED_ACCOUNT_ID}}]`. Route-table
intent: `prod` (Prod VPCs only, propagation off), `nonprod` (dev+staging), `shared` (ECR,
Route 53 PHZs, inspection VPC). Cross-env reachability requires an **explicit per-CIDR
route**; default is none. Module outputs: `transit_gateway_id`, `route_table_ids` (map),
`ram_resource_share_arn`.

### 4.4 Cross-region TGW peering (scaffolded, not yet live)

`terraform/modules/tgw-peering` creates a requester attachment locally and an accepter via
an **aliased provider** (`provider = aws.peer`), then adds `peer_cidrs` into every
`local_route_table_ids` entry. Driven from `network/account.hcl`:

```hcl
enable_tgw_peering = true
tgw_peers = {
  "eu-central-1" = { tgw_id = "", cidrs = ["10.13.0.0/16"] }  # staging-euc1
  "eu-west-1"    = { tgw_id = "", cidrs = ["10.10.0.0/16"] }  # staging-euw1
}
```

**Status:** these locals are set, but the `tgw-peering` unit is wired only into the catalog
*template* stack — no live region connectivity stack consumes it yet. Cross-region routing
is a design-target to be wired per-region (see §7).

### 4.5 Route 53 Resolver (cross-account/on-prem DNS)

`terraform/modules/route53-resolver` places **inbound** (on-prem/VPN → resolve AWS private
zones) and **outbound** (AWS → resolve partner/on-prem domains) endpoints in the Network VPC
private subnets (≥2 AZ). A dedicated SG permits DNS `53/tcp`+`53/udp` from `allowed_cidrs`
(default `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`). **FORWARD** rules map partner
domains to target IPs and are associated to the VPC:

```hcl
forwarding_rules = {                    # from network/account.hcl dns_forwarding_rules
  # partner-internal = { domain = "internal.partner.example",
  #   target_ips = [{ ip = "10.100.0.53" }, { ip = "10.100.1.53" }] }
}
```

The internal shared zone is a **PRIVATE** Route 53 zone (resolvable only inside associated
VPCs); VPN clients resolve it via the network-VPC association + DNS push. The public apex
(`{{DOMAIN}}`) lives outside AWS DNS and is untouched by the private boundary (ADR-0013).

### 4.6 DNS zone hierarchy & dual-provider sync (octoDNS)

Authoritative records for `{{DOMAIN}}` are declared as YAML and reconciled to **both**
providers. `dns-sync/config/octodns-config.yaml`:

```yaml
providers:
  config:     { class: octodns.provider.yaml.YamlProvider, directory: ./zones, default_ttl: 300 }
  cloudflare: { class: octodns_cloudflare.CloudflareProvider, token: env/CLOUDFLARE_TOKEN }
  route53:    { class: octodns_route53.Route53Provider }   # creds via IRSA (AWS_ROLE_ARN)
zones:
  {{DOMAIN}}.:
    sources: [config]
    targets: [cloudflare, route53]        # <- primary + secondary kept in lockstep
```

`dns-sync/zones/{{DOMAIN}}.yaml` (sanitized shape) carries apex `A`, `MX`, SPF `TXT`, `www`,
`api` `CNAME`, and a `_health-check` `TXT` canary (`ttl 60`) that the monitor/failover
components probe:

```yaml
'':          [ {type: A, value: 192.0.2.10, ttl: 300},
               {type: MX, values: [{exchange: mail.{{DOMAIN}}., preference: 10}], ttl: 3600},
               {type: TXT, value: "v=spf1 include:{{MAIL_PROVIDER}} ~all", ttl: 3600} ]
api:         [ {type: CNAME, value: api-lb.{{PRIMARY_REGION}}.elb.amazonaws.com., ttl: 300} ]
_health-check: [ {type: TXT, value: canary-record-for-monitoring, ttl: 60} ]
```

`scripts/validate-sync.sh` `dig +short +norecurse`s each provider's nameservers for `A/TXT/
CNAME`, sorts, and `diff`s them to detect **cross-provider drift**.

### 4.7 DNS health monitor (`dns-monitor`, Go)

A 30-second loop reads provider rows from Postgres (`dns_providers WHERE status != 'failed'`),
`dig`s each nameserver for `_health-check.{{DOMAIN}}` (TXT, `RecursionDesired=false`, 5s
timeout), records each check into `health_check_results` (fields: `provider_id,
nameserver_address, query_domain, response_time_ms, success, error_message, check_location,
check_timestamp`), exports Prometheus metrics (`dns_query_duration_seconds`,
`dns_query_success_total`, `dns_query_failure_total`, `dns_provider_health_score`), and
computes a **0–100 health score**:

```
score = successRate*60 + latencyScore*30 + consistencyScore*10
latencyScore = 1.0 if avg < 50ms;  → 0.0 linearly by 1000ms
```

### 4.8 DNS failover controller (`failover-controller`, Go)

A separate 30-second state machine reads the monitor's health scores (5-minute lookback) and,
on sustained primary-provider degradation, **swaps the registrar's nameservers** to the
secondary provider — DNS-provider-level failover, not record-level. States/thresholds
(`statemachine.go`):

```
HEALTHY ─(primary<0.5)→ DEGRADED ─(3 consecutive<0.5)→ FAILING_OVER
   ▲                        │(recovers ≥0.5)                 │(update NS + verify propagation)
   │                        ▼                                ▼
   └──(failback, NS→primary)── RECOVERING ←(primary>0.7)── FAILED_OVER
        cooldown 10m stable        │(primary<0.5 again → abort back to FAILED_OVER)
```

`DegradeThreshold=0.5`, `ConsecutiveDegradedChecksRequired=3`, `RecoveryThreshold=0.7`,
`HealthScoreWindow=5m`. Safety guardrails (`safety.go`, `DefaultSafetyParams`) gate every
transition: `MinTimeInState=5m`, `FailoverCooldown=1h`, `MaxDailyFailovers=1`,
`RecoveryCooldown=10m`, `RequireManualAuth=false` (**set true in prod initially**). A
`validTransitions` map rejects any topologically-invalid jump. State persists to `STATE_FILE`
(default `/var/lib/failover-controller/state.json`, fields: `current_state,
last_transition_time` (RFC3339)`, daily_failover_count, primary_provider_id,
secondary_provider_id`); HTTP `:8080` serves `/metrics /healthz /readyz /state`. The
registrar is an **interface** (`RegistrarClient`) with a `Mock` default — real
Namecheap/GoDaddy/Cloudflare-Registrar impls are selected by `REGISTRAR_TYPE`;
`VerifyPropagation` should query public resolvers (`8.8.8.8`, `1.1.1.1`) and require
agreement. This is the same controller ADR-0036/0044 reuse for cross-region **serving**
failover (a region drops out of DNS rotation on health-signal loss; batch/training is
region-pinned and re-queued, never failed over).

### 4.9 In-cluster record automation (`external-dns`)

GitOps-managed, **disabled by default**. Provider `aws` (Route 53), `policy: upsert-only`
(never deletes), `registry: txt` with `txtOwnerId`/`txtPrefix` for ownership, `sources:
[service, ingress]`, `region: ""` so each cluster manages **its own** zone (multi-region
safe). IRSA/Pod-Identity grants `route53:ChangeResourceRecordSets` + `List*`. `domainFilters`
scope which zones it may touch; `evaluateTargetHealth: true` on ALIAS records.

### 4.10 VPC endpoints, VPN, Lattice, ingress, Global Accelerator

- **VPC endpoints** (`catalog/units/vpc-endpoints` → `terraform-aws-modules/vpc/aws//modules/
  vpc-endpoints` v6.6.0): **2 gateway** (S3, DynamoDB) + **13 interface** endpoints — `ssm`,
  `ssmmessages`, `ec2messages`, `ec2`, `ecr.api`, `ecr.dkr`, `sts`, `sns`, `sqs`, `logs`,
  `monitoring`, `secretsmanager`, `kms` (`private_dns_enabled = true`). Removes NAT
  data-processing cost for AWS-API calls and is required for SSM Session Manager + private
  ECR pulls. Requires a pre-wired SG allowing `443` from the VPC CIDR (unit passes `[]`).
- **remote-access-VPN** (`remote-access-vpn`, ADR-0013; deps `../vpc`, `../kms`): AL2023 host
  in the Network account behind a public NLB (`TCP_UDP`, `target_type=ip`,
  `preserve_client_ip=false`); host SG never sees `0.0.0.0/0` (only the NLB); SSM not SSH;
  ops sub-pool `10.100.0.0/24` (→prod/shared/legacy), standard sub-pool `10.100.1.0/24`
  (→shared only), client pool `10.100.0.0/20`; secrets under `org/network/remote-access-vpn`;
  SNS `network-alerts` + EC2 auto-recovery + `NetworkOut` anomaly alarm.
- **Site-to-site VPN** (`vpn-connection`; dep `../transit-gateway`): partner/on-prem tunnels
  terminating on the TGW; `vpn_connections` from `account.hcl` (empty by default; example
  `bgp_asn = 65001`).
- **VPC Lattice resource** (`vpc-lattice-resource`, ADR-0023): Resource Gateway in the owning
  VPC private subnets + `type=ARN` Resource Configuration (RDS ARN, port `5432`) + Service
  Network + RAM org-share + IAM auth policy scoped to `{{ORG_ID}}` (`aws:PrincipalOrgID`).
- **nlb-ingress** (`nlb-ingress`; deps `../vpc`, `../eks`): public NLB, TLS on `443` via ACM,
  `ssl_policy = ELBSecurityPolicy-TLS13-1-2-2021-06`, TCP health check `/healthz`,
  `deregistration_delay = 30`; the regional endpoint that Global Accelerator targets.
- **Global Accelerator** (`global-accelerator`, multi-region active/active; place under
  `_global/`): anycast listeners `443`/`80` TCP, `client_affinity=SOURCE_IP`, one endpoint
  group per regional NLB with health checks + `traffic_dial_percentage`; flow logs → S3.
  `enabled`/endpoint-groups filled per-estate (`enable_global_accelerator`).

### 4.11 Multi-geo / multi-cloud edges

- **AWS multi-region:** the region-0 stamp (VPC + TGW + optional ClusterMesh) repeats per
  region; canonical footprint is the 4-region EU set `eu-west-1/2/3`, `eu-central-1`
  (`common.hcl region_short_codes`). `dr/` mirrors the prod network topology across all four
  regions on the `10.30–33` block, but its **TGW attachment is gated off**
  (`enable_tgw_attachment = false`, `transit_gateway_id = ""`) until the network-account TGW
  exists; DR also runs `single_nat_gateway = true`, `eks_public_access = false`,
  `rds_multi_az = true`. Cross-region east-west rides peered TGW + ClusterMesh:
  `clustermesh-connect` reads peer TLS from **AWS Secrets Manager** per region (gated by
  `clustermesh_connect_enabled`, default false); `clustermesh-sg-rules` opens node-SG ingress
  for ports `2379`/`4240`/`4244`/`51871` (gated by `enable_clustermesh`, default false).
- **Bare-metal DC (`terragrunt/uk/`, ADR-0049/0051):** a production Talos estate with
  `primary` (active) + `standby` (hot-standby) DCs, hierarchy via `dc.hcl`/`env.hcl` (not
  account/region). No cloud LB — Cilium **kube-proxy-less + LB-IPAM + BGP** advertises service
  VIPs (from a `CiliumLoadBalancerIPPool` carved from the DC service-VIP CIDR) to ToR switches
  via `CiliumBGPClusterConfig`. Load-bearing config: BGP **hold timer 180s**, **MTU 9000**
  end-to-end (100 GbE), `max-prefix` sized on the ToR; MetalLB is a documented fallback only.
  Module contract (`baremetal-cilium-lb`): `bgp_peers = [{ peer_address, peer_asn, local_asn,
  hold_time_seconds = 180 }]`, `lb_ipam_pools = [{ name, cidr }]`, `mtu` default 9000.
- **GCP (`terragrunt/gcp-staging/europe-west9`, Paris):** a GKE GPU estate — custom-mode VPC
  `subnet_cidr = 10.200.0.0/16`, Cloud Router + Cloud NAT, private Google API access,
  secondary IP ranges for GKE pods/services, Cloud Armor edge (ADR-0042, default off). This is
  an **independent** estate: there is **no Interconnect/Cloud VPN to AWS** — GCP↔AWS
  integration is by independent estates + DNS failover only (ADR-0036 rejects cross-cloud GPU
  pooling).

---

## 5. Parameterization table

| Placeholder / knob | Meaning | Default in this estate | Resize guidance |
|---|---|---|---|
| `{{DOMAIN}}` | Root authoritative DNS zone | `example.com` (source) | Client apex; drives octoDNS zone, `_health-check`, external-dns `domainFilters` |
| `{{PRIMARY_DNS_PROVIDER}}` / `{{SECONDARY_DNS_PROVIDER}}` *(spec-local)* | The two authoritative providers kept in lockstep | `cloudflare` / `route53` | Any octoDNS-supported pair; failover swaps NS between them |
| `{{MAIL_PROVIDER}}` *(spec-local)* | SPF include host | `_spf.google.com` (source) | Client mail provider's SPF include |
| `{{TGW_ASN}}` *(spec-local)* | Amazon-side TGW BGP ASN | `64512` | Private ASN 64512–65534; must differ from peer TGW / on-prem ASN |
| `{{NETWORK_ACCOUNT_ID}}` | Hub (TGW owner) account | `555555555555` | Owns TGW, resolver, VPN, Lattice service network |
| `{{DEV/STAGING/PROD/DR/SECURITY/LOGARCHIVE/SHARED_ACCOUNT_ID}}` | TGW-share RAM principals | `1…`/`2…`/`3…`/`4…`/`7…`/`8…`/`9…` | Match SPEC-01 account map; add new spokes to `ram_principals` |
| `{{MGMT_ACCOUNT_ID}}` | Org management account | `000000000000` | `organization_arn` populated after org creation |
| `{{ORG_ID}}` *(spec-local)* | AWS Organization ID | `o-placeholderorg` | Lattice auth policy `aws:PrincipalOrgID` |
| `{{STATE_BUCKET}}` | TF state bucket | `{{ORG}}-terraform-state-<account_id>` (eu-central-1, S3 native lock) | See SPEC-01; sanitized from source's company-named bucket |
| `{{PRIMARY_REGION}}` / `{{DR_REGION}}` | Anchor / DR regions (`{{DR_REGION}}` ∈ `{{SECONDARY_REGIONS}}`) | `eu-west-1` / DR on `10.30–33` | Reset to client anchor; single-region TGW is v1-acceptable |
| VPC `/16` per env×region | `cidr_map` scheme | `10.<env-block>.<region-idx>.0/16` | Keep 2nd octet = env, 3rd = region; reserve `10.54–99`; never overlap legacy/on-prem |
| Subnet size | `cidrsubnet(cidr,4,i)` | `/20` × AZ, 3 tiers | Shrink prefix delta for more/smaller subnets; keep private/public/database offsets 0/4/8 |
| GPU-inference pod CIDR | TGW-Connect BGP propagation | `100.64.0.0/10` (CGNAT) | Keep outside the `10/8` VPC plan to avoid collision |
| GCP `subnet_cidr` | GKE estate VPC | `10.200.0.0/16` | Keep clear of the AWS `10/8` plan if the estates are ever joined |
| `single_nat_gateway` | NAT HA | `false` (1 NAT/AZ); `true` in DR/dev | `true` to cut cost; keep HA in prod |
| VPN sub-pools | Trust segmentation | ops `10.100.0.0/24`, std `10.100.1.0/24`, pool `10.100.0.0/20` | Size to remote-user count; only ops→prod |
| Resolver `allowed_cidrs` | Who may query resolver | RFC1918 supernets | Tighten to actual spoke/on-prem ranges |
| TGW route tables | Segmentation | `prod`, `nonprod`, `shared` | Add `inspection` when the inspection VPC lands |
| ClusterMesh SG ports | East-west | `2379`, `4240`, `4244`, `51871` | Fixed by Cilium; open only between peer VPC CIDRs |
| BGP hold timer / MTU (bare metal) | DC fabric | `180s` / `9000` | Match ToR config; 9000 requires end-to-end jumbo frames |
| Failover thresholds | State-machine tuning | degrade `0.5`, 3 checks, recover `0.7`, window `5m` | Loosen for flaky links; tighten for stricter SLAs |
| Failover safety | Anti-flap guards | `MinTimeInState 5m`, `FailoverCooldown 1h`, `MaxDailyFailovers 1`, `RecoveryCooldown 10m`, `RequireManualAuth false` | Raise `MaxDailyFailovers`/lower cooldown only with confidence; **set `RequireManualAuth=true` for prod** |
| Tool/provider pins (`versions.hcl`) | Reproducible builds | Terraform `1.14.8`, Terragrunt `1.0.8`, AWS provider `~> 6.0`, VPC module `6.6.0` | Bump via ADR (major) / green-CI PR (minor); keep single source of truth |

---

## 6. Best practices distilled

1. **Make reachability an allow-list, not a default.** Disable TGW default route-table
   association *and* propagation; every attachment associates to an explicit custom route
   table. *Why:* "can dev reach prod?" is answered by reading one route table, not auditing a
   mesh.
2. **Add a blackhole backstop even where no route exists.** Blackhole prod↔nonprod CIDRs.
   *Why:* a mistaken future route is silently dropped instead of quietly bridging environments.
3. **Allocate CIDRs deterministically from a single map**, encoding environment and region in
   fixed octets with a reserved growth band. *Why:* guarantees the non-overlap that peering,
   ClusterMesh routable pod IPs, and legacy-estate joins all require — without a spreadsheet.
4. **Keep pod CIDRs non-overlapping and routable** (Cilium ENI/native). *Why:* it's the single
   biggest enabler of zero-proxy-hop ClusterMesh; overlap permanently forecloses routable
   methods and forces proxied fallbacks.
5. **Two authoritative DNS providers, one declarative source.** Push identical zone YAML to
   both via octoDNS and diff for drift. *Why:* a single provider outage otherwise takes down
   the platform's entire name resolution.
6. **Fail over DNS at the nameserver, gated by health scoring — not by a human paging at 3am.**
   A scored monitor + a guarded state machine with cooldowns and a daily cap removes toil while
   preventing flap. *Why:* automated failover is only safe with anti-oscillation guards and a
   manual-auth switch for prod.
7. **Separate the health signal from the actor.** `dns-monitor` scores; `failover-controller`
   acts. *Why:* the actor stays simple/testable; the scorer can evolve without touching
   failover logic.
8. **Terminate the VPN's blast radius with trust sub-pools**, and make a negative test
   (non-ops client must NOT reach prod) an acceptance requirement. *Why:* a flat VPN pool + any
   legacy peering silently recreates a transitive path to prod.
9. **Two independent enforcement layers must agree.** DB SGs accept only the SG/CIDR the TGW
   route table also permits; NACLs backstop at the subnet. *Why:* a single misedited layer
   doesn't open a path.
10. **Prefer identity-scoped resource access for single-region TCP resources** (VPC Lattice +
    IAM auth) over an NLB+TGW path. *Why:* the unit of control becomes the caller's identity;
    drops standing NLB/TGW plumbing for that flow.
11. **Keep AWS-API traffic inside the VPC** with gateway + interface endpoints for the core
    services. *Why:* removes NAT data-processing cost and egress exposure for control-plane
    calls, and is a hard prerequisite for SSM/ECR on private subnets.
12. **Externalise the EKS public CIDR allow-list; never rely on the implicit `0.0.0.0/0`.**
    Fail-closed `[]`; private access always on; prod narrow or private-only. *Why:* an implicit
    wide-open endpoint is invisible in review and can't be tightened without a module change.
13. **Gate every dangerous flip behind an explicit boolean with a documented sequence**
    (`enable_vpn_routing`, `enable_prod_nacl_backstop`, `clustermesh_connect_enabled`,
    `enable_tgw_attachment` — all default false). *Why:* ordering mistakes transiently breach
    isolation.
14. **One CNI/policy model across cloud and metal.** Cilium everywhere; bare-metal uses
    LB-IPAM+BGP instead of a cloud LB. *Why:* one `CiliumNetworkPolicy` mental model and Hubble
    observability spanning every estate.
15. **Pin tool/provider versions in one file and bump by policy.** *Why:* reproducible plans
    across CI/dev/prod; majors get an ADR + multi-env soak.

---

## 7. Known pitfalls

1. **The sequencing gate is real.** Flipping `enable_vpn_routing=true` before the network VPC/
   attachment **and** the prod NACL backstop are applied lets the standard VPN sub-pool reach
   prod through the TGW. Keep it `false` until both hold (ADR-0013).
2. **Implicit `0.0.0.0/0`.** Leaving `cluster_endpoint_public_access_cidrs` unset means AWS
   applies `0.0.0.0/0`. Non-prod ships an *explicit, documented* `0.0.0.0/0`; do **not** let
   prod inherit it (ADR-0010).
3. **As-built divergence:** **TGW is a per-region hub — cross-region needs a second TGW +
   peering, and it is not wired live yet.** `enable_tgw_peering=true` + `tgw_peers` are set in `network/account.hcl`, but
   the `tgw-peering` unit is only in the catalog *template* stack. Wire it per-region and add
   the peer CIDRs to **every** local route table, or cross-region east-west silently fails.
4. **VPC Lattice resource connectivity is TCP-only and single-region-only.** A non-TCP or
   cross-region resource flow must stay on the ADR-0013 TGW/NLB path; a permissive
   `vpc-lattice:*` auth policy over-shares — scope to specific principals (ADR-0023).
5. **ClusterMesh holds only while pod CIDRs stay non-overlapping & routable.** A future
   overlapping-CIDR cluster pair takes routable methods off the table (fall back to
   PrivateLink/Lattice/ingress). Verify CIDR planning *before* promising ClusterMesh.
6. **The registrar client ships as a Mock; `VerifyPropagation` always returns true.** In
   production, wire a real `RegistrarClient` and a real propagation check that polls public
   resolvers — otherwise failover reports success without actually moving traffic.
7. **`MaxDailyFailovers=1` + `RequireManualAuth=false`.** Defaults allow exactly one automatic
   failover/day with no human in the loop. For prod, start with `RequireManualAuth=true`; a
   persistent outage past the daily cap will **not** auto-fail again (intentional — page on it).
8. **Failover state is a local JSON file.** Without a PersistentVolume for `STATE_FILE`, a
   rescheduled pod reloads default (`HEALTHY`) state and loses failover counters/cooldowns.
9. **octoDNS drift is detected, not auto-healed.** `validate-sync.sh` prints drift and has a
   `TODO` to emit a metric/DB row — wire it to alerting; a silent one-provider divergence
   undermines the dual-provider premise.
10. **As-built divergence:** **dns-monitor/failover domain and probe region are hard-coded to
    the sample.** `checkProvider` probes `_health-check.example.com`; `CheckLocation` is hard-coded
    `us-east-1`. Parameterise both to `{{DOMAIN}}` and the real probe region before use.
11. **Legacy-side return routes + prod NACL backstop are cross-account, out-of-repo
    design-targets** (owned by legacy-ops / prod-account VPC unit). If they aren't added,
    ops-pool reachability is one-way.
12. **Company-identifying leakage in state config.** The source state bucket is named after the
    company; always parameterise to `{{STATE_BUCKET}}` and scrub account IDs/ARNs before sharing.
13. **TGW attachment cost creep.** ~$36/mo per attachment plus inter-VPC data processing — an
    unbounded spoke count is a FinOps issue; consolidate where segmentation allows.

---

## 8. Acceptance checklist

A rebuild passes when all hold:

- [ ] `terragrunt run --all plan` is clean from an empty Network account (backend bootstrapped
      with `--backend-bootstrap`, S3 native locking).
- [ ] The TGW has `default_route_table_association = disable` **and**
      `default_route_table_propagation = disable`; route tables `prod`, `nonprod`, `shared`
      exist; the RAM share targets exactly the intended workload accounts.
- [ ] No route table grants a dev/standard source a path into prod; prod↔nonprod CIDRs are
      blackholed.
- [ ] Every workload VPC's `/16` comes from `cidr_map` with **no overlaps** across
      environments, regions, DR, GCP (`10.200/16`), the GPU-inference pod CIDR
      (`100.64.0.0/10`), and legacy/on-prem ranges; subnets are the expected `/20` slices.
- [ ] VPC Flow Logs are enabled (365-day retention); the 2 gateway + 13 interface endpoints exist.
- [ ] Route 53 Resolver inbound + outbound endpoints are up in ≥2 AZ; SG allows only DNS `53`
      from `allowed_cidrs`; the internal shared zone is PRIVATE.
- [ ] octoDNS applies the zone to **both** providers; `validate-sync.sh` reports **zero drift**;
      the `_health-check` TXT canary resolves at both.
- [ ] `dns-monitor` exports `dns_provider_health_score` for every provider and is scraped by
      Prometheus.
- [ ] `failover-controller` starts in `HEALTHY`, persists state to a **PV**, exposes `/state`,
      and (in a drill) transitions `HEALTHY→DEGRADED→FAILING_OVER→FAILED_OVER` then fails back
      after the recovery cooldown; `RequireManualAuth=true` in prod.
- [ ] A **negative VPN test** confirms a standard (non-ops) client cannot reach prod;
      `enable_vpn_routing` was flipped **only after** the VPC/attachment + NACL backstop.
- [ ] Cross-region: the second TGW + peering exists, peer CIDRs are in every local route table,
      and (if used) ClusterMesh certs are exchanged into Secrets Manager before
      `clustermesh_connect_enabled=true`; SG ports `2379/4240/4244/51871` are open only between
      peer VPC CIDRs.
- [ ] EKS endpoints set `cluster_endpoint_public_access_cidrs` explicitly (never implicit
      `0.0.0.0/0`); prod is private-only or a narrow corp/VPN CIDR.
- [ ] `external-dns` (if enabled) is `upsert-only` with `txt` registry ownership and per-cluster
      zone scoping.
- [ ] Bare-metal DC: Cilium BGP sessions to the ToR are up (hold-timer 180s), service VIPs come
      from a `CiliumLoadBalancerIPPool`, and MTU 9000 is end-to-end.

---

## 9. Dependencies on other specs

- **SPEC-00 — Overview:** global placeholder registry (`{{DOMAIN}}`, `{{ORG}}`, account IDs,
  `{{PRIMARY_REGION}}`/`{{DR_REGION}}`, `{{STATE_BUCKET}}`), the region footprint, and the
  ADR-0028 tagging taxonomy consumed by every unit here.
- **SPEC-01 — Foundation: IaC, Account Topology & State:** the OU split (ADR-0001) and the
  account-ID map that becomes the TGW `ram_principals`; the Terragrunt `root.hcl`/`versions.hcl`
  /`common.hcl` + `catalog/units` model this spec's units plug into; remote state + version
  pins; `organization_arn`/`{{ORG_ID}}` used by the Lattice auth policy. (SPEC-01 explicitly
  defers VPC/CIDR/TGW/ClusterMesh/inter-VPC to this spec.)
- **SPEC-03 — Compute Clusters:** Cilium install & CRDs, `CiliumNetworkPolicy` authoring,
  Gateway API `HTTPRoute`s, NLB-per-Gateway ingress, ClusterMesh operational detail, and the
  bare-metal Talos cluster — this spec sets the VPC/CIDR/east-west substrate they run on
  (ADR-0003/0009/0019/0043/0051).
- **SPEC-05 — Security:** GuardDuty on the Network account, VPC Flow Logs
  destination/KMS, the (future) inspection VPC + AWS Network Firewall, and SCP/NACL prod
  backstops referenced by ADR-0013.
- **SPEC — Observability:** Prometheus scrape of `dns-monitor`/`failover-controller` metrics and
  Hubble flow logs; Grafana surfaces exposed via the Gateway API.
- **SPEC — Edge / Inference Serving:** Global Accelerator + WAF/CloudFront fronting public
  inference endpoints (ADR-0042/0047) that consume the regional NLBs defined here.
```
