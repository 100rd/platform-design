# SPEC-08 — Resilience, Disaster Recovery & Stateful Services

> Portable reverse-engineering of this platform's resilience estate. A senior platform team
> can rebuild the same failover, DR, and data-durability design for a new client from this
> document alone. Follows `specs/CONVENTIONS.md`. All identifiers are placeholders (see §5).

---

## 1. Scope & non-goals

This spec covers everything the platform does to **survive failure and never lose data**:
(a) the in-repo **`failover-controller`** — a Go control loop that fails a domain's DNS between
providers at the registrar; (b) the **DR account** design (a pre-provisioned warm-standby AWS
account for production); (c) **stateful services** — RDS PostgreSQL HA, Kubernetes persistent
storage, and schema-migration handling; (d) **object/artifact storage** durability — the MLflow
artifact store, the centralized **log-archive** immutability design, and Terraform-state DR;
(e) **cross-region / cross-cloud federation** — the two-cluster active/active-standby topology
(AWS EKS, Azure AKS, GKE) and the AWS Global Accelerator active-active transaction plane; and
(f) the **failure-mode matrix**, **DR runbook shape**, **data-classification → storage mapping**,
and the **RTO/RPO tiers** a client must decide (§5.1, §6.x tables).

**Non-goals.** DNS record synchronisation and provider health *measurement* mechanics belong to
**SPEC-02** (`dns-monitor` / `dns-sync`) — this spec consumes their health scores and references
their zone-of-truth. Network fabric (Transit Gateway, Cilium, VPC CIDRs) is also **SPEC-02**;
IAM/org guardrails are **SPEC-05**. GPU-fabric and ML-serving internals are **SPEC-10**;
here they appear only as *stateful-service* and *federation* consumers.

---

## 2. Architecture

The estate has **three independent resilience layers**, each with its own detector, actuator,
and blast radius. They are deliberately decoupled: a failure in one does not disable the others.

```
                          RESILIENCE LAYER MAP

  L1  DNS-PROVIDER FAILOVER (registrar nameserver swap)   ── this spec, core
  ┌───────────────────────────────────────────────────────────────────────┐
  │  dns-monitor (SPEC-02)          failover-controller (Go)                │
  │  probes NS via DNS TXT   ──►  Postgres  ──►  5-state machine, 30s tick  │
  │  score=0.6·succ+0.3·lat+0.1·cons   health_check_results                 │
  │                                          │                             │
  │                                          ▼  RegistrarClient            │
  │                              {{REGISTRAR}} API: swap NS records         │
  │  primary ({{PRIMARY_DNS_PROVIDER}}) ⇄ secondary ({{SECONDARY_DNS_PROVIDER}})           │
  └───────────────────────────────────────────────────────────────────────┘

  L2  MULTI-REGION APP FAILOVER (anycast, no DNS change)  ── transaction plane
  ┌───────────────────────────────────────────────────────────────────────┐
  │        AWS Global Accelerator (anycast, TCP/443 health, ~30s)          │
  │              │ traffic_dial=100/100 (true active-active)               │
  │        ┌─────┴─────┐                                                    │
  │     NLB euw1     NLB euc1                                               │
  │     EKS euw1  ⇄  EKS euc1     Cilium ClusterMesh (WireGuard, east-west) │
  └───────────────────────────────────────────────────────────────────────┘

  L3  DR ACCOUNT / REGION (warm standby, IaC re-provision)  ── prod DR
  ┌───────────────────────────────────────────────────────────────────────┐
  │  dr account ({{DR_ACCOUNT_ID}}) — full platform stack as Terragrunt,   │
  │  scaled down (no GPU), applied/scaled-up on invocation.                │
  │  Data restored from: RDS automated backups · Velero aws-dr bucket ·    │
  │  state-backend-dr S3 CRR ({{PRIMARY_REGION}}→{{DR_REGION}}).           │
  └───────────────────────────────────────────────────────────────────────┘
```

### 2.1 L1 — the `failover-controller` (fully reverse-engineered)

A single Go binary (`failover-controller/`, module `failover-controller`, `go 1.23`). It does
**not** measure health itself; it reads scores that `dns-monitor` (SPEC-02) writes to a shared
PostgreSQL database, decides whether to fail over, and actuates by rewriting the domain's
**nameserver records at the registrar**. This is *provider-level* failover (swap the whole DNS
provider), distinct from record-level DNS.

**Control loop** (`main.go`): a 30-second `time.Ticker`; one immediate evaluation on startup;
graceful shutdown on SIGINT/SIGTERM. An HTTP server on `:8080` exposes `/metrics` (Prometheus),
`/healthz` (liveness), `/readyz` (loads persisted state), and `/state` (current JSON state).

**State machine** (`statemachine.go`) — five states (consolidated from an original eight; the
removed MONITORING/PREPARING/RESTORING added ceremony without distinct behaviour):

```
  HEALTHY ──score<0.5──► DEGRADED ──3 consecutive degraded──► FAILING_OVER
     ▲                      │                                      │
     │                 score≥0.5                              swap NS ok
     │                      ▼                                      ▼
     └──cooldown 10m──── RECOVERING ◄──score>0.7──── FAILED_OVER (serve on secondary)
        failback NS          │  (abort back to FAILED_OVER if score<0.5 during cooldown)
```

| State | Handler behaviour |
|---|---|
| `HEALTHY` | Query provider scores; if primary `< DegradeThreshold (0.5)` → set `DegradedCheckCount=1`, go `DEGRADED`. |
| `DEGRADED` | If primary recovers (`≥0.5`) → reset, back to `HEALTHY`. Else increment counter; at `ConsecutiveDegradedChecksRequired (3)` → `FAILING_OVER`. |
| `FAILING_OVER` | Read current NS (audit), resolve secondary NS, `UpdateNameservers`, `VerifyPropagation`; record `LastFailoverTime`, `DailyFailoverCount++`; → `FAILED_OVER`. On any error, abort → `DEGRADED` (not a tight retry loop). |
| `FAILED_OVER` | Serve on secondary; watch primary; when primary `> RecoveryThreshold (0.7)` → set `RecoveryStartTime`, go `RECOVERING`. |
| `RECOVERING` | Primary must stay healthy for `RecoveryCooldown (10m)`; if it degrades again → abort to `FAILED_OVER`; after cooldown → failback NS to primary → `HEALTHY`. |

**Thresholds** (`statemachine.go`): `DegradeThreshold=0.5`, `ConsecutiveDegradedChecksRequired=3`,
`RecoveryThreshold=0.7`, `HealthScoreWindow=5m`.

**Safety guard-rails** (`safety.go`, `DefaultSafetyParams`) — every transition passes
`ValidateTransition` before it is applied:

```go
MinTimeInState    = 5 * time.Minute   // anti-flap: min dwell in any state
FailoverCooldown  = 1 * time.Hour     // min gap between failovers
MaxDailyFailovers = 1                 // hard cap per calendar day (day-of-year)
RequireManualAuth = false             // set TRUE in prod initially (human-gates FAILING_OVER)
RecoveryCooldown  = 10 * time.Minute  // primary must be stable this long before failback
```

`ValidateTransition` enforces, in order: (1) the transition is in the `validTransitions`
adjacency map (anything else rejected); (2) `MinTimeInState` elapsed; (3) for `→ FAILING_OVER`,
`FailoverCooldown` elapsed **and** `DailyFailoverCount < MaxDailyFailovers`; (4) if
`RequireManualAuth`, block `→ FAILING_OVER` entirely (out-of-band human action required).

**Health scoring** (`healthstore.go`, `PostgresHealthStore`) — the controller re-implements the
*same* formula `dns-monitor` uses, over `health_check_results` in the shared DB:

```
score = successRate·0.6 + latencyScore·0.3 + consistency·0.1     (normalized 0.0–1.0)
latencyScore = 1.0 if avg<50ms ; 0.0 if avg≥1000ms ; linear 1-(avg-50)/950 between
```
Providers with `status='failed'` are excluded. `consistency` is a `1.0` placeholder in both
codebases (a real build measures variance).

**State persistence** (`persistence.go`, `StateStore`) — `ControllerState` is JSON on a
host/PVC path (`STATE_FILE`, default `/var/lib/failover-controller/state.json`). Writes are
**atomic** (temp file + `os.Rename`). `DailyFailoverCount` resets when the day-of-year rolls
over. A missing or corrupt file yields a default `HEALTHY` state rather than a crash. Fields:
`current_state`, `primary_provider_id`, `secondary_provider_id`, `domain`, `last_transition_time`
(RFC3339), `last_failover_time`, `daily_failover_count`, `degraded_check_count`,
`recovery_start_time`, `updated_at`.

**Registrar abstraction** (`registrar.go`) — `RegistrarClient` interface: `GetNameservers`,
`UpdateNameservers`, `VerifyPropagation` (queries public resolvers, e.g. `8.8.8.8`/`1.1.1.1`, and
returns true only when all agree). Ships with `MockRegistrarClient` (default, logs only); a real
build switches on `REGISTRAR_TYPE` (`namecheap`/`godaddy`/…) in `NewRegistrarClient()`.

**Deployment** (`Dockerfile`): multi-stage `golang:1.26-alpine` → `alpine:3.24`, `CGO_ENABLED=0`,
runs as `nonroot` (uid 65532), exposes `:8080`, state dir owned by the non-root user. Runtime env:
`DATABASE_URL` (required — fatal if unset), `STATE_FILE`, `PRIMARY_PROVIDER_ID`,
`SECONDARY_PROVIDER_ID`, `FAILOVER_DOMAIN`. Dependencies: `lib/pq`, `prometheus/client_golang`;
DB pool capped small (`SetMaxOpenConns(5)`, one query per tick).

### 2.2 L1 data model (`database/migrations/V1__initial_schema.sql`, Flyway)

Shared PostgreSQL between `dns-monitor` (writer) and `failover-controller` (reader). Five tables,
UUID PKs, JSONB payloads, `TIMESTAMP WITH TIME ZONE`:

| Table | Role |
|---|---|
| `dns_providers` | provider registry: `name`, `type IN (active,standby)`, `health_check_endpoints` (JSONB), `status IN (healthy,degraded,failed)`. |
| `dns_zones` | domain → registrar + `current_ns_records` / `desired_ns_records` (JSONB), `sync_status`. |
| `health_check_results` | per-probe rows: `provider_id`, `check_timestamp`, `response_time_ms`, `success`, `check_location`. Indexed `(provider_id, check_timestamp DESC)`. |
| `failover_events` | audit: `event_type`, `old/new_ns_records`, `initiated_by` (`auto`/`manual:user`). |
| `state_machine_history` | `previous_state`→`current_state`, `transition_reason`. Indexed `(domain_name, timestamp DESC)`. |

### 2.3 L2 — multi-region active-active (transaction plane)

The staging/prod transaction estate runs **true active-active** across `{{PRIMARY_REGION}}`
(euw1) and a second region (euc1) with **no DNS involvement in failover**:

- **AWS Global Accelerator** (anycast IPs, geo-routing). Both regions `traffic_dial_percentage=100`.
  Health checks: **TCP/443, 10s interval, 3-consecutive threshold ⇒ ~30s detect and ~30s
  recover**, `client_affinity=SOURCE_IP`. GA reroutes at the **network layer** — clients need no
  DNS update. GA is TCP-only: it does **not** fail over on app-level 5xx, partial pod
  degradation, ClusterMesh disconnect, or latency-without-loss (those use manual traffic-dial failover).
- **Cilium ClusterMesh** (WireGuard-encrypted) for east-west pod-to-pod service discovery. Global
  services carry `service.cilium.io/global:"true"`; affinity modes `local` (default; remote
  failover only when all local endpoints unhealthy), `remote`, `none`.
- **ApplicationSet matrix generator** (teams × clusters) with `RollingSync` — deploys euw1 first,
  then euc1 (a natural canary; a failed euw1 sync never reaches euc1).

### 2.4 L2 — GPU-ML two-cluster federation (uniform across clouds)

The GPU-ML platforms mirror one federation shape on all three clouds (AWS two-EKS, Azure two-AKS,
GKE two-region) — see `docs/architecture/{aws,azure}/*-ml-stack.excalidraw`:

- **Exactly two clusters**: Region A **active**, Region B **active / standby**, each a
  *self-contained copy* of the per-region stack. **Non-overlapping pod CIDRs 10.10.0.0/16 (A) vs
  10.20.0.0/16 (B)** — a hard prerequisite for ClusterMesh routability.
- **North-south failover = anycast + health-probe**: AWS Route 53 + Global Accelerator; Azure
  Front Door; GCP DNS. **The same in-repo `failover-controller` (Route 53 DNS failover) is the
  reused serving-failover actuator** (ADR-0044 D5, ADR-0036).
- **East-west = Cilium ClusterMesh** over cross-region **Transit Gateway peering** (AWS) / Global
  VNet peering + **Azure Kubernetes Fleet Manager** L4 (Azure).
- **Serving fails over; batch/training does NOT.** Gang-scheduled GPU jobs are region-pinned and
  **re-queued**, never migrated. The secondary region is deliberately **asymmetric**: scale-to-zero
  GPU node pools, spot-first, sized only for *failover-serving headroom* — not a hot training
  mirror. A **cold-standby (IaC, zero running GPU)** model is left open as a cost-driven revisit.
- **Cross-region data replication is thin**: only container-image geo-replication (ECR/ACR
  cross-region replica) is defined; artifact/dataset stores are per-region with no built-in sync.
  (Bare-metal ADR-0052 is the only estate naming replication tech: CloudNativePG streaming + MinIO
  site-replication + Ceph 3-replica.)

### 2.5 L3 — DR account (warm standby for production)

`terragrunt/dr/` defines a full, **independent AWS account** (`dr`, OU `Prod`, purpose "Disaster
recovery for prod") whose region folders (`eu-west-1/2/3`, `eu-central-1`, CIDR block
`10.30.0.0/16`) each carry the **identical platform stack** (`terragrunt.stack.hcl`: vpc,
tgw-attachment, secrets, eks, cilium, karpenter{-iam,-controller,-nodepools}, keda, hpa-defaults,
wpa, rds, monitoring). It is **pilot-light / warm standby**: the IaC exists and is sized, but
scaled down and not continuously serving —

```hcl
# terragrunt/dr/account.hcl (sanitized)
single_nat_gateway = true            eks_public_access = false
eks_instance_types = ["m6i.xlarge"]  eks_min_size = 1  desired = 2  max = 5
rds_instance_class = "db.r6g.large"  rds_allocated_storage = 50  rds_multi_az = true
monitoring_replicas = 1
enable_tgw_attachment = false        # NOT yet wired to the network hub
# no GPU node pools; x86+arm64 Karpenter pools at spot_percentage = 50
```

DR data is **restored, not continuously replicated** into this account: RDS from automated
backups/snapshots, Kubernetes state from the Velero `aws-dr` bucket, Terraform state from the
`state-backend-dr` replica. This is the estate's chosen trade: low steady-state cost, RTO paid at
invocation time (re-apply + scale-up + restore). Today only `dr/_global/iam` is materialized.

### 2.6 Stateful services & durability surfaces

| Surface | Engine / mechanism | HA / DR posture |
|---|---|---|
| Platform DB | RDS **PostgreSQL 17.7** (registry module `terraform-aws-modules/rds/aws` v7.1.0). **Vanilla, single-instance + Multi-AZ standby. No Aurora, no read replicas.** | Multi-AZ = single-region AZ failover. `backup_retention_period` prod 30d / others 7d. **No cross-region snapshot copy or read replica.** |
| DB schema | ADR-0032: migrations as **ArgoCD PreSync Jobs** (Flyway `V1__` naming in-repo). | `backoffLimit:0`, `activeDeadlineSeconds:300`, ESO creds; no auto-rollback. |
| K8s persistent volumes | EBS CSI `gp3` StorageClasses (`WaitForFirstConsumer`); large per-chain StatefulSets, VictoriaMetrics, RabbitMQ. | Velero daily/weekly + EBS volume snapshots; cross-region `aws-dr` copy. |
| K8s app/PV backup | **Velero** (plugin-for-aws v1.11.0, CSI v0.8.0, `EnableCSI`). | Dual `backupStorageLocation` (`aws-primary` + `aws-dr`), **SSE-KMS required** (`alias/velero`), EBS snapshots primary + DR. Schedules: `daily-full` 02:00 UTC / 30d TTL, `weekly-full` Sun 03:00 / 90d TTL. |
| MLflow artifact store | S3 (`aws-ml-artifact-store`), GCS mirror, MinIO/Ceph-RGW mirror. | Versioning on; **no Object Lock, no replication**; SSE-KMS *or AES256 fallback*. |
| Immutable log archive | `centralized-logging` S3 bucket + org CloudTrail bucket. | **Object Lock** (GOVERNANCE 365d / CloudTrail **COMPLIANCE** WORM), SSE-KMS, cross-region CRR. |
| Terraform state | S3 `tfstate-<account>-<region>` + DynamoDB locks. | `state-backend-dr`: S3 CRR + DynamoDB **Global Tables v2** (active-active locks). |
| Bare-metal (UK DC, ADR-0052) | Rook-Ceph (RBD/CephFS/RGW, ≥3 replicas) + CloudNativePG streaming + MinIO site-replication. | Cross-DC: CNPG streaming (relational) + Ceph/MinIO site-replication (object). |

### 2.7 Data-at-rest immutability (object storage)

- **`aws-ml-artifact-store`** (`terraform/modules/aws-ml-artifact-store`, ADR-0048/0018/0028):
  `object_ownership=BucketOwnerEnforced`, all-four public-access-block, `prevent_destroy`,
  versioning **on by default**, a `DenyInsecureTransport` (`aws:SecureTransport=false`) bucket
  policy applied **after** the public-access-block, lifecycle `STANDARD_IA@90d → GLACIER_IR@365d →
  expire@730d`, **ABAC IAM** (grant conditioned on `aws:PrincipalTag/platform:system ==
  aws:ResourceTag/platform:system`), EKS **Pod Identity** trust scoped to the caller account.
  **Caveat**: when `kms_key_arn` is empty (the default) it silently falls back to **AES256
  (SSE-S3), not SSE-KMS**; and it carries **no Object Lock and no replication**.
- **`centralized-logging`** (the log-archive sink; `_envcommon/centralized-logging.hcl`): versioning
  hardcoded on, SSE-KMS always, **Object Lock GOVERNANCE, 365-day** default retention, cross-account
  write policy for CloudTrail/Config/VPC-Flow/EKS-audit, lifecycle to Glacier + expire **2555d
  (~7yr, PCI-DSS)**, and a **DR replica bucket** (`${bucket}-dr`) with S3 replication
  `{{PRIMARY_REGION}}→{{DR_REGION}}` including `delete_marker_replication`. The org **CloudTrail**
  bucket is stricter: **Object Lock COMPLIANCE** (true, non-overridable WORM), 365d.
- **KMS** (`_envcommon/kms.hcl`): a per-region CMK inventory (cloudtrail, aws-config, s3-data,
  eks-secrets, ebs, rds, sns, sqs, logs, backup), **rotation on**, `deletion_window=30`, ABAC key
  policy, `prevent_destroy` on protected keys. `common.hcl` declares
  `default_compliance_frameworks = "pci-dss,soc2,iso27001"`.

### 2.8 Terraform-state DR (deploy-capability continuity)

State lives in `tfstate-<account>-<region>` (SSE-KMS, versioning, `prevent_destroy`,
`DenyUnencryptedTransport` + `DenyDeleteBucket` policies) with a DynamoDB lock table
(`terraform-locks-<account>`, PAY_PER_REQUEST, **PITR on**, `prevent_destroy`). `root.hcl` sets
`retry_max_attempts=3`. The `state-backend-dr` module adds **one-way S3 CRR**
`{{PRIMARY_REGION}}→{{DR_REGION}}` plus a **DynamoDB Global Table v2** replica (bidirectional,
active-active locks; requires `stream_enabled` on the source). Failover is a **PR that repoints
`bucket`+`region`** in `root.hcl` to the DR region; `init -reconfigure` regenerates `backend.tf`.
Writes made to the replica during an outage are **not auto-replicated back** — recovery does an
explicit `aws s3 sync` before failing back. (Sandbox is the exception: it uses S3 native
`use_lockfile` instead of DynamoDB.)

---

## 3. Decision record

| Decision | Rationale | Trade-off accepted | Source |
|---|---|---|---|
| DNS-provider failover as a **stateful Go control loop with a 5-state machine**, not a cron script | Explicit states + persisted transitions make failover auditable, resumable after restart, and safe against flapping | Extra service to run and monitor; a shared DB dependency | `failover-controller/` (this spec) |
| **Hard safety caps**: `MaxDailyFailovers=1`, `FailoverCooldown=1h`, `MinTimeInState=5m`, optional `RequireManualAuth` | Failover is high-blast-radius (whole domain moves); caps prevent oscillation and runaway automation | A genuine second incident the same day needs manual override | `safety.go` |
| **3 consecutive degraded checks** before failover; **10-min recovery cooldown** before failback | Debounce transient provider blips; avoid ping-ponging back to a still-flaky primary | Adds ~90s (3×30s) detection latency and 10-min failback latency | `statemachine.go` |
| **Atomic JSON file** for controller state (not the DB) | Controller must know its own state even if the DB is the thing that failed; temp+rename is crash-safe | State is node-local; needs a PVC or restore on reschedule | `persistence.go` |
| **Registrar behind an interface**, mock by default, real impl via `REGISTRAR_TYPE` | Portable across Namecheap/GoDaddy/Cloudflare Registrar; testable without touching production DNS | A misconfigured build silently no-ops (mock) | `registrar.go` |
| **DR = warm-standby account re-provisioned by IaC**, data restored from backups; **not** continuous cross-region replication for RDS | Lowest steady-state cost; the full stack is already codified per region and re-appliable | Higher RTO (apply + scale-up + restore); RPO bounded by backup cadence | `terragrunt/dr/`, ADR-0032 |
| **Vanilla RDS Multi-AZ, no Aurora / no read replica** | Simplicity; Multi-AZ covers the common AZ-failure case; PITR + snapshots cover data loss | No sub-minute cross-region DB failover; regional RDS outage needs snapshot restore | `catalog/units/rds`, ADR-0032 |
| **Migrations as ArgoCD PreSync Jobs** (`backoffLimit:0`) | Runs once per sync, strictly before rollout; a failure blocks the sync and leaves current pods serving | No automatic down-migration; teams must ship idempotent, expand/contract migrations | ADR-0032 |
| **Immutable log archive**: Object Lock (GOVERNANCE for ops logs, **COMPLIANCE for CloudTrail**) + SSE-KMS + cross-region CRR | Tamper-evident audit trail for PCI-DSS/SOC2/ISO27001; survives a region loss | COMPLIANCE objects cannot be deleted before retention even by admins; storage cost | ADR-0002, `centralized-logging` |
| **Terraform-state DR**: S3 CRR + DynamoDB Global Tables, PR-driven region flip | Deploy capability survives a primary-region outage; locks stay consistent | Manual PR to flip; replica-side writes need manual sync-back | ADR-0002, `state-backend-dr` |
| **Break-glass IAM users protected with `prevent_destroy` + `force_destroy=false`** | Emergency access must survive `terraform destroy`, stray `moved` blocks, and SSO outages | `destroy` on such an account always fails until the lifecycle block is removed (intentional friction) | **ADR-0011** |
| **Serving fails over cross-region; batch/training is region-pinned + re-queued** | GPU jobs are gang-scheduled and stateful-in-flight; migrating them mid-run is unsafe | A region loss loses in-flight training progress (re-queued, not migrated) | ADR-0044, ADR-0036 |
| **Global Accelerator anycast for the transaction plane** (no DNS change on failover) | ~30s network-layer reroute; no client DNS-cache dependency | TCP-only health — app-level failures need manual traffic-dial failover | `docs/multi-region/`, ADR-0043 |

Additional cited ADRs: **ADR-0035** (Control Tower + AFT is the *intended* account-vending
substrate under which the `dr`/`log-archive` accounts are enrolled — planning-only today);
**ADR-0043** (cross-cluster ClusterMesh substrate the federation rides); **ADR-0052** (bare-metal
Rook-Ceph + CloudNativePG streaming DR); **ADR-0037/0048** (ML artifact-store lineage).

---

## 4. Implementation blueprint

### 4.1 Directory layout (load-bearing paths)

```
failover-controller/            # L1 Go control loop
├── main.go            # 30s ticker, HTTP :8080 (/metrics /healthz /readyz /state), signal handling
├── statemachine.go    # 5 states, thresholds, transition handlers
├── safety.go          # SafetyParams, validTransitions map, ValidateTransition
├── persistence.go     # ControllerState, atomic file StateStore
├── healthstore.go     # PostgresHealthStore, score formula (0.6/0.3/0.1)
├── registrar.go       # RegistrarClient interface + MockRegistrarClient
├── storage.go         # *sql.DB pool (lib/pq), MaxOpenConns=5
└── Dockerfile         # golang:1.26-alpine → alpine:3.24, nonroot uid 65532
database/migrations/V1__initial_schema.sql   # 5 tables (Flyway)

terragrunt/
├── root.hcl           # remote_state (S3+DynamoDB / sandbox use_lockfile), retry_max_attempts=3
├── dr/account.hcl     # DR sizing knobs (warm standby); regions eu-west-1/2/3, eu-central-1
├── dr/<region>/platform/terragrunt.stack.hcl   # full stack, identical to prod, scaled down
├── log-archive/account.hcl                      # immutable log sink account
└── _envcommon/{centralized-logging,kms}.hcl     # Object Lock, CRR, CMK inventory

terraform/modules/
├── aws-ml-artifact-store/     # S3 + TLS-deny + ABAC + Pod Identity + lifecycle
├── centralized-logging/       # Object Lock GOVERNANCE + SSE-KMS + DR CRR
├── cloudtrail/                # Object Lock COMPLIANCE (WORM)
├── state-backend{,-dr}/       # state S3+DynamoDB, cross-region replica + Global Table
├── rds{,-postgres}/           # RDS wrappers (legacy + service-owned)
└── break-glass-user/          # prevent_destroy + MFA policy (ADR-0011)
apps/infra/velero/values.yaml  # dual backupStorageLocation, schedules, SSE-KMS
docs/runbooks/                 # DISASTER_RECOVERY.md, state-backend-failover.md, velero-restore.md, DNS_*
docs/multi-region/runbooks/    # failover-auto.md, failover-manual.md, region-recovery.md
```

### 4.2 Load-bearing snippets (sanitized)

**RDS live unit** (`catalog/units/rds/terragrunt.hcl`) — sizing flows from `account.hcl`:

```hcl
terraform { source = "tfr:///terraform-aws-modules/rds/aws?version=7.1.0" }
inputs = {
  engine = "postgres"  engine_version = "17.7"  family = "postgres17"
  instance_class          = local.account_vars.locals.rds_instance_class      # per-env
  allocated_storage       = local.account_vars.locals.rds_allocated_storage
  multi_az                = local.account_vars.locals.rds_multi_az
  backup_retention_period = local.environment == "prod" ? 30 : 7              # 30d prod / 7d rest
  deletion_protection     = contains(["prod", "staging"], local.environment)  # NOT dr/dev
  storage_encrypted = true
  kms_key_id        = dependency.kms.outputs.key_arns["rds"]                  # customer CMK
  manage_master_user_password = true                                         # RDS-managed secret
  # rds.force_ssl=1 parameter group (apply_method = pending-reboot)
}
```

**Immutable log archive** (`_envcommon/centralized-logging.hcl` inputs → `centralized-logging`):

```hcl
enable_object_lock = true   object_lock_mode = "GOVERNANCE"  object_lock_retention_days = 365
use_kms_encryption = true   enable_replication = true         enable_cross_account_writes = true
lifecycle_standard_days = 90  lifecycle_glacier_days = 365    lifecycle_expiration_days = 2555 # ~7yr
# DR replica: ${bucket}-dr in {{DR_REGION}}, delete_marker_replication = Enabled
```

**TLS-deny bucket policy** (identical shape on every state/log/artifact bucket — CIS/FSBP):

```json
{ "Sid": "DenyInsecureTransport", "Effect": "Deny", "Principal": "*",
  "Action": "s3:*", "Resource": ["<bucket-arn>", "<bucket-arn>/*"],
  "Condition": { "Bool": { "aws:SecureTransport": "false" } } }
```

**Velero DR** (`apps/infra/velero/values.yaml`, excerpt): two `backupStorageLocation`s
(`aws-primary` default + `aws-dr`, `kmsKeyId` **required**), EBS `volumeSnapshotLocation`s
primary+DR, `defaultBackupTTL: 720h`, `schedules.daily-full "0 2 * * *"` (ttl 720h),
`weekly-full "0 3 * * 0"` (ttl 2160h), `features: EnableCSI`, `deployNodeAgent: true`.

**State backend** (`root.hcl`, sanitized) — note the sandbox branch uses S3 native locking:

```hcl
config = merge(
  { bucket  = "tfstate-${account_name}-${aws_region}"
    key     = "${environment}/${path_relative_to_include()}/terraform.tfstate"
    region  = state_bucket_region  encrypt = true },
  is_sandbox
    ? { use_lockfile = true  dynamodb_table = null }                 # S3 native lock (TF ≥ 1.10)
    : { use_lockfile = false dynamodb_table = "terraform-locks-${account_name}" } )
```

### 4.3 Ordering / dependencies (what must exist before what)

1. **State backend** (`bootstrap/state-backend/` via plain `terraform apply`, local state) → then
   `state-backend-dr` (needs source DynamoDB streams; gated by `enable_dynamodb_streams`).
2. **KMS CMK inventory** (`_envcommon/kms.hcl`) → before any SSE-KMS bucket/RDS/Velero (they
   reference `key_arns[...]` / `alias/velero` / `alias/log-archive`).
3. **Per-region platform stack** dependency chain (Terragrunt-managed): `vpc, secrets` →
   `eks` → `karpenter, monitoring, rds`. `rds` depends on `vpc, eks, secrets, kms`.
4. **L1 controller**: `database/migrations` applied → `dns-monitor` populating
   `health_check_results` → **then** `failover-controller` (empty scores otherwise no-op).
5. **Log archive**: `log-archive` account + `_envcommon/centralized-logging.hcl` unit wired before
   producer accounts point CloudTrail/Config/VPC-Flow/EKS-audit at it (see §7 pitfall — not yet
   instantiated in the reference estate).

---

## 5. Parameterization table

Global placeholders are defined in `SPEC-00-overview.md`. Spec-local placeholders below.

| Placeholder | Meaning | Example shape |
|---|---|---|
| `{{PRIMARY_REGION}}` / `{{DR_REGION}}` | primary + DR AWS regions | `eu-west-1` / `eu-central-1` |
| `{{DR_ACCOUNT_ID}}` | DR (warm-standby) account ID | `444444444444` |
| `{{LOG_ARCHIVE_ACCOUNT_ID}}` | immutable log-sink account ID | `888888888888` |
| `{{DOMAIN}}` | domain the controller fails over | `platform.example.com` |
| `{{REGISTRAR}}` | domain registrar (drives `REGISTRAR_TYPE`) | `namecheap` \| `godaddy` |
| `{{PRIMARY_DNS_PROVIDER}}` / `{{SECONDARY_DNS_PROVIDER}}` | active / standby DNS providers | `cloudflare` / `route53` |
| `{{STATE_BUCKET}}` | Terraform state bucket | `tfstate-{{ORG}}-{{PRIMARY_REGION}}` |
| `{{SANDBOX_ACCOUNT_ID}}` | personal/sandbox account (S3-native-lock path) | `123456789012` |

**Sizing knobs** (defaults observed here; resize per client):

| Knob | Where | Default (this estate) | Resize guidance |
|---|---|---|---|
| `DegradeThreshold` / `RecoveryThreshold` | `statemachine.go` | 0.5 / 0.7 | Lower degrade for eager failover; widen the gap to add hysteresis. |
| `ConsecutiveDegradedChecksRequired` | `statemachine.go` | 3 (×30s ≈ 90s) | Raise for noisier providers; lower to cut detection latency. |
| `MaxDailyFailovers` / `FailoverCooldown` | `safety.go` | 1 / 1h | Raise cap only with strong anti-flap confidence. |
| `RequireManualAuth` | `safety.go` | `false` (→ `true` in prod initially) | Keep `true` until failover is trusted end-to-end. |
| tick interval | `main.go` | 30s | Trades detection latency vs DB/registrar load. |
| `rds_instance_class` / `_allocated_storage` / `_multi_az` | `account.hcl` | prod `db.r6g.xlarge`/100/true · dr+staging `db.r6g.large`/50/true · dev `db.t4g.medium`/20/false | Match prod IOPS; keep DR ≥ the tier you must serve on. |
| `backup_retention_period` | `catalog/units/rds` | prod 30d / others 7d | Set to your RPO tier (see §5.1). |
| Velero `daily/weekly TTL` | `velero/values.yaml` | 720h / 2160h | Align with retention + restore SLA. |
| `object_lock_retention_days` | `centralized-logging.hcl` | 365 (GOVERNANCE); CloudTrail COMPLIANCE 365 | Set to the longest regulatory hold; COMPLIANCE is irreversible. |
| `lifecycle_expiration_days` | log buckets | 2555 (~7yr) | Match audit-retention regulation. |
| DR pod CIDRs | federation | A `10.10.0.0/16` / B `10.20.0.0/16` | Must be non-overlapping for ClusterMesh. |

### 5.1 What the client must decide — RTO/RPO tiers

The reference estate **does not publish numeric RTO/RPO for the GPU-ML federation** (it relies on
health-check detection windows). Numeric targets exist only in adjacent estates and are the shape a
client should adopt and tune:

| Tier | Example workload | RTO | RPO | Knobs that set it |
|---|---|---|---|---|
| **T0 tx/critical** | trading / UK-DC | < 15m planned, < 30m unplanned | < 60s | streaming replication (CNPG), Global Accelerator ~30s, MinIO site-replication |
| **T1 relational DB** | platform Postgres | ~1h (snapshot restore) | 5m (PITR) | RDS Multi-AZ + PITR; add cross-region snapshot copy for regional DR |
| **T2 observability** | metrics/logs in S3 | 2h | 0 (data in S3) | re-deploy stack; data already durable in object store |
| **T3 GPU serving** | inference | health-detect (~30s) + failover | stateless | `failover-controller` DNS failover + scale-to-zero standby pools |
| **T3 GPU batch** | training | re-queue, not migrated | last checkpoint | checkpoint cadence to durable store |

A client picks a tier per service, then sets: RDS `backup_retention_period` + optional
cross-region snapshot copy (RPO), DR account sizing + whether it is warm vs cold (RTO), Velero
schedule/TTL, Object Lock mode + retention, and the controller thresholds/caps.

### 5.2 Failure-mode matrix (failure · blast radius · detection · response · automated?)

| Failure | Blast radius | Detection | Response | Automated? |
|---|---|---|---|---|
| Primary DNS provider degrades | Domain resolution slows/fails globally | `dns-monitor` score `< 0.5`, 3× (~90s) | `failover-controller` swaps NS to secondary at registrar | ✅ (capped: 1/day, 1h cooldown; `RequireManualAuth` can gate) |
| Both DNS providers down | Total resolution outage | Both scores low; controller cannot pick a healthy target | Manual: activate 3rd emergency provider, upload octoDNS zone (`DISASTER_RECOVERY.md` Scenario B) | ❌ manual |
| Failover-controller / EKS control plane down | No automated DNS failover | Missing `/healthz`, absent metrics, alerts | Manual registrar override (bypasses safety checks); restore control plane | ❌ manual |
| Shared Postgres corrupt/down | Controller & monitor blind (no fresh scores) | Query errors; stale `check_timestamp` | Restore from RDS snapshot/AWS Backup; repoint `database-url` secret; restart pods (Scenario C) | ❌ manual (restore) |
| Single AZ failure (RDS) | One AZ of the DB | RDS Multi-AZ health | Automatic Multi-AZ standby promotion | ✅ (Multi-AZ, prod/staging/dr) |
| Regional RDS outage | Whole DB in a region | RDS/region alarms | Restore latest snapshot into `{{DR_REGION}}` / DR account; repoint secret | ❌ manual (no cross-region replica) |
| Region-level app outage (transaction plane) | All traffic to that region | Global Accelerator TCP/443 health, 3× (~30s) | GA reroutes anycast to healthy region; no DNS change | ✅ (network-layer) |
| App-level degradation (5xx, healthy TCP) | Users on that region get errors | Dashboards/alerts (GA won't catch it) | Manual traffic-dial → 0% for the region (`failover-manual.md`) | ❌ manual |
| Primary-region Terraform-state outage | Deploy capability (not prod traffic) | `terragrunt init/plan` fails > 15m; AWS Health | PR repoints backend to DR replica; force-unlock stale locks (`state-backend-failover.md`) | ❌ manual (PR) |
| EKS node / PV loss | Stateful pods on that node | Pod/PVC alerts | Velero restore (PV from EBS snapshot); Karpenter re-provisions nodes | ⚠️ semi (Velero restore is manual) |
| GPU region loss (serving) | Inference in that region | Health-probe / DNS failover | `failover-controller` shifts serving to standby region (scale-to-zero pools spin up) | ✅ serving only |
| GPU region loss (training) | In-flight batch jobs | Job/scheduler alerts | Jobs re-queued in healthy region from last checkpoint (NOT migrated) | ⚠️ re-queue, not migrate |

### 5.3 DR runbook shape (the estate's runbook library)

The estate keeps a runbook per failure class; a rebuild should mirror this shape. Every runbook is:
**trigger → decision tree → action steps → verification → recovery/failback → post-incident review**.

| Runbook | Scenario | Core action |
|---|---|---|
| `docs/runbooks/DISASTER_RECOVERY.md` | Region outage / total DNS outage / DB corruption | A: manual registrar override + deploy stack to secondary region + restore DB snapshot. B: emergency 3rd DNS provider + upload zone. C: restore DB from AWS Backup + repoint secret + restart pods. |
| `docs/multi-region/runbooks/failover-auto.md` | NLB/region loss (transaction plane) | GA auto-reroute (~30s); TCP-only; documents what does/doesn't trigger it. |
| `docs/multi-region/runbooks/failover-manual.md` | App-level degradation | Traffic-dial → 0% for the region; gradual 10→50→100% ramp on recovery; rollback to 0% if it re-fails. |
| `docs/multi-region/runbooks/region-recovery.md` | Bringing a failed region back | Verify EKS/nodes/Cilium/ClusterMesh; GA ramp 10→50→100% with 5-min soaks; post-incident review ≤ 48h. |
| `docs/runbooks/state-backend-failover.md` | Primary state-region outage | PR repoints `bucket`+`region` to DR replica; force-unlock orphaned locks; `aws s3 sync` back on failback. |
| `docs/runbooks/velero-restore.md` | K8s app/PV loss or whole-cluster DR | `velero restore create` (namespace, resource, or whole-cluster); cross-region restore from `aws-dr` label. |
| `docs/runbooks/DNS_*` (SPEC-02) | DNS failover initiated / provider degraded / sync failure | Operator-facing detail for each L1 event. |

**Drill cadence:** quarterly — practice the "controller down → manual registrar override" and the
region-recovery traffic ramp; schedule failover tests (scale a region's deployments to 0).

### 5.4 Data classification → storage mapping

| Class | Examples | Store | Durability controls |
|---|---|---|---|
| **Regulated audit / immutable** | CloudTrail, Config, VPC Flow, EKS audit | `centralized-logging` S3 (log-archive account) | Object Lock (CloudTrail **COMPLIANCE** / ops **GOVERNANCE**) 365d, SSE-KMS, cross-region CRR, expire ~7yr |
| **Relational transactional** | platform DB, tenant metadata, `dns_failover` schema | RDS PostgreSQL Multi-AZ | SSE-KMS CMK, `force_ssl`, backups 30d(prod)/7d, PITR; DR = snapshot restore |
| **ML artifacts / datasets** | MLflow artifacts, models, datasets | S3 (`aws-ml-artifact-store`) / GCS / MinIO-Ceph | Versioning, SSE-KMS (⚠ AES256 fallback), lifecycle IA→Glacier→expire; per-region (no CRR) |
| **Kubernetes app + PV state** | StatefulSets (chains, VictoriaMetrics, RabbitMQ) | EBS `gp3` + Velero | Velero daily/weekly, EBS snapshots, cross-region `aws-dr` bucket, SSE-KMS |
| **Infra state / locks** | Terraform state, lock table | S3 `tfstate-*` + DynamoDB | Versioning, SSE-KMS, `prevent_destroy`, PITR; DR = CRR + Global Tables |
| **Secrets** | DB creds, provider tokens | AWS Secrets Manager / Vault via ESO | RDS-managed master password; ESO refresh; SSE-KMS; never in TF state/`.tfvars` |
| **Ephemeral scratch** | build temp, non-durable caches | `emptyDir` / local-path | None — must not hold stateful ML data (ADR-0052 D5) |

---

## 6. Best practices distilled

1. **Separate the detector from the actuator.** `dns-monitor` measures; `failover-controller`
   decides and acts. A bug in scoring cannot directly move DNS, and the actuator can be reasoned
   about (and safety-capped) independently. *Why:* smaller blast radius, testable in isolation.
2. **Persist controller state atomically and locally, not in the database you might be failing over
   from.** Temp-file + rename survives a crash mid-write; a corrupt file degrades to a safe default.
   *Why:* the controller must remain deterministic even when its data plane is the thing that broke.
3. **Guard-rail every automated failover with hard caps.** `MaxDailyFailovers`, a cooldown, a
   minimum dwell time, and a manual-auth kill-switch. *Why:* the worst failover automation failure
   is oscillation; caps convert "runaway" into "one action, then a human".
4. **Debounce before you act, cool down before you revert.** 3 consecutive bad checks in; a 10-min
   stability window before failback. *Why:* transient provider blips must not trigger a real,
   costly provider swap, and a flaky primary must not be trusted the instant it looks up.
5. **Prefer network-layer failover (anycast) where you can.** Global Accelerator reroutes in ~30s
   with no client DNS-cache dependency; DNS-provider failover is the fallback for when the whole
   provider is the failure. *Why:* DNS TTLs make DNS failover slow and uneven.
6. **Make DR an *account*, defined as IaC, sized down — not a second live environment.** The `dr`
   account carries the same stack, so recovery is `apply` + scale-up + restore, reviewed like any
   change. *Why:* a warm standby you can rebuild beats a hot mirror you pay for and let drift.
7. **Encrypt in transit *and* deny plaintext at the bucket.** Every state/log/artifact bucket
   carries `DenyInsecureTransport` on top of SSE-KMS. *Why:* defence in depth; a missing
   client-side flag fails closed, not open.
8. **Use Object Lock for audit data — COMPLIANCE where regulation demands true WORM.** CloudTrail
   is COMPLIANCE (no one, including admins, deletes before retention); ops logs are GOVERNANCE.
   *Why:* tamper-evidence for PCI-DSS/SOC2/ISO27001; pick the strictest mode you can operate.
9. **Replicate the things you cannot recreate — state and audit logs — cross-region.** Terraform
   state (CRR + DynamoDB Global Tables) and the log archive (CRR) both survive a region loss.
   *Why:* you can re-apply infrastructure, but you cannot re-derive lost state or lost audit trail.
10. **Run schema migrations as a pre-deploy gate, not per-pod.** ArgoCD PreSync Jobs run once,
    strictly before rollout, `backoffLimit:0`; a failure blocks the sync and leaves current pods
    serving. *Why:* eliminates the multi-replica migration race and the "neither version available"
    window of init-container migrations.
11. **Protect break-glass identities with `prevent_destroy`.** Plan-time protection beats
    apply-time (`force_destroy=false`) because it stops a destroy from even being *planned*.
    *Why:* emergency access must survive a stray `terraform destroy` or `moved` block (ADR-0011).
12. **Drill quarterly and ramp traffic back gradually.** Practise the manual registrar override and
    the region recovery (10% → 50% → 100% traffic dial). *Why:* an untested runbook is a hypothesis;
    a thundering-herd restore causes a second outage.
13. **Classify data first, then map storage + durability to the class.** Each class (audit, tx,
    artifacts, PV, state, secrets, scratch — §5.4) has one home and one durability contract.
    *Why:* prevents regulated data landing in a non-immutable bucket or secrets in Terraform state.

---

## 7. Known pitfalls

1. **As-built divergence — the log-archive design is not wired.** `terragrunt/log-archive/<region>/` contains only
   `region.hcl` — no unit includes `_envcommon/centralized-logging.hcl`. Object Lock, KMS,
   cross-account policy, and DR replication are **designed but not instantiated**. A rebuild must
   actually create the unit; do not assume immutability is live because the module exists.
2. **As-built divergence — ML artifact store silently downgrades encryption.** `aws-ml-artifact-store` defaults
   `kms_key_arn=""` → **AES256 (SSE-S3), not SSE-KMS**. Pass a CMK explicitly for any regulated
   data. It also has **no Object Lock and no replication** — it is not a durable-of-record store.
3. **As-built divergence — lifecycle wiring mismatch in `centralized-logging`.** `_envcommon` passes
   `lifecycle_glacier_days=365`, but the module transitions to GLACIER on the *unset*
   `lifecycle_ia_days` (default **90**); `lifecycle_glacier_days` is defined-but-unused there. Audit
   the actual transition, don't trust the input name.
4. **As-built divergence (confirm intent) — Object Lock mode divergence (GOVERNANCE vs COMPLIANCE).** Only the **CloudTrail** bucket is true WORM (COMPLIANCE); the
   general log archive is **GOVERNANCE** (an admin with the bypass permission *can* delete). If a
   client needs regulator-grade immutability for all logs, promote to COMPLIANCE knowingly.
5. **As-built divergence — RDS has no cross-region DR.** Multi-AZ covers AZ failure only; there is **no read replica and
   no cross-region snapshot copy**. A regional RDS outage means restore-from-snapshot into the DR
   region (T1 RTO ~1h). The DR account's RDS is a *fresh* instance, not a replica.
6. **As-built divergence — DR account is a warm standby, and `deletion_protection=false` there.** DR RDS retention is 7d
   (only prod gets 30d + deletion protection), and `enable_tgw_attachment=false` means DR is not yet
   connected to the network hub. Treat DR as "codified, needs finishing", not "hot".
7. **As-built divergence — three divergent RDS code paths.** `catalog/units/rds` (registry `7.1.0`, PG 17.7) vs
   `terraform/modules/rds` (`~>6.0`, PG "17", `db_name=dns_failover`) vs `rds-postgres` (raw
   `aws_db_instance`, PG "16"). Only the catalog unit is wired into platform stacks; do not copy the
   legacy wrappers by mistake.
8. **As-built divergence — `RequireManualAuth=false` by default.** The failover safety default ships permissive; the code
   comment says set it `true` for production initially. A rebuild that skips this gives fully
   automated DNS failover on day one.
9. **`MaxDailyFailovers=1` can strand you.** A legitimate second incident the same calendar day
   cannot auto-fail-over — it needs the manual registrar-override runbook. This is intentional but
   must be operationally understood.
10. **State-backend failback is not automatic.** S3 CRR is one-way; writes to the DR replica during
    an outage must be `aws s3 sync`'d back before failback, or state diverges. Both buckets carry
    `prevent_destroy` — never `aws s3 rb` / `delete-table` during an incident.
11. **Batch/training does not fail over.** In-flight GPU jobs are region-pinned and re-queued.
    Clients must checkpoint to a durable store; a region loss loses uncheckpointed progress.
12. **Sanitize the sandbox path.** The reference `root.hcl` embeds a real sandbox account ID and a
    real pre-existing bucket name; replace with `{{SANDBOX_ACCOUNT_ID}}` / `{{STATE_BUCKET}}` and
    do not carry the hard-coded personal-account carve-out into a client build.

---

## 8. Acceptance checklist

A rebuild passes when:

- [ ] `failover-controller` starts, loads (or defaults) persisted state, exposes `/healthz`,
      `/readyz`, `/state`, `/metrics`, and logs an initial evaluation within one tick.
- [ ] With a synthetic primary score `< 0.5` sustained for 3 checks, the controller transitions
      `HEALTHY→DEGRADED→FAILING_OVER`, calls `UpdateNameservers` to the secondary, and lands in
      `FAILED_OVER`; a `< 0.5` blip that recovers before 3 checks returns to `HEALTHY`.
- [ ] `ValidateTransition` **blocks** a second failover within `FailoverCooldown`, a failover once
      `DailyFailoverCount ≥ MaxDailyFailovers`, and (when `RequireManualAuth=true`) any
      `→ FAILING_OVER`.
- [ ] Killing the controller mid-run and restarting resumes from the persisted state file (no
      re-failover), and a corrupted state file degrades to `HEALTHY` without crashing.
- [ ] `terragrunt run --all plan` is clean for the `dr` account from an empty account; the DR stack
      composes the same units as prod at DR sizing.
- [ ] RDS comes up Multi-AZ (prod/staging/dr), `storage_encrypted=true` with the `rds` CMK,
      `rds.force_ssl=1` enforced, `backup_retention_period` = 30 (prod) / 7 (others),
      `deletion_protection` on for prod+staging.
- [ ] A DB migration ships as an ArgoCD **PreSync** Job (`hook-delete-policy: HookSucceeded`,
      `backoffLimit:0`); a failing migration marks the Application `Failed` and does **not** start
      the new rollout.
- [ ] Velero has two `backupStorageLocation`s (`aws-primary` + `aws-dr`), both SSE-KMS; `daily-full`
      and `weekly-full` schedules exist; a `velero restore` of one namespace succeeds and binds PVCs
      from EBS snapshots.
- [ ] Every state/log/artifact bucket denies `aws:SecureTransport=false`, blocks public access, and
      carries `prevent_destroy`; the CloudTrail bucket is Object-Lock **COMPLIANCE**.
- [ ] `state-backend-dr` replicates state `{{PRIMARY_REGION}}→{{DR_REGION}}` and the DynamoDB lock
      table shows both regions as Global-Table replicas; the state-backend-failover runbook flips
      the backend via a PR and `terragrunt plan` succeeds against the replica.
- [ ] Global Accelerator health checks are TCP/443, 10s/3-threshold, both endpoint groups
      `traffic_dial=100`; scaling a region's workloads to 0 shifts traffic within ~30s.
- [ ] A quarterly DR drill (manual registrar override + region-recovery ramp 10→50→100%) is
      scheduled and documented.

---

## 9. Dependencies on other specs

- **SPEC-00** — global placeholders (`{{ORG}}`, `{{PRIMARY_REGION}}`, `{{DR_REGION}}`,
  `{{STATE_BUCKET}}`, account IDs).
- **SPEC-01 (Foundation IaC)** — the Terragrunt root/`_envcommon` skeleton, `versions.hcl`
  (Terraform `1.14.8`, Terragrunt `1.0.8`, `aws ~> 6.0`), and the account/region hierarchy this
  spec's DR account and state backend build on.
- **SPEC-02 (Network & DNS)** — **tight coupling**: `dns-monitor` writes the
  `health_check_results` this controller reads and owns the health-score formula; `dns-sync`
  (octoDNS, YAML zone-of-truth, Cloudflare + Route53 targets, IRSA for Route53) is the zone source
  used by the DR "upload zone to emergency provider" runbook. SPEC-02 also owns the **network
  fabric** the L2 federation rides — Transit Gateway peering, Cilium ClusterMesh (WireGuard), VPC
  CIDR allocation, and the DR account's `enable_tgw_attachment` wiring. The L1 failover here is the
  actuator on top of SPEC-02's detection.
- **SPEC-03 (Compute / EKS / Karpenter / KEDA)** — the platform stack the DR account re-provisions;
  scale-to-zero standby GPU node pools.
- **SPEC-04 (Delivery / GitOps)** — ArgoCD ApplicationSets, the PreSync-Job DB migration mechanism
  (ADR-0032), and Velero delivery (`SPEC-04-delivery-gitops.md`).
- **SPEC-05 (Security / IAM / Org)** — KMS CMK inventory, ABAC tag conditions, break-glass
  (ADR-0011), and Control Tower/AFT account vending (ADR-0035) that governs the `dr` and
  `log-archive` accounts.
- **SPEC-07 (Observability)** — Grafana `multiregion-overview` / `clustermesh-status` dashboards,
  the GA/CloudWatch alarms, and the Velero `ServiceMonitor` that make failover observable.
- **SPEC-09 (AI-SRE)** — the advisory SRE layer that consumes these failover/DR signals
  (`specs/SPEC-09-ai-sre.md`).
- **SPEC-10 (ML Workloads)** — the GPU-ML federation whose serving-failover / batch-re-queue
  semantics this spec documents at the resilience layer.
```
