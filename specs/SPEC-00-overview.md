# SPEC-00 — Platform Overview & Shared Registries

> The front-matter for a portable, reverse-engineered platform estate. This document is
> written for a **client CTO and platform lead** deciding whether — and how — to rebuild
> this platform for a new organization. It grounds every claim in the ten domain specs
> (`SPEC-01`…`SPEC-10`), owns the **canonical placeholder registry**, and consolidates the
> cross-spec **as-built divergence** and **recommendation** registers a rebuild team must
> work through. Read this before any domain spec. Follows `CONVENTIONS.md`; all identity is
> parameterized — no real account IDs, org names, domains, emails, IPs, or bucket names appear.

---

## 1. What this platform is

This is an **AWS-primary, multi-account Infrastructure-as-Code estate** that runs
containerized and GPU/ML workloads on Kubernetes, delivered by GitOps, guarded by
defense-in-depth security and full CI/CD quality gates, and observed by a self-hosted
telemetry plane — with disaster-recovery machinery and an advisory AI operations layer on
top. Every capability below is reproducible from the domain spec named in parentheses.

- **A landing zone as code.** An AWS Organization with an 8-OU tree (Security /
  Infrastructure / Workloads → NonProd/Prod, plus Deployments / Sandbox / Suspended) over a
  canonical ~11-account topology (management, security, log-archive, network, shared, dev,
  staging, prod, dr, third-party, optional sandbox). Orchestration is **Terragrunt over
  Terraform/OpenTofu** (`root.hcl` generates backend + provider + version files; `_envcommon/`
  kills per-account duplication), with a Terraform-only bootstrapped remote-state backend and
  a single version-pin source of truth (`versions.hcl`). Control Tower + AFT account vending is
  the ratified *target*, not the live path. (**SPEC-01**)
- **A segmented network substrate.** A hub-and-spoke Transit Gateway owned by the network
  account, deterministic non-overlapping per-environment/region VPC CIDRs, deny-by-default
  route-table segmentation, cross-account Route 53 Resolver, and a dual-provider authoritative
  DNS control plane (octoDNS to two providers) with a scored health monitor and a registrar-level
  failover controller. (**SPEC-02**)
- **A Kubernetes compute plane.** EKS control planes (private-by-default) with **Cilium**
  (eBPF, ENI IPAM, WireGuard) as the sole CNI, **Karpenter** for just-in-time nodes on
  **Bottlerocket**, **KEDA/HPA** for pod autoscaling, EKS Pod Identity for workload identity,
  and dedicated clusters per specialized workload class (general, HPC/blockchain, GPU). (**SPEC-03**)
- **GitOps delivery.** **ArgoCD** app-of-apps + ApplicationSets fan work across the cluster
  fleet by label; **Kargo** advances an immutable Freight through a metric-gated
  dev→integration→staging→prod promotion graph; one generic `helm/app` chart deploys every
  workload. (**SPEC-04**)
- **Defense-in-depth security.** A six-layer map (org → account → network → cluster → workload
  → pipeline): SCPs + RCPs + EC2 declarative policies + break-glass; centralized audit/logging;
  admission control (Gatekeeper/Kyverno/VAP) + image-signature verification; Pod-Identity ABAC +
  External Secrets Operator + KMS + rotation; and a keyless-OIDC supply chain. (**SPEC-05**)
- **CI/CD quality gates.** A GitHub Actions estate (34 workflows + 10 composite actions) wiring
  the IaC verification loop (`fmt → validate → tflint → checkov/tfsec → plan → OPA → cost`),
  merge-gating vs advisory checks, keyless OIDC (no long-lived cloud keys), a supply-chain chain
  (harden-runner → build → Trivy → SBOM → cosign), scheduled drift detection, and an Infracost
  gate — portable to GitLab CI. (**SPEC-06**)
- **Self-hosted observability.** An LGTM-aligned signal plane (Prometheus 3.x + Thanos on S3,
  Loki, Tempo, Pyroscope, one RED-metric source), a VictoriaMetrics variant for the GPU-inference
  mega-cluster, DCGM GPU telemetry with a hardened auto-taint loop, ML drift/accuracy monitoring,
  SLOs-as-code (Pyrra), severity-tiered Alertmanager routing, and OpenCost cost visibility. (**SPEC-07**)
- **Resilience & DR.** Three decoupled resilience layers — DNS-provider failover (the Go
  `failover-controller`), multi-region active-active via Global Accelerator anycast, and a
  warm-standby DR account re-provisioned by IaC — plus stateful-service HA (RDS Multi-AZ, Velero,
  immutable Object-Lock log archive, cross-region state replication) and an RTO/RPO tiering the
  client must choose. (**SPEC-08**)
- **An advisory AI-SRE.** A multi-agent LLM system that investigates alerts and posts
  human-actionable recommendations to Slack but **never mutates infrastructure autonomously** —
  "advisory-only" is enforced by four independent controls (read-only MCP → read-only RBAC →
  egress NetworkPolicy → app-layer guardrails), with its own SLOs, cost cap, and audit trail. (**SPEC-09**)
- **An ML/GPU serving surface.** A model-aware, KV-cache-aware inference path (WAF → Gateway API
  Inference Extension → InferencePool/EndpointPicker → vLLM on DRA-claimed GPUs over RDMA fabric),
  a per-machine-family GPU capacity strategy, an Airflow→MLflow→Kargo model lifecycle with
  drift-driven retrain, and one operating model expressed across GCP, AWS, Azure, and bare-metal. (**SPEC-10**)

**Read this as a design estate, not a running product.** Large parts of the ML/GPU surface
(SPEC-10), the AI-SRE (SPEC-09), and several security/resilience units are **ratified design
targets or partially-simulated scaffolds**, not wired production — §4 (the divergence register)
is the authoritative catalog of what is real vs. scaffolded. A rebuild must treat those rows as
work items, not as already-done.

---

## 2. Spec map

| Spec | Domain | What it lets you rebuild | Key decisions inside |
|---|---|---|---|
| **SPEC-01** | Foundation: IaC, account topology & state | The AWS Org + 8-OU tree, ~11-account topology, Terragrunt/`_envcommon`/`catalog` skeleton, Terraform-only state bootstrap, version pins, ADR-0028 tagging taxonomy | Terragrunt over plain TF (ADR-0004); TF-only state backend (ADR-0002); OU split (ADR-0001); unified tagging (ADR-0028); Control Tower + AFT target (ADR-0035) |
| **SPEC-02** | Network topology & DNS | Hub-spoke Transit Gateway, deterministic VPC CIDR scheme, deny-by-default segmentation, Route 53 Resolver, dual-provider octoDNS + health monitor + registrar failover | Hub-spoke TGW (ADR-0005); inter-VPC deny-by-default (ADR-0013); Cilium CNI (ADR-0003); Gateway API ingress (ADR-0009); VPC Lattice (ADR-0023) |
| **SPEC-03** | Compute clusters (EKS/Karpenter/Cilium/KEDA) | EKS control plane, Cilium ENI dataplane, Karpenter NodePools on Bottlerocket, KEDA/HPA, Pod Identity, per-workload cluster split | Cilium replaces VPC CNI (ADR-0003); Karpenter over CAS (ADR-0007/0046); Bottlerocket (ADR-0030); Pod Identity (ADR-0018); private EKS endpoint (ADR-0010) |
| **SPEC-04** | Delivery & GitOps | ArgoCD app-of-apps + ApplicationSets, Kargo promotion graph, the generic `helm/app` chart, PreSync migrations, drift/rollback | ArgoCD GitOps (ADR-0006); `cluster_role` label scheme (ADR-0012); Kargo promotion (ADR-0021); ArgoCD hardening (ADR-0024); PreSync migrations (ADR-0032) |
| **SPEC-05** | Security | Org guardrails (SCP/RCP/EC2 declarative), audit/logging accounts, Pod-Identity ABAC, ESO + KMS + rotation, admission control, supply-chain gates | Two perimeters SCP+RCP (ADR-0017); break-glass (ADR-0011); Pod Identity ABAC (ADR-0018); Kyverno+VAP (ADR-0020); tier-1 supply chain (ADR-0016/0022) |
| **SPEC-06** | CI/CD & quality gates | The GitHub Actions estate, IaC loop as CI, keyless OIDC, supply-chain build path, drift detection, Infracost gate, GitLab port | Reusable pipelines (ADR-0015); keyless OIDC + split plan/apply roles; supply chain (ADR-0016); runtime hardening (ADR-0022); cost gate (ADR-0027) |
| **SPEC-07** | Observability | LGTM stack (Prom+Thanos/Loki/Tempo/Pyroscope), VictoriaMetrics GPU variant, DCGM + auto-taint, ML drift, Pyrra SLOs, Alertmanager routing, OpenCost | LGTM target (ADR-0026); one RED source (ADR-0026/0019); OpenCost+CUR (ADR-0027); ML drift (ADR-0038); self-serve observability (ADR-0039) |
| **SPEC-08** | Resilience, DR & stateful services | The `failover-controller`, warm-standby DR account, RDS HA, Velero, immutable log archive, state DR, failure-mode matrix + RTO/RPO tiers | Stateful failover control loop; warm-standby DR; vanilla RDS Multi-AZ; PreSync migrations (ADR-0032); Object-Lock archive (ADR-0002); break-glass (ADR-0011) |
| **SPEC-09** | Advisory AI-SRE | The multi-agent advisory system, four-layer advisory-only enforcement, runbook/approval engine, ClickHouse memory, MCP tool surface, meta-observability | Advisory-only invariant; 4-layer defense in depth; orchestrator+specialists over a Blackboard; GitOps-PR remediation; SOC2/on-call (ADR-0040); *no dedicated committed ADR* (see §4) |
| **SPEC-10** | ML / GPU workloads | The inference serving reference arch, GPU capacity strategy, Airflow→MLflow→Kargo lifecycle, multi-cloud pattern (GCP/AWS/Azure/bare-metal) | Gateway API Inference Extension (ADR-0042/0047/0053); DRA over `nvidia.com/gpu` (ADR-0044); Volcano gang scheduling; Airflow orchestration (ADR-0037); *all ML ADRs Proposed/apply-gated* |

### Reading / execution order for a rebuild

```
SPEC-01 → SPEC-02 → SPEC-03 → SPEC-05 → SPEC-04 → SPEC-06 → SPEC-07 → SPEC-08 → SPEC-10 → SPEC-09
foundation  network   compute  security  delivery  ci/cd    observ.   resilience  ml/gpu   ai-sre
```

**Why this order.** SPEC-01 is the ground floor every spec assumes (accounts, Terragrunt,
state, version pins, tagging). SPEC-02 lays the network substrate SPEC-03's clusters ride on.
SPEC-05 precedes SPEC-04 deliberately: org guardrails, ESO/`ClusterSecretStore`, KMS, and the
admission stack are prerequisites the GitOps delivery plane *references* (charts point at an
`ExternalSecret`; workloads must land on a cluster that already denies-by-default), so secrets and
admission must exist before delivery is wired. SPEC-06 guards everything and reads best once the
delivery model it gates is understood. SPEC-07 is delivered *via* SPEC-04 and consumes SPEC-05
secrets. SPEC-08 layers DR/stateful machinery on the running stack. SPEC-10 reuses compute +
delivery + observability + security. SPEC-09 is last — an advisory overlay that only *consumes*
SPEC-07 signals and *proposes* SPEC-04 PRs, mutating nothing. (SPEC-05↔SPEC-04 is a mutual
dependency; the order above resolves it toward "secrets/admission first, delivery second".)

---

## 3. Shared placeholder registry (canonical)

This is the **one canonical registry** for the estate. Every `{{PLACEHOLDER}}` used by any spec
resolves here; spec-local placeholders are registered against this table. Fill this table with
client values **first** (§7). All example shapes below are documentation placeholders (repeated-digit
account IDs, RFC-5737/RFC-1918 IPs, `example.com`) — never real values.

### 3.1 Identity & organization

| Placeholder | Meaning | Specs | Example shape |
|---|---|---|---|
| `{{ORG}}` | Organization / company slug (bucket + WAF-ACL prefix, sandbox state bucket) | 01,02,03,05,07,08,09,10 | `acme` (lowercase, DNS-safe) |
| `{{PROJECT}}` | Project/repo slug in role ARNs + `Project` tag (`{{PROJECT}}-terraform-*` SCP exemption). **Alias: `{{REPO}}`** | 01,05 | `platform-design` |
| `{{ORG_ID}}` | AWS Organizations ID (perimeter SCP/RCP condition) | 02,05 | `o-0123456789` |
| `{{DOMAIN}}` | Root authoritative DNS zone (Grafana OAuth, octoDNS, runbook URLs) | 01,02,06,07,08,10 | `platform.example.com` |
| `{{ROOT_EMAIL_DOMAIN}}` | Root-account email domain (`aws+<role>@…`); may equal `{{DOMAIN}}` but kept distinct | 05 | `example.com` |
| `{{VCS_ORG}}` | Git hosting org that owns the platform + GitOps repos | 01,04,06,10 | `acme-platform` |

### 3.2 Accounts (12-digit AWS account IDs — repeated-digit doc shape + `# TODO: replace`)

| Placeholder | Meaning | Specs | Example shape |
|---|---|---|---|
| `{{MGMT_ACCOUNT_ID}}` | Org management / landing-zone hub | 01,02,05 | `000000000000` |
| `{{DEV_ACCOUNT_ID}}` | Development workloads | 01,02,03,05 | `111111111111` |
| `{{STAGING_ACCOUNT_ID}}` | Pre-production (canonical name `stage`) | 01,02 | `222222222222` |
| `{{PROD_ACCOUNT_ID}}` | Production workloads (also fronts CI OIDC roles, ECR) | 01,02,03,04,05,06,07 | `333333333333` |
| `{{DR_ACCOUNT_ID}}` | Warm-standby DR for prod | 01,02,08 | `444444444444` |
| `{{NETWORK_ACCOUNT_ID}}` | TGW hub, Route 53 Resolver, VPN, Lattice | 01,02 | `555555555555` |
| `{{SECURITY_ACCOUNT_ID}}` | GuardDuty/SecurityHub delegated admin | 01,02,05 | `777777777777` |
| `{{LOG_ARCHIVE_ACCOUNT_ID}}` | Centralized immutable log bucket. **Alias: `{{LOGARCHIVE_ACCOUNT_ID}}`** | 01,02,05,08 | `888888888888` |
| `{{SHARED_ACCOUNT_ID}}` | ECR, Route 53 private zones, ACM, Service Catalog | 01,02 | `999999999999` |
| `{{THIRDPARTY_ACCOUNT_ID}}` | Vendor IAM principals (narrow cross-org trust) | 01 | `666666666666` |
| `{{SANDBOX_ACCOUNT_ID}}` | Optional personal escape-hatch account (S3-native-lock path) | 01,08 | `123456789012` |
| `{{AWS_ACCOUNT_ID}}` | Generic per-pipeline account behind OIDC roles / ECR (context-resolved) | 10 | one of the above |

> **Two sources of truth for account IDs** (SPEC-01 §4.5): each account's own `account.hcl` **and**
> the `member_accounts` map in `_org/account.hcl`. Keep them in sync in one PR when onboarding an account.

### 3.3 Regions

| Placeholder | Meaning | Specs | Example shape |
|---|---|---|---|
| `{{PRIMARY_REGION}}` | Primary / aggregator / Control-Tower home region | 01,02,03,04,05,06,07,08,09,10 | `eu-west-1` |
| `{{DR_REGION}}` | DR region (∈ `{{SECONDARY_REGIONS}}`) | 02,05,08,10 | `eu-central-1` |
| `{{SECONDARY_REGIONS}}` | Additional active regions (list) | 01,02,03 | `["eu-west-2","eu-west-3","eu-central-1"]` |
| `{{SECONDARY_REGION}}` | One active-active partner region (delivery) | 04 | `eu-central-1` |
| `{{PRIMARY_REGION_SHORT}}` / `{{SECONDARY_REGION_SHORT}}` | Short region tokens in app names + value-file lookups (≤4 chars) | 04 | `euw1` / `euc1` |
| `{{SECRETS_REGION}}` | ESO `ClusterSecretStore` region (may differ from primary — see §4/§5) | 05,07 | `eu-central-1` |

### 3.4 DNS, network & failover

| Placeholder | Meaning | Specs | Example shape |
|---|---|---|---|
| `{{PRIMARY_DNS_PROVIDER}}` | Active authoritative DNS provider. **Alias: `{{PRIMARY_DNS}}`** | 02,08 | `cloudflare` |
| `{{SECONDARY_DNS_PROVIDER}}` | Standby authoritative DNS provider. **Alias: `{{SECONDARY_DNS}}`** | 02,08 | `route53` |
| `{{REGISTRAR}}` | Domain registrar (drives `REGISTRAR_TYPE`) | 08 | `namecheap` / `godaddy` |
| `{{MAIL_PROVIDER}}` | SPF include host | 02 | `_spf.google.com` |
| `{{TGW_ASN}}` | Amazon-side TGW BGP ASN (private 64512–65534) | 02 | `64512` |
| `{{DEPLOY_ROLE}}` | Cross-account deploy role assumed by CI | 01 | `TerragruntDeployRole` |
| `{{OPERATOR_IP}}` | Sandbox operator public-IP allow-list (sandbox only; never a real IP) | 01 | `198.51.100.10/32` |
| `{{ADMIN_CIDR_ALLOWLIST}}` | Operator/VPN egress CIDRs for a public API (**never** `0.0.0.0/0`) | 03 | narrow RFC-1918 range |

### 3.5 State, buckets, KMS & clusters

| Placeholder | Meaning | Specs | Example shape |
|---|---|---|---|
| `{{STATE_BUCKET}}` | Terraform state bucket | 01,02,08 | `tfstate-<account>-<region>` (org); `{{ORG}}-terraform-state-<id>` (sandbox) |
| `{{LOG_ARCHIVE_BUCKET}}` | Central immutable log bucket | 05 | `{{ORG}}-log-archive-{{LOG_ARCHIVE_ACCOUNT_ID}}-{{PRIMARY_REGION}}` |
| `{{ACCOUNT_EMAIL}}` | Per-account root email (plus-addressing) | 01 | `aws+<name>@{{DOMAIN}}` |
| `{{KMS_EKS_SECRETS_KEY_ARN}}` | Secrets CMK ARN (control-plane envelope encryption) | 03 | KMS unit `key_arns["eks-secrets"]` |
| `{{CLUSTER_NAME}}` | Cluster name pattern / Thanos dedup key | 03,07 | `<env>-<region>-platform` |
| `{{SANDBOX_EMAIL}}` / `{{SANDBOX_USER}}` | Sandbox root email / IAM user (sandbox only) | 01 | *(sanitized)* / `sandbox-admin` |

### 3.6 Repos, registries & CI

| Placeholder | Meaning | Specs | Example shape |
|---|---|---|---|
| `{{GITOPS_REPO}}` | The single GitOps mono-repo (`argocd/ apps/ envs/ helm/ kargo/`). **See §4 D-INC: overlaps `{{ARGOCD_CONFIG_REPO}}`** | 04 | `platform-design` |
| `{{ARGOCD_CONFIG_REPO}}` | GitOps config repo the deploy pipeline PRs into | 06,10 | `{{VCS_ORG}}/argocd` |
| `{{PLATFORM_WORKFLOWS_REPO}}` | Shared reusable-workflow repo | 06 | `{{VCS_ORG}}/platform-workflows` |
| `{{ECR_REGISTRY}}` | AWS image registry base | 04,10 | `{{PROD_ACCOUNT_ID}}.dkr.ecr.{{PRIMARY_REGION}}.amazonaws.com` |
| `{{ML_IMAGE_REPO}}` | Model image registry | 10 | `{{AWS_ACCOUNT_ID}}.dkr.ecr.{{PRIMARY_REGION}}.amazonaws.com/ml` |
| `{{GHCR_REGISTRY}}` | GHCR registry (e.g. auto-taint image) | 07 | `ghcr.io/{{VCS_ORG}}` |
| `{{ARGOCD_SERVER}}` | ArgoCD API host (smoke/wait) | 06 | `argocd.{{DOMAIN}}` |
| `{{CI_BOT_NAME}}` / `{{CI_BOT_EMAIL}}` | Git committer for auto-commits/PRs | 06,10 | `platform-ci[bot]` / `ci@{{DOMAIN}}` |
| `{{CI_FEATURE_BRANCH}}` | Long-lived migration branch also gated | 06 | `feature/**` |

### 3.7 Cloud identity (multi-cloud — GPU/ML)

| Placeholder | Meaning | Specs | Example shape |
|---|---|---|---|
| `{{GCP_PROJECT_ID}}` | GCP project (GKE, GCS reference data). **Alias: `{{GCP_PROJECT}}`** | 07,10 | `acme-ml-prod` |
| `{{AZURE_SUBSCRIPTION_ID}}` | Azure subscription (AKS estate) | 10 | `00000000-0000-0000-0000-000000000000` |
| `{{MLFLOW_TRACKING_URI}}` / `{{AIRFLOW_BASE_URL}}` / `{{MLFLOW_S3_ENDPOINT_URL}}` | ML control-plane endpoints (per substrate; CI `vars.*`) | 10 | in-cluster service URLs |
| `{{MODEL_ID}}` / `{{BASE_MODEL}}` | Served model / base model | 10 | `fraud-uk` / `Qwen 2.5 3B` |

### 3.8 ML / observability / AI-SRE knobs

| Placeholder | Meaning | Specs | Example shape |
|---|---|---|---|
| `{{TENANT}}` / `{{DOMAIN_SLUG}}` | ML tenant / business domain (namespace `ml-<tenant>-<domain>`) | 07 | `tenant-acme` / `hft,rtb,insurance` |
| `{{SLUG}}` | Team/alert-name prefix (self-serve observability) | 07 | `payments` (→ `payments_HighErrorRate`) |
| `{{XID_THRESHOLD}}` / `{{TEMP_THRESHOLD}}` | GPU auto-taint thresholds | 07 | `1` / `85` (°C) |
| `{{PD_ROUTING_KEY}}` / `{{SLACK_WEBHOOK}}` | PagerDuty service key / Slack webhook (ESO-sourced secrets) | 07 | *(secret)* |
| `{{AGENT_NAMESPACE}}` | AI-SRE K8s namespace | 09 | `ai-sre-system` |
| `{{HUB_CLUSTER}}` | AI-SRE monitored hub cluster | 09 | `platform` |
| `{{OMNISCIENCE_URL}}` / `{{OMNISCIENCE_TOKEN}}` | Knowledge-graph endpoint / token (mock by default — see §4) | 09 | real Neo4j+Qdrant service |
| `{{CLICKHOUSE_URL}}` / `{{METRICS_MCP_URL}}` / `{{RUNBOOK_MCP_URL}}` | AI-SRE store + MCP HTTP servers | 09 | in-namespace service URLs |
| `{{ARTIFACT_DIR}}` | AI-SRE collector mock output dir (**must contain no PII — see §4/§6**) | 09 | configurable path or disabled |
| `{{ANTHROPIC_API_KEY}}` / `{{SLACK_BOT_TOKEN}}` / `{{SLACK_APP_TOKEN}}` | AI-SRE LLM + Slack credentials (ESO-sourced) | 09 | *(secret)* |

### 3.9 Alias mapping (naming overlaps resolved)

Where two specs named the same thing differently, this table fixes the **canonical** name and
lists the alias. The domain specs are **not** edited; `SPEC-INDEX.md` carries the same table.

| Canonical | Alias(es) | Alias used by | Note |
|---|---|---|---|
| `{{LOG_ARCHIVE_ACCOUNT_ID}}` | `{{LOGARCHIVE_ACCOUNT_ID}}` | SPEC-01, SPEC-02 | Same log-archive account; two spellings. |
| `{{PRIMARY_DNS_PROVIDER}}` | `{{PRIMARY_DNS}}` | SPEC-02 (diagram) | Same active DNS provider. |
| `{{SECONDARY_DNS_PROVIDER}}` | `{{SECONDARY_DNS}}` | SPEC-02 (diagram) | Same standby DNS provider. |
| `{{GCP_PROJECT_ID}}` | `{{GCP_PROJECT}}` | SPEC-07 | Same GCP project. |
| `{{PROJECT}}` | `{{REPO}}` | SPEC-01 | Both default `platform-design` (project/repo slug in ARNs/tags). |

> **Not a clean alias — a genuine inconsistency (see §4 row D-INC):** `{{GITOPS_REPO}}` (SPEC-04,
> "one mono-repo holds `argocd/apps/envs/helm/kargo/`") vs `{{ARGOCD_CONFIG_REPO}}` (SPEC-06/10,
> "the `{{VCS_ORG}}/argocd` config repo the deploy pipeline PRs into"). The mono-repo model and the
> separate-config-repo model coexist in source; a rebuild must pick one and reconcile the placeholders.

---

## 4. As-built divergence register

The master list of "what to fix or decide before/while rebuilding". Each row is a **§7 item**
lifted verbatim-in-summary from a domain spec (45 rows). **Type** legend: `scaffold` = designed
but unwired/simulated/not deployed; `version-drift` = multiple pins/paths disagree; `config-bug` =
an actual misconfiguration or interface mismatch; `missing-target` = a control/DR path that does
not yet exist or is not hardened; `client-decision` = a "confirm intent" call the client must make.

| # | Spec | Summary | Type |
|---|---|---|---|
| D01 | 01 | DynamoDB locking is still the non-sandbox default (`use_lockfile=false` + `terraform-locks-*`); only sandbox uses S3-native locking — plan a migration. | client-decision |
| D02 | 01 | `_envcommon` module sources are path-based, not git-ref/registry-version pinned — a module edit hits every consumer. | version-drift |
| D03 | 02 | TGW is a per-region hub; cross-region peering (`tgw-peers` set in `account.hcl`) is only in the catalog *template* stack, not wired live. | scaffold |
| D04 | 02 | `dns-monitor`/`failover-controller` domain (`_health-check.example.com`) and probe region (`us-east-1`) are hard-coded to the sample. | config-bug |
| D05 | 03 | Cilium version is pinned in three places (GitOps `1.19.4` / TF module `1.17.1` / catalog unit `1.16.5`); `1.19.4` is the as-built truth — pin one source. | version-drift |
| D06 | 03 | Cluster Kubernetes version spread: `1.29` (dev agent-cluster) / `1.32` (catalog) / `1.34` (`_envcommon` target) — adopt `1.34` as the floor. | version-drift |
| D07 | 03 | Istio is declared (dev `agent-cluster` lists an `istio` unit + reference manual) but no Istio module ships; the as-built mesh is sidecarless. | scaffold |
| D08 | 03 | KEDA is deployed with zero `ScaledObject`s — the autoscaling contract exists without instances. | scaffold |
| D09 | 04 | P1 — Two ApplicationSet families exist; only Family A is wired into the bootstrap Kustomization, so the workload/Kargo plane never comes up on a clean bootstrap. | scaffold |
| D10 | 04 | P3 — `stage` (Family A/RollingSync/overlays) vs `staging` (Family B/Kargo) env-vocabulary drift silently no-ops mismatched files. | client-decision |
| D11 | 04 | P5 — Argo Rollouts machinery ships in `helm/app` + ADR-0014 "synced", but no Rollouts controller runs; keep `rollout.enabled:false`. | scaffold |
| D12 | 04 | P6 — Mixed repo-URL scheme (`https://` vs `git@`); SSH sources need a credential Secret or ArgoCD `ComparisonError`s. | config-bug |
| D13 | 05 | ESO `ClusterSecretStore` targets `{{SECRETS_REGION}}` (`eu-central-1`) ≠ primary infra region (`eu-west-1`) — deliberate isolation or drift? | client-decision |
| D14 | 06 | Soft-fail scanners (`tfsec`, Checkov/well-architected, `zizmor`, CodeQL) are advisory pending the hard-gate flip — a CRITICAL finding does not block today. | client-decision |
| D15 | 06 | `terraform-compliance` BDD runs with `--no-failure`/`\|\| true` (decorative); only native `terraform test` gates. | config-bug |
| D16 | 06 | Region inconsistency: IaC workflows hardcode `{{PRIMARY_REGION}}` (`eu-west-1`) while Terratest uses `us-east-1`. | config-bug |
| D17 | 06 | Two overlapping Terraform versions in CI — `1.14.8` (validate/plan) vs `~1.11`/`1.11.0` (compliance/terratest). | version-drift |
| D18 | 06 | `workflow_call` reusables live locally as mocks; in production they belong in `{{PLATFORM_WORKFLOWS_REPO}}`. | scaffold |
| D19 | 07 | ADR-0026 says "Alloy is the single pipeline hub" but the estate ships a standalone OTel Collector (+ Fluent Bit) and no Alloy — reconcile the ADR or the tool. | client-decision |
| D20 | 07 | ADR-0026 says "defer Pyroscope" but Pyroscope is fully deployed — the ADR is stale or the defer was overridden. | client-decision |
| D21 | 07 | Namespace drift: prometheus-stack Application targets `monitoring` while LGTM add-ons/datasources reference `observability` (and two Prometheus service names). | config-bug |
| D22 | 07 | VictoriaMetrics has two conflicting definitions — TF `VMCluster` (3/3/3, 500Gi, no RF) vs app Helm values (2/2/2, 100Gi, RF 2, full stack). | version-drift |
| D23 | 07 | Loki retention conflict: values say `8760h` (365d, PCI-DSS 10.7) vs a 30-day README claim — a 12× storage difference. | client-decision |
| D24 | 07 | Bare-metal auto-taint CronJob is the least hardened — raw manifest, no securityContext/limits/in-module RBAC. | missing-target |
| D25 | 07 | DCGM exporter image tag drift — TF pins `4.5.0-4.2.3-ubuntu22.04` vs app Helm `4.5.0-4.3.3-ubuntu22.04`. | version-drift |
| D26 | 07 | `observability-check` queries raw `DCGM_FI_DEV_*` names, but the gpu-inference-dcgm CSV remaps them to `dcgm_*` — the check fails for the wrong reason. | config-bug |
| D27 | 08 | The log-archive design is not wired — `terragrunt/log-archive/<region>/` has only `region.hcl`; Object Lock/KMS/CRR are designed but not instantiated. | scaffold |
| D28 | 08 | ML artifact store silently downgrades encryption — `kms_key_arn=""` default → AES256 (SSE-S3), not SSE-KMS; no Object Lock, no replication. | config-bug |
| D29 | 08 | `centralized-logging` lifecycle wiring mismatch — `lifecycle_glacier_days=365` is defined-but-unused; transition keys off the unset `lifecycle_ia_days` (90). | config-bug |
| D30 | 08 | Object Lock mode divergence — only the CloudTrail bucket is COMPLIANCE (true WORM); the general log archive is GOVERNANCE (admin can bypass). | client-decision |
| D31 | 08 | RDS has no cross-region DR — Multi-AZ only; no read replica / no cross-region snapshot copy; DR RDS is a fresh instance. | missing-target |
| D32 | 08 | DR account is a warm standby — `deletion_protection=false`, 7d retention, `enable_tgw_attachment=false` (not connected to the hub). | missing-target |
| D33 | 08 | Three divergent RDS code paths — `catalog/units/rds` (7.1.0/PG17.7) vs `terraform/modules/rds` (~>6.0/PG17) vs `rds-postgres` (raw/PG16); only the catalog unit is wired. | version-drift |
| D34 | 08 | `RequireManualAuth=false` by default — failover safety ships permissive; code comment says set `true` for prod initially. | client-decision |
| D35 | 09 | Agents are simulated — `_run_agent` and `incident` steps 2–6 fabricate findings; a naïve deploy posts plausible-but-empty advisories. | scaffold |
| D36 | 09 | Omniscience is a dry-run mock — default `sk_live_mock_token`/`OMNISCIENCE_DRY_RUN` writes a local JSON artifact, never touches Neo4j. | scaffold |
| D37 | 09 | Authoring leak in `collector.py` — mock handler hard-codes a personal home path + conversation UUID as the artifact dir; must be sanitized to `{{ARTIFACT_DIR}}`. | config-bug |
| D38 | 09 | Keyword retrieval ≠ semantic retrieval — `search_similar`/`suggest_runbook` do keyword overlap; `similarity_score` is a `1.0` placeholder. | scaffold |
| D39 | 09 | In-memory dedup/approval/rate-limit state with `replicas:2` — state is per-pod; caps are approximate under HA (externalize to Redis). | missing-target |
| D40 | 09 | Daily cost cap resets on a rolling 24h from process start (not UTC midnight) and is per-pod — budgeting is approximate. | missing-target |
| D41 | 09 | No committed ADR governs the AI-SRE — the advisory-only invariant and Omniscience integration have only the unverified `ADR-0055` draft. | missing-target |
| D42 | 10 | Two sources of truth for Volcano — chart values vs TF module disagree on `gang.enablePreemptable` and where Queue CRDs are created. | version-drift |
| D43 | 10 | CI/CD composite-action interface drift — ML workflows call `syft-sbom`/`cosign-sign` with `image:` but actions declare `image-ref:`; `argocd-tag-bump` inputs unpassed. | config-bug |
| D44 | 10 | Hardcoded identifiers in scaffold defaults — real VCS-org, CI-bot identity/email, placeholder-shaped tokens in actions/manifests/`.tftest.hcl` — scrub before sharing. | config-bug |
| D45 | 10 | `busybox` model-loader stub — the vLLM init container is a placeholder; ship a real weight-pull or pods start with no model. | scaffold |

> **D-INC (cross-spec inconsistency, not from a single §7):** `{{GITOPS_REPO}}` mono-repo model
> (SPEC-04) vs `{{ARGOCD_CONFIG_REPO}}` separate-config-repo model (SPEC-06/10) — reconcile the
> delivery-repo topology (see §3.9). Type: client-decision.

**Type tally:** scaffold ×11 · version-drift ×8 · config-bug ×11 · missing-target ×6 · client-decision ×9 (+ D-INC).

---

## 5. Recommendations register

The cross-spec "harden/decide before prod" backlog the writers flagged, deduplicated and
attributed. Work these alongside the divergence register (§4).

| # | Recommendation | Specs | Related divergences |
|---|---|---|---|
| R01 | **Author committed ADRs for the two ungoverned decisions** — the AI-SRE advisory-only invariant + Omniscience graph integration (only the unverified `ADR-0055` draft exists), and the Azure two-AKS ML federation (diagram-only, no ADR). | 09, 10 | D41 |
| R02 | **Reconcile the observability stack against ADR-0026** — ratify OTel-Collector-as-hub (or adopt Alloy) and the Pyroscope decision; do not run two of the same tier. | 07 | D19, D20 |
| R03 | **Flip advisory gates to blocking per the in-repo roadmap** — `tfsec`, Checkov/well-architected, `zizmor`, CodeQL, Access-Analyzer, `terraform-compliance` — once the finding backlog is remediated. | 06 | D14, D15 |
| R04 | **Pin one version per component, derive the rest** — Cilium (single source), cluster K8s (`1.34` floor), CI Terraform (`1.14.8`), Volcano, DCGM image, and the three RDS paths. | 03, 06, 07, 08, 10 | D05, D06, D17, D22, D25, D33, D42 |
| R05 | **Standardize workload identity for storage backends on Pod Identity** — the estate mixes Pod Identity (Thanos/YACE), IRSA (Loki/Pyroscope), and static S3 keys (Tempo); delete the static-key path. | 07 | — |
| R06 | **Wire the unwired scaffolds before relying on them** — cross-region TGW peering, the log-archive `centralized-logging` unit, Family-B ApplicationSets, real Cilium/K8s pins, and the AI-SRE SDK loop + Omniscience push. | 02, 04, 08, 09 | D03, D09, D27, D35, D36 |
| R07 | **Normalize the `stage`/`staging` env vocabulary** across Family-A/Family-B/overlays/Kargo and downstream tooling keyed on the canonical `stage` name. | 01, 04 | D10 |
| R08 | **Reconcile the delivery-repo topology** — mono-repo (`{{GITOPS_REPO}}`) vs separate config repo (`{{ARGOCD_CONFIG_REPO}}`); pick one and align placeholders + credentials (D12 SSH creds). | 04, 06, 10 | D12, D-INC |
| R09 | **Add cross-region RDS DR** — Multi-AZ covers AZ failure only; add a cross-region snapshot copy or read replica for regional DR, and finish the DR account (TGW attachment, deletion protection). | 08 | D31, D32 |
| R10 | **Set `RequireManualAuth=true` for prod** on the failover controller until failover is trusted end-to-end; understand the `MaxDailyFailovers=1` strand. | 02, 08 | D34, D04 |
| R11 | **Migrate state locking to S3-native** (`use_lockfile=true`), and **pin module sources by git-ref/registry version** instead of repo-root paths. | 01 | D01, D02 |
| R12 | **Externalize AI-SRE per-pod state to Redis** (dedup, approvals, rate-limit, cost cap) before scaling past `replicas:1` or tightening caps; standardize on structlog. | 09 | D39, D40 |
| R13 | **Decide the confirm-intent data-durability calls** — Object Lock GOVERNANCE→COMPLIANCE where regulation demands, Loki retention (30d vs 365d), and the ESO secrets-region isolation. | 05, 07, 08 | D13, D23, D30 |
| R14 | **Harden the remaining gaps** — bare-metal auto-taint pod (securityContext/limits/RBAC), the `observability-check` metric-name remap, the ML CI/CD composite-action interface, and the `busybox`/`model-loader` stubs. | 07, 10 | D24, D26, D43, D45 |
| R15 | **Scrub every authoring leak and hardcoded identifier** before sharing — the AI-SRE collector path/UUID, the ML scaffold defaults (VCS-org, CI-bot, tokens), and the sandbox account/bucket/IP. | 08, 09, 10 | D37, D44 |

---

## 6. Sanitization statement

Estate-wide, the following classes of real values were replaced with double-brace placeholders
(§3) while preserving the *shape* of each value, per `CONVENTIONS.md`: **AWS account IDs** (→
repeated-digit documentation shape, e.g. `000000000000`) and any **ARNs carrying an account ID**;
**organization / company / project slugs** (→ `{{ORG}}`, `{{PROJECT}}`, `{{VCS_ORG}}`); **DNS
domains and hostnames** (→ `{{DOMAIN}}`, `example.com`); **S3 bucket names** that embedded the
company name (→ `{{STATE_BUCKET}}`, `{{LOG_ARCHIVE_BUCKET}}`); **personal / root emails** (→
`aws+<role>@{{DOMAIN}}`); **IP addresses** (kept only as RFC-1918 / RFC-5737 documentation ranges;
real operator/office IPs → `{{OPERATOR_IP}}`); **CI-bot identities** (→ `{{CI_BOT_NAME}}` /
`{{CI_BOT_EMAIL}}`); **registrar/DNS-provider tokens, Slack/PagerDuty keys, LLM API keys, and cloud
credentials** (→ ESO-sourced secret placeholders); and **authoring leaks** such as personal home
paths and conversation UUIDs found in scaffold code (→ `{{ARTIFACT_DIR}}`, flagged as D37/D44 to
scrub). The specs also flag several source-side leaks a rebuild must still remove (sandbox account
ID/bucket/IP in `root.hcl`; hardcoded identifiers in ML scaffold defaults). **Note:** the name
**"Innovate Inc"** appearing in this estate's ADRs is a **fictional placeholder company**, not a
real client — treat it as sample text, not an identity to preserve.

---

## 7. How to use these specs for a client build

A pragmatic protocol. Do these in order; each step gates the next.

1. **Fill the placeholder registry first (§3).** Replace every `{{PLACEHOLDER}}` with the client's
   real values in one pass. Resolve the aliases (§3.9) to the canonical name. Keep the two
   account-ID sources of truth in sync (SPEC-01 §4.5). Nothing else should start until this table
   is complete.
2. **Resolve the divergence register's `client-decision` rows (§4).** These are not bugs — they are
   choices only the client can make: state-lock backend (D01), env vocabulary (D10), secrets-region
   isolation (D13), gate-blocking timeline (D14), observability-stack ratification (D19/D20),
   Loki retention (D23), Object-Lock mode (D30), failover auth (D34), and the delivery-repo topology
   (D-INC). Record each decision as a committed ADR (R01).
3. **Reconcile the `version-drift` rows to a single pin each (§4, R04)** before building — carrying
   three Cilium pins or three RDS paths into a fresh build reproduces the drift.
4. **Execute the specs in reading order (§2):** `01 → 02 → 03 → 05 → 04 → 06 → 07 → 08 → 10 → 09`.
   Build each domain from its **§4 implementation blueprint**, and treat each spec's **§8 acceptance
   checklist as the phase gate** — do not proceed to the next spec until the current one's checklist
   passes clean (e.g. "`terragrunt run --all plan` clean from an empty account", "ArgoCD app-of-apps
   syncs with zero manual steps", "advisory-only holds across all four enforcement layers").
5. **Wire the `scaffold` rows as explicit work items (§4, R06),** not assumptions — the ML/GPU
   surface, the AI-SRE agent loop, cross-region TGW peering, and the log-archive unit are designed
   but not deployed; a rebuild must actually build them.
6. **Run the recommendations register (§5) as the "harden before prod" backlog** — flip advisory
   gates to blocking, standardize workload identity, add cross-region RDS DR, externalize AI-SRE
   state, and scrub every authoring leak — before promoting anything to production.
7. **Keep sanitization a standing rule (§6).** Every client-specific value stays a placeholder in
   shared artifacts; verify no real account ID, ARN-with-ID, bucket, hostname, email, non-RFC-1918
   IP, or CI-bot identity survives before any spec or plan output is shared.

---

## 8. Dependencies

SPEC-00 owns the canonical placeholder registry (§3), the divergence register (§4), and the
recommendations register (§5); every domain spec's §5 parameterization table and §7 known-pitfalls
register against these. The domain specs' own `§9 Dependencies on other specs` sections define the
inter-spec edges; the reading order in §2 is the topological resolution of those edges.
