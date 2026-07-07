# SPEC-INDEX — Platform Specs

Portable, reverse-engineered specs for an AWS-primary multi-account IaC + Kubernetes/GPU
platform. A senior platform team can rebuild the estate for a new client from these files
alone. **Start with `SPEC-00-overview.md`** (owns the canonical placeholder registry + the
cross-spec divergence/recommendation registers), then read in the order below.

## Files

| File | Description | Lines |
|---|---|---|
| `CONVENTIONS.md` | Authoring rules: audience, parameterization, sanitization, per-spec structure | 68 |
| `SPEC-00-overview.md` | **Start here** — platform overview, canonical placeholder registry, as-built divergence register (45), recommendations register, sanitization statement, client-build protocol | 390 |
| `SPEC-01-foundation-iac.md` | Foundation: AWS Org + 8-OU tree, ~11-account topology, Terragrunt/`_envcommon`/`catalog`, TF-only state bootstrap, version pins, ADR-0028 tagging | 523 |
| `SPEC-02-network-dns.md` | Network & DNS: hub-spoke Transit Gateway, deterministic VPC CIDRs, deny-by-default segmentation, Route 53 Resolver, dual-provider octoDNS + health monitor + registrar failover | 608 |
| `SPEC-03-compute-clusters.md` | Compute: EKS + Cilium (eBPF/ENI) + Karpenter on Bottlerocket + KEDA/HPA, Pod Identity, per-workload cluster split | 657 |
| `SPEC-04-delivery-gitops.md` | Delivery: ArgoCD app-of-apps + ApplicationSets, Kargo promotion graph, the generic `helm/app` chart, PreSync migrations | 610 |
| `SPEC-05-security.md` | Security: SCP/RCP/EC2-declarative guardrails, audit/logging accounts, Pod-Identity ABAC, ESO+KMS+rotation, admission control, supply-chain gates | 551 |
| `SPEC-06-cicd-quality.md` | CI/CD: GitHub Actions estate (34 wf + 10 actions), IaC loop as CI, keyless OIDC, supply chain, drift detection, Infracost, GitLab port | 604 |
| `SPEC-07-observability.md` | Observability: LGTM (Prom+Thanos/Loki/Tempo/Pyroscope), VictoriaMetrics GPU variant, DCGM + auto-taint, ML drift, Pyrra SLOs, Alertmanager, OpenCost | 783 |
| `SPEC-08-resilience-data.md` | Resilience/DR: `failover-controller`, warm-standby DR account, RDS HA, Velero, immutable log archive, state DR, failure-mode matrix, RTO/RPO tiers | 651 |
| `SPEC-09-ai-sre.md` | Advisory AI-SRE: multi-agent system, four-layer advisory-only enforcement, runbook/approval engine, ClickHouse memory, MCP surface, meta-observability | 525 |
| `SPEC-10-ml-workloads.md` | ML/GPU: inference serving (Gateway API Inference Extension + EPP + vLLM on DRA), GPU capacity strategy, Airflow→MLflow→Kargo lifecycle, multi-cloud pattern | 682 |

## Reading / execution order

```
SPEC-00 → 01 → 02 → 03 → 05 → 04 → 06 → 07 → 08 → 10 → 09
overview  found. net  comp  sec  deliv ci/cd obs  resil ml   ai-sre
```

Foundation first; network before compute; **security before delivery** (secrets/admission are
prerequisites delivery references); CI/CD guards it all; observability is delivered via GitOps;
resilience layers on the running stack; ML reuses everything; the advisory AI-SRE is last
(consumes signals, mutates nothing). Full justification in `SPEC-00-overview.md` §2. Use each
spec's **§8 acceptance checklist** as the gate before moving to the next.

## Placeholder aliases (resolved in `SPEC-00-overview.md` §3.9)

The domain specs are not edited; where two specs named the same thing differently, the canonical
name and its alias are:

| Canonical | Alias | Alias used by |
|---|---|---|
| `{{LOG_ARCHIVE_ACCOUNT_ID}}` | `{{LOGARCHIVE_ACCOUNT_ID}}` | SPEC-01, SPEC-02 |
| `{{PRIMARY_DNS_PROVIDER}}` | `{{PRIMARY_DNS}}` | SPEC-02 |
| `{{SECONDARY_DNS_PROVIDER}}` | `{{SECONDARY_DNS}}` | SPEC-02 |
| `{{GCP_PROJECT_ID}}` | `{{GCP_PROJECT}}` | SPEC-07 |
| `{{PROJECT}}` | `{{REPO}}` | SPEC-01 |

> Unresolved inconsistency (a decision, not a clean alias): `{{GITOPS_REPO}}` (SPEC-04 mono-repo
> model) vs `{{ARGOCD_CONFIG_REPO}}` (SPEC-06/10 separate-config-repo model) — see SPEC-00 §3.9 / D-INC.
