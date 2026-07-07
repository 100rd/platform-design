# SPEC-09 — Advisory AI-SRE System ("Platform Brain SRE" / PB-SRE)

> Portable blueprint for an **advisory-only, multi-agent AI Site-Reliability system** that
> observes a multi-cluster Kubernetes/GPU platform, investigates alerts with LLM agents, and
> posts human-actionable recommendations to Slack. It **never mutates infrastructure
> autonomously**; every write is gated behind a human approval. This spec captures the
> architecture, the defense-in-depth model that makes "advisory-only" an enforced property
> (not a promise), the knowledge/memory design, the MCP tool surface, the deployment shape,
> and the maturity ladder from advisory → gated execution.

---

## 1. Scope & non-goals

**In scope.** A Python service (`claude-agent-sdk` + FastAPI + MCP) that: ingests alerts from
Alertmanager/CloudWatch/Slack; deduplicates and enriches them; routes each to a specialized
LLM agent (incident, GPU-health, scaling, cost, capacity, chaos, on-call copilot,
runbook-automation, AWS-cloud) coordinated by an **Orchestrator** over a shared **Blackboard**;
consults a topology/knowledge graph ("Omniscience") and a ClickHouse incident memory; and emits
a structured advisory to Slack with approve/escalate/ack/snooze buttons. Includes the guardrail
stack, the runbook engine with approval workflow, meta-observability (self-SLOs, cost, accuracy
feedback), and the Kubernetes deployment manifests.

**Non-goals.** This spec does not define the underlying platform's observability stack
(VictoriaMetrics/ClickHouse/Grafana — see **SPEC-07**), the GitOps delivery machinery it opens
PRs against (see **SPEC-04**), or the cluster/network foundation it reads. It does not describe
building the Omniscience knowledge-graph service itself — PB-SRE is a *client* of that graph.

**Honesty boundary (read before building).** In this estate the system is a **faithfully
architected scaffold, partially simulated**. What is production-grade and real: routing,
deduplication, the guardrail classes, MCP server registry/config, Slack Block Kit + approval
handlers, all ClickHouse schemas, and every Kubernetes manifest (RBAC, NetworkPolicy,
ExternalSecret, hardened Deployments, meta-alerts). What is **stubbed/simulated** and must be
completed for a real deployment is called out explicitly in §4.7 and §7 — the actual Claude
Agent SDK tool-calling loop, embedding-based retrieval, live runbook execution, and the push to
the Omniscience graph (an in-process HTTP **mock** / dry-run today). Build the real loop into the
seams the scaffold already defines; do not assume the agents currently reason over live tools.

---

## 2. Architecture

### 2.1 The advisory loop: signal → enrich → advise → human

```
                      ┌──────────────────────── SIGNAL ───────────────────────┐
  Alertmanager/VMAlert │  CloudWatch alarms │  Slack /sre command or @mention  │
                      └───────────────┬────────────────────────────────────────┘
                                      ▼
                        ┌───────────────────────────┐   rate-limit 100/min
                        │  Ingestion API (FastAPI)   │   dedup 5-min window
                        │  /api/v1/alerts            │   (alertname:cluster:ns)
                        └───────────────┬────────────┘
                                        ▼  EnrichedAlert  ────────────── ENRICH
                        ┌───────────────────────────┐   resource utilization,
                        │  Orchestrator (Claude Opus)│   recent similar alerts,
                        │  route_alert() → role      │   topology subgraph
                        └───────────────┬────────────┘
                    writes Alert signal ▼            reads/writes findings
                        ┌───────────────────────────┐
                        │  Shared Blackboard         │◀──────────────┐
                        │  signals + subgraph +      │               │
                        │  findings(Advisory[])      │               │ ADVISE
                        └───────────────┬────────────┘               │
             ┌──────────────┬───────────┼───────────┬───────────┐    │
             ▼              ▼           ▼           ▼           ▼    │
        Incident       GPU-Health   Scaling     Cost/Cap    AWS-Cloud│  (Claude Sonnet workers)
        Response        agent       agent       agent        agent   │
             │  each agent calls MCP tools (READ-ONLY) through guardrails
             ▼
        ┌──────────────────────────────── MCP TOOL SURFACE ──────────────────────────────┐
        │ kubernetes-mcp(ro) │ aws-mcp(ro) │ metrics-mcp(ro) │ git-mcp(ro) │ runbook-mcp   │
        │ slack-mcp(rw, output-only) │  Omniscience graph API (topology/RAG, read)        │
        └────────────────────────────────────────────────────────────────────────────────┘
                                        ▼  aggregate_advisories()
                        ┌───────────────────────────┐
                        │  Slack Advisory (BlockKit) │   ──────────────────── HUMAN
                        │  Summary · RootCause(conf) │   [Approve Runbook]
                        │  Recommended actions       │   [Escalate][Ack][Snooze]
                        └───────────────┬────────────┘
                                        ▼ human clicks Approve
                        ┌───────────────────────────┐   15-min approval expiry
                        │  Runbook engine            │   auto steps: [DRY RUN]
                        │  approval_required → gate  │   privileged steps: human
                        └────────────────────────────┘
   Every hop is written immutably to ClickHouse `ai_sre.audit_log` / `ai_sre.agent_usage`.
```

The loop stops at **HUMAN** by design. No specialized agent writes to the cluster, cloud, or
Git without a human clicking Approve on a specific runbook step; the "GitOps remediation"
path (§4.6) produces a *Pull Request*, never a direct apply.

### 2.2 Component roles

| Component | Tech | Responsibility |
|---|---|---|
| **Ingestion API** | FastAPI, `ingestion/` | Accept Alertmanager/VMAlertmanager webhooks; rate-limit; dedup; enrich; route. |
| **Orchestrator** | Claude Opus, `agents/orchestrator/` | Label-based routing to a specialist; run agents on the Blackboard; aggregate advisories; cross-layer AWS enrichment. |
| **Blackboard** | dataclass, in-orchestrator | Shared canvas: `incident_signals`, `infrastructure_subgraph`, `findings: Advisory[]`. |
| **Specialist agents** | Claude Sonnet, `agents/{incident,gpu-health,scaling,cost,ops,cloud}/` | Domain RCA / recommendation; write `Advisory` back to the Blackboard. |
| **AWS-Cloud agent + collector** | `agents/cloud/` | Cross-layer EC2/EBS/TGW/GuardDuty correlation; background topology collector → Omniscience graph. |
| **MCP servers** | `mcp-servers/`, external | `metrics-mcp` (VictoriaMetrics/ClickHouse), `runbook-mcp` (runbook engine), plus stdio servers for k8s/aws/git/slack. |
| **Guardrails** | `guardrails/` | Tool allowlists + write-verb blocking, per-agent rate limits, circuit breaker, secret scanner, immutable audit. |
| **Memory** | ClickHouse, `memory/` | `incident_store` (history/RAG), `topology_store` (static YAML or Omniscience), `slo_store`. |
| **Omniscience** | Neo4j + Postgres + Qdrant (external) | Graph-of-record for platform topology + document/vector RAG. PB-SRE reads it; the collector writes it. |
| **Slack app** | slack-bolt, `slack/` | Deliver advisories; run approval button workflow; `/sre` slash commands; feedback reactions. |
| **Analytics/Observability** | ClickHouse + Prometheus, `analytics/`, `observability/` | Per-invocation usage/cost/findings; self-SLOs; human-accuracy feedback loop. |

### 2.3 Model tiering

`AgentModel.ORCHESTRATOR = claude-opus-4-*` (routing + synthesis, deeper reasoning, extended
thinking tokens tracked separately); `AgentModel.WORKER = claude-sonnet-4-*` (specialist
investigations). Temperature `0.0`, `max_tokens 4096` per agent definition.

---

## 3. Decision record

| Decision | Rationale | Trade-off accepted | Source |
|---|---|---|---|
| **Advisory-only** (agents never mutate; humans approve every write) | Trust, blast-radius control, auditability while LLM reliability matures | Slower MTTR than closed-loop automation; a human must be in the loop | System-wide invariant enforced by §4.2 defense-in-depth; on-call integration governed by `ADR-0040 SOC2 posture + ML on-call` |
| **Defense in depth, 4 layers** (MCP read-only → RBAC → NetworkPolicy → SDK guardrails) | No single control is trusted; the app-layer guardrail is the *last* line, not the only one | Redundant config to maintain across YAML + Python | `guardrails/read_only.py` header; `ADR-0011 break-glass / destroy protection` (least-privilege lineage) |
| **Orchestrator + specialists over a shared Blackboard** | Divide domain expertise; let the Opus orchestrator synthesize; keep worker context small/cheap | Coordination complexity; blackboard is in-memory per investigation | `agents/orchestrator/agent.py` |
| **Label-prefix routing** (e.g. `gpu_*`,`dcgm_*`→GPU-Health) | Deterministic, debuggable, zero-cost routing before spending tokens | Brittle to alert-name drift; unknown alerts fall to on-call copilot | `route_alert()` |
| **Cross-layer AWS enrichment by default** | Most K8s symptoms (pod crash, node NotReady) have an EC2/EBS/TGW root cause | Extra read calls per investigation | `AGENT_TOOL_PERMISSIONS` (most agents hold read-only `aws-mcp`) |
| **Omniscience graph-of-record for topology/RAG** (Neo4j+Qdrant), collector pushes state | One source of truth for dependencies + semantic runbook/incident retrieval | External dependency; **mocked in this estate** (§4.7) | `memory/topology_store.py`, `agents/cloud/collector.py`; graph model per `ADR-0055 logical-units: graph-of-record vs tag-projection` (see §9 caveat) |
| **ClickHouse for audit/analytics/incidents** | High-ingest, columnar, cheap TTL'd retention; already in platform observability stack | Eventually-consistent; SQL string-building needs escaping discipline | `analytics/`, `memory/incident_store.py`; **SPEC-07** |
| **Runbooks as Markdown + YAML frontmatter** with `auto_executable_steps` / `approval_required_steps` | Human-readable, Git-reviewable, powers a skills registry reused elsewhere | Parser must stay in lockstep with the doc format | `mcp-servers/runbooks/server.py`, `runbooks/*.md` |
| **Remediation via GitOps PR, never direct apply** | Keeps the declarative Git source of truth authoritative; review gate | Even approved fixes wait for PR merge/sync | `agents/ops/gitops_remediation.py`; **SPEC-04** |
| **Meta-monitoring: the AI-SRE has its own SLOs + circuit breaker + cost cap** | An observer that fails silently or runs away on cost is worse than none | Extra alert rules and daily cost ceiling to tune | `observability/slos.py`, `guardrails/rate_limiter.py`, `k8s/orchestrator/vmalert-rules.yaml` |

---

## 4. Implementation blueprint

### 4.1 Directory layout

```
ai-sre/
├── pyproject.toml            # py>=3.12, claude-agent-sdk>=0.1.56, fastapi, slack-bolt, clickhouse-connect
├── Dockerfile               # python:3.12-slim, non-root 'aisre', uvicorn orchestrator.main:app
├── agents/
│   ├── orchestrator/        # agent.py (routing+blackboard), config.py (roles/prompts/perms), mcp_registry.py, main.py (FastAPI)
│   ├── incident/            # multi-signal RCA specialist (+ investigation.py)
│   ├── gpu-health/  scaling/  cost/  capacity(ops/)  chaos(ops/)  oncall(ops/)  runbook(ops/)
│   └── cloud/               # agent.py, collector.py (topology→Omniscience), correlation.py, iam_policy.py
├── guardrails/              # read_only.py, rate_limiter.py, audit.py, secret_scanner.py, migrations/
├── ingestion/              # api.py, dedup.py, enrichment.py, router.py, models.py, migrations/
├── knowledge/              # cilium-bgp-issues.md, eks-upgrade-checklist.md, gpu-driver-updates.md, nccl-troubleshooting.md
├── memory/                 # incident_store.py, topology_store.py, slo_store.py, topology.yaml, models/, migrations/
├── mcp-servers/            # metrics/server.py, runbooks/server.py
├── observability/          # slos.py, feedback.py, cost_tracker.py, health.py, metrics.py, migrations/
├── analytics/              # tracker.py, client.py, slack_feedback.py, migrations/001_create_analytics_schema.sql
├── slack/                  # app.py, blocks.py, interactions.py, commands.py, channels.py, listeners.py
├── runbooks/               # <slug>.md with YAML frontmatter (symptoms + step gating)
└── k8s/                    # orchestrator/, slack-app/, ingestion/, mcp-servers/, clickhouse/
```

**Build order (what must exist before what):** ClickHouse DB + schemas (`analytics`, `guardrails`,
`memory`, `ingestion`, `observability` migrations) → MCP servers reachable → secrets in the
cloud secret manager → orchestrator/ingestion/slack Deployments → VMAlert meta-rules. The
topology collector and Omniscience are optional at first (static `memory/topology.yaml` is the
fallback).

### 4.2 The crown jewel — how "advisory-only" is *enforced*, layer by layer

Advisory-only is not a single flag; it is four independent controls, any one of which blocks a
write. From the module header of `guardrails/read_only.py`:

- **Layer 1 — MCP server config.** The Kubernetes MCP server runs with
  `KUBERNETES_MCP_READ_ONLY=true` and `KUBERNETES_MCP_REDACT_SECRETS=true`; the AWS MCP server is
  launched read-only. Servers refuse mutating calls before the agent's request reaches a cluster.

  ```python
  # agents/orchestrator/mcp_registry.py — DEFAULT_MCP_SERVERS (excerpt)
  "kubernetes-mcp": MCPServerConfig(
      name="kubernetes-mcp", transport=MCPTransport.STDIO, command="kubernetes-mcp-server",
      env={"KUBERNETES_MCP_READ_ONLY": "true", "KUBERNETES_MCP_REDACT_SECRETS": "true"},
      read_only=True),
  # slack-mcp and runbook-mcp are the only read_only=False servers (output + gated execution)
  ```

- **Layer 2 — Kubernetes RBAC.** Every agent runs under its own ServiceAccount, all bound to a
  single **read-only** ClusterRole. There is no Role anywhere that grants a write verb.

  ```yaml
  # k8s/orchestrator/rbac-per-agent.yaml — the ONLY ClusterRole, shared by all 9 agent SAs
  kind: ClusterRole
  metadata: { name: ai-sre-readonly }
  rules:
    - apiGroups: ["*"], resources: ["*"], verbs: ["get", "list", "watch"]
    - apiGroups: [""],  resources: ["pods/log"], verbs: ["get"]
  ```

- **Layer 3 — NetworkPolicy egress allowlist.** Orchestrator egress is pinned to the K8s API
  (443), VictoriaMetrics vmselect (8481), ClickHouse (8123), in-namespace MCP servers (8080/8081)
  and DNS. There is no open egress path to arbitrary cloud control-plane endpoints.

- **Layer 4 — Agent SDK guardrails (application, last line).** `ToolCallGuard.validate()` runs
  before every tool call and enforces three things: (a) the tool is in the agent-role allowlist;
  (b) the per-agent `max_tool_calls` budget is not exhausted; (c) in `read_only` mode, the call is
  not a write. Write detection scans both the **tool name** and **every string value in the tool
  input** for a verb in `WRITE_VERBS`:

  ```python
  # guardrails/read_only.py
  WRITE_VERBS = frozenset({"create","update","patch","delete","apply","cordon","uncordon",
      "drain","taint","scale","rollout","restart","insert","alter","drop","truncate"})

  def _is_write_operation(tool_name, tool_input=None) -> bool:
      if any(v in tool_name.lower() for v in WRITE_VERBS): return True
      for value in (tool_input or {}).values():
          if isinstance(value, str) and any(v in value.lower() for v in WRITE_VERBS):
              return True
      return False
  ```

  Per-role guardrails apply least privilege: `gpu-health` gets 6 read tools / 30 calls / 180s;
  the orchestrator and `oncall-copilot` get `["*"]`; **`runbook-automation` is the single role
  with `read_only=False`** (max 50 calls) — and even it can only reach the runbook engine, which
  itself gates privileged steps behind human approval (§4.5).

- **Prompt-level reinforcement.** Every system prompt restates the invariant (Orchestrator:
  *"Enforce advisory-only mode: you NEVER take autonomous actions… All write operations require
  explicit human approval via Slack"*; Chaos: *"You NEVER execute chaos experiments
  autonomously"*). Prompts are defense-in-depth reinforcement, **not** the enforcement — the four
  layers above hold even if the model is jailbroken.

- **Cross-cutting — audit + secret hygiene.** `AuditLogger` writes every tool call, Slack message,
  and approval/denial immutably to `ai_sre.audit_log` (input sanitized of `password/token/secret/…`
  keys first). `secret_scanner.scan_text()` redacts AWS keys, bearer/JWT/Slack/GitHub tokens,
  private keys, etc. from any agent output **before** it is posted to Slack or logged.

### 4.3 Ingestion, dedup, routing

`POST /api/v1/alerts` accepts Alertmanager/VMAlertmanager webhooks. Pipeline per alert:
rate-limit (sliding window, default 100/min → HTTP 429) → **dedup** (`AlertDeduplicator`,
key = `alertname:cluster:namespace`, 5-min window; increments a count and suppresses re-investigation
within the window; groups GC'd at 2× window) → enrich → `route_alert()`. Routing is prefix-based:

```
gpu_*, dcgm_*            → gpu-health          kube_pod_*, container_* → incident-response
node_*, kubelet_*        → capacity-planning   cilium_*, network_*     → incident-response
vllm_*                   → predictive-scaling  cost_*                  → cost-optimization
ec2_*|ebs_*|spot_*|guardduty_*|securityhub_*|aws_quota_*|cloudwatch_* → aws-cloud
(no match)               → oncall-copilot
```

For most K8s-layer alerts the orchestrator *also* runs the AWS-Cloud agent on the same Blackboard
(`_needs_aws_enrichment`) to rule out an infrastructure root cause.

### 4.4 Blackboard & advisory aggregation

`InvestigationContext` seeds a `Blackboard` with the alert signal, links `blackboard.findings`
to `context.advisories`, runs the routed specialist (and optionally AWS-Cloud) which read signals
+ `infrastructure_subgraph` and append `Advisory(agent_role, summary, root_cause, confidence,
recommended_actions[], severity)`. `aggregate_advisories()` synthesizes them into
`{status, advisories[], infrastructure_subgraph, aws_enrichment, timestamp}` for Slack.

### 4.5 Runbook engine & approval workflow

Runbooks are Markdown with YAML frontmatter; steps are gated in the frontmatter, not the body:

```markdown
---
id: gpu-node-unhealthy
category: gpu-health
severity: high
clusters: [gpu-inference, gpu-analysis]
auto_executable_steps: [1, 2, 3]      # diagnostics only
approval_required_steps: [4, 5]       # cordon / drain — human must click Approve
---
## Symptoms
- DCGM XID errors detected
## Steps
### Step 1: Gather GPU diagnostics (auto)
### Step 4: Cordon node (requires approval)
```

`runbook-mcp` `execute_runbook_step` returns `pending_approval` for approval-required steps, and
`[DRY RUN] Would execute: <cmd>` for auto steps (real execution is a seam to implement, §4.7).
The Slack side (`slack/blocks.build_runbook_approval_blocks` + `slack/interactions.py`) posts
Approve/Deny buttons; approvals **expire after 15 minutes** (`APPROVAL_EXPIRY_SECONDS = 900`) and
are logged with user id + timestamp. `suggest_runbook()` matches symptoms by keyword overlap
today (embedding search is the documented upgrade).

### 4.6 GitOps remediation (PR, not apply)

`agents/ops/gitops_remediation.py` proposes config fixes by: checkout `-B <branch>` → string-replace
in the target file → commit → optionally `git push` + `gh pr create` → restore original branch.
It **opens a PR for human review**; it never merges or applies. This is the only write path to the
platform and it flows through the same review gate as any human change (**SPEC-04**).

### 4.7 What is simulated (build these seams for a real deployment)

| Seam | Current state in estate | To productionize |
|---|---|---|
| Agent tool-calling loop | `orchestrator._run_agent` and `incident/agent.py` steps 2–6 **simulate** findings/subgraph; comments read *"In production, this would invoke the Claude Agent SDK"* | Wire `claude-agent-sdk` with `mcp_registry.to_sdk_config()` + per-role `AGENT_TOOL_PERMISSIONS`, run the real tool loop through `ToolCallGuard`. |
| Omniscience push | `collector.py` uses an in-process `httpx.MockTransport`; a "live" token `sk_live_mock_token` / `OMNISCIENCE_DRY_RUN` **forces dry-run**, writing the graph payload to a local JSON artifact instead of Neo4j | Point `OMNISCIENCE_URL`/`OMNISCIENCE_TOKEN` at the real graph service; remove the mock transport; the real `push_to_omniscience()` POST `/api/v1/graph/sync` already exists. |
| Retrieval | `incident_store.search_similar` and `runbook.suggest_runbook` use keyword matching; `similarity_score` is a placeholder `1.0` | Replace with Qdrant embedding search (GraphRAG). |
| Runbook execution | auto steps return `[DRY RUN] Would execute` | Implement the executor service behind the approval gate; keep audit logging. |

**Sanitization note (do not copy verbatim from the estate):** the mock handler in `collector.py`
writes its artifact to a hard-coded developer path containing a personal home directory and a
conversation UUID. That is an authoring leak — a real build MUST write to a configurable
`{{ARTIFACT_DIR}}` (or nothing) and must not embed any personal path or ID.

### 4.8 Data model (ClickHouse, `ai_sre` database)

MergeTree, monthly `PARTITION BY toYYYYMM(timestamp)`, **365-day TTL** across the board:

- `audit_log` — every tool call/message/approval (agent_id, agent_role, action, tool_name,
  sanitized tool_input, cluster, namespace, approved_by, tokens_used, duration_ms, error).
- `agent_usage` — one row per invocation: model, trigger_type, tokens_{input,output,thinking},
  `cost_usd`, tool_calls_count, `mcp_servers_used Array`, outcome, `finding_id` FK.
- `findings` — one row per discovered issue: finding_type, severity, category, affected_resource,
  root_cause_summary, confidence, recommendations[], `is_cross_layer` (K8s+AWS both present).
- `incidents` — history/RAG memory: symptoms[], root_cause(_category), resolution_steps[],
  `resolution_source`, TTD/TTM/TTR seconds. `capture_resolution()` back-fills human resolutions so
  agents can cite "how similar incidents were resolved" (the learning loop).
- `feedback` — human reaction → advisory quality (helpful / unhelpful / root_cause_correct/wrong).

### 4.9 Deployment (Kubernetes, namespace `ai-sre-system`)

- **Orchestrator Deployment**: `replicas: 2`; `runAsNonRoot`, `readOnlyRootFilesystem: true`,
  `allowPrivilegeEscalation: false`, `capabilities.drop:[ALL]`, `seccompProfile: RuntimeDefault`;
  `emptyDir` `/tmp` (100Mi); requests `1 CPU / 2Gi`, limits `2 CPU / 4Gi`; `ADVISORY_ONLY="true"`;
  `/healthz` liveness, `/readyz` readiness; Prometheus `/metrics` on 9090.
- **Secrets** via External Secrets Operator: `ExternalSecret` pulls `ANTHROPIC_API_KEY`,
  `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN` from the cloud secret manager (`ClusterSecretStore
  aws-secrets-manager`, `refreshInterval: 1h`). No secret is ever committed.
- **NetworkPolicy** (§4.2 Layer 3) constrains ingress (only in-namespace + monitoring) and egress
  (443/8481/8123/8080/8081/53 only).
- **Meta-monitoring** (`vmalert-rules.yaml`): `AISRESystemDown` (up==0 5m, critical),
  `AISREHighErrorRate` (>30% 5m), `AISRECircuitBreakerOpen`, `AISREHighLatency` (p95>120s),
  `AISREDailyCostHigh` (>$80) / `AISREDailyCostExceeded` (>$100, critical), `AISRELowAccuracy`
  (<60% for 24h), plus recorded 30-day availability/latency error-budget series.
- **Image** from `python:3.12-slim`, non-root `aisre` user, `uvicorn agents.orchestrator.main:app`.

### 4.10 Guardrail runtime limits (defaults)

`RateLimitConfig`: 10 investigations/agent/hour, 50 API calls/min, **$100/day cost cap**;
circuit breaker trips at 30% error rate over a 300s window (min 5 samples) → OPEN for 600s →
HALF_OPEN test. `can_proceed()` checks breaker → api rate → cost cap → per-agent rate in order.

---

## 5. Parameterization table

| Placeholder / knob | Meaning | Default in this estate | Resize guidance |
|---|---|---|---|
| `{{AGENT_NAMESPACE}}` | K8s namespace | `ai-sre-system` | Keep one namespace; NetworkPolicies assume it. |
| `{{PRIMARY_REGION}}` | region for clusters/secret store | `us-east-1` | Per SPEC-00. |
| `{{HUB_CLUSTER}}` / spoke clusters | monitored clusters | `platform` (hub); `gpu-inference`, `blockchain`, `gpu-analysis` (spokes) | Edit `memory/topology.yaml`; routing/prompts reference these names. |
| `{{ANTHROPIC_API_KEY}}` | LLM credential | secret `ai-sre/anthropic-api-key` | Rotate via secret manager; never inline. |
| `{{SLACK_BOT_TOKEN}}` / `{{SLACK_APP_TOKEN}}` | Slack app creds | secret `ai-sre/slack-credentials` | Socket-mode app token + bot token. |
| `{{OMNISCIENCE_URL}}` / `{{OMNISCIENCE_TOKEN}}` | knowledge-graph endpoint | `http://localhost:8000` / mock `sk_live_mock_token` | Point at real Neo4j+Qdrant service; unset token or `OMNISCIENCE_DRY_RUN=true` → mock. |
| `{{CLICKHOUSE_URL}}` | audit/analytics/incident store | `http://clickhouse.monitoring.svc.cluster.local:8123` | Shared with SPEC-07 stack. |
| `{{METRICS_MCP_URL}}` / `{{RUNBOOK_MCP_URL}}` | MCP HTTP servers | `…svc.cluster.local:8080` / `:8081` | In-namespace; NetworkPolicy pins these ports. |
| `{{ARTIFACT_DIR}}` | collector mock output dir | *(hard-coded dev path — sanitize!)* | Set explicitly or disable; must contain no PII (§4.7). |
| Orchestrator `replicas` | HA | `2` | Scale with alert volume; agents are stateless per investigation. |
| Resources | cpu/mem | req `1/2Gi`, lim `2/4Gi` | Opus context is memory-light; scale for concurrency. |
| `max_daily_cost_usd` | LLM cost cap | `100.0` | Primary cost lever; drives $80/$100 meta-alerts. |
| `max_investigations_per_hour` / `max_api_calls_per_minute` | rate limits | `10` / `50` | Raise carefully; watch circuit breaker. |
| Circuit breaker | threshold / window / cooldown | `0.30` / `300s` / `600s` | Lower threshold = more conservative auto-pause. |
| Dedup / approval windows | suppression / approval TTL | `300s` / `900s` | Approval TTL must exceed on-call human response time. |
| `max_tool_calls` per role | tool budget | 20–50 | Least privilege; unknown roles default to 20. |
| ClickHouse TTL | retention | `365 DAY` | Compliance-driven; shorten to cut storage. |

---

## 6. Best practices distilled

1. **Make "advisory-only" an enforced property, not a prompt.** Stack four independent controls
   (MCP read-only config → read-only RBAC → egress NetworkPolicy → app-layer `ToolCallGuard`).
   *Why:* a jailbroken or buggy model must still be physically unable to mutate; any single layer
   holding is sufficient.
2. **Scan tool *inputs*, not just tool *names*, for write verbs.** `_is_write_operation` inspects
   every string argument. *Why:* a read-named tool (`run_query`, `exec`) can still carry
   `DROP TABLE` or `kubectl delete` in its payload.
3. **Least privilege per agent role.** Give each role the *minimum* tool allowlist, call budget,
   and timeout; only `runbook-automation` is non-read-only, and only it reaches the gated engine.
   *Why:* compromise of one specialist cannot escalate across the platform.
4. **One ServiceAccount per agent, one shared read-only ClusterRole.** *Why:* per-SA identity gives
   you audit granularity in K8s API logs while a single Role guarantees no write verb exists to grant.
5. **Gate privileged runbook steps in frontmatter, with expiring approvals.** `auto_executable_steps`
   vs `approval_required_steps` + a 15-minute Slack approval TTL. *Why:* diagnostics run freely;
   destructive ops (cordon/drain) always need a fresh, attributable human click.
6. **Remediate through Git PRs, never direct apply.** *Why:* the declarative Git state stays the
   source of truth, and every fix — human or agent-proposed — passes the same review/sync gate.
7. **Give the observer its own SLOs, cost cap, and circuit breaker.** Self-SLOs (99% within 5 min,
   p95 first-advisory < 2 min, 80% helpful) + `$100/day` cap + auto-pause at 30% error rate.
   *Why:* an SRE bot that runs away on cost or fails silently is a liability; it must fail safe.
8. **Deduplicate before you spend a token.** 5-min `alertname:cluster:namespace` grouping stops an
   alert storm from launching N parallel investigations. *Why:* cost and rate-limit protection.
9. **Route deterministically before invoking a model.** Cheap label-prefix routing picks the
   specialist; unknown alerts fall back to the on-call copilot. *Why:* debuggable, free, and it
   keeps worker context tight.
10. **Correlate cross-layer by default.** Most K8s symptoms have an EC2/EBS/TGW/GuardDuty root
    cause; grant read-only `aws-mcp` to most agents and run the AWS-Cloud agent alongside. *Why:*
    "pod CrashLoopBackOff + EBS impaired → root cause is storage, not the app."
11. **Redact secrets on the way *out*.** `secret_scanner` runs on agent output before Slack/logs;
    `audit._sanitize_input` redacts sensitive keys before storage. *Why:* an LLM can echo a secret
    it read; stop it at the boundary.
12. **Audit everything immutably with TTL.** Every tool call/approval to `ai_sre.audit_log`
    (MergeTree, 365-day TTL). *Why:* post-incident forensics and compliance evidence.
13. **Close the accuracy loop with humans.** Map Slack reactions → helpful / root_cause_correct,
    emit per-agent `ai_sre_accuracy_ratio`, alert when <60%. *Why:* measured trust is the gate for
    advancing maturity (§7 ladder).
14. **Track thinking tokens and cost per invocation.** `agent_usage.tokens_thinking` + `cost_usd`.
    *Why:* Opus extended-thinking is a real cost driver; you cannot cap what you do not measure.
15. **Harden the pod.** Non-root, `readOnlyRootFilesystem`, drop ALL caps, seccomp RuntimeDefault,
    secrets via ESO. *Why:* the SRE agent reads the whole fleet — it is a high-value target.

### Maturity ladder (advisory → gated execution)

| Stage | Capability | Gate to advance |
|---|---|---|
| **0 Shadow** | Investigate + post advisories; humans act manually | — |
| **1 Advisory** *(this estate)* | Structured advisory + runbook *suggestions* + Approve/Escalate/Ack/Snooze; all writes manual | Sustained accuracy + audit coverage |
| **2 Gated execution** | `runbook-automation` executes **auto** steps; privileged steps still human-approved (15-min TTL) | Per-agent accuracy ≥ target; executor + audit hardened |
| **3 Supervised remediation** | Agent opens GitOps PRs automatically; human merges | PR-quality track record |
| **4 Closed-loop (out of scope here)** | Auto-apply pre-approved runbooks for narrow, reversible ops | Formal error-budget policy + rollback proof |

Advance a *capability at a time*, measured by the feedback loop — never flip the whole system to
autonomous.

---

## 7. Known pitfalls

1. **Prompt text is not a control.** Every prompt says "advisory-only," but only §4.2's four
   layers enforce it. Do not weaken any layer trusting the prompt.
2. **Write-verb substring matching is coarse.** `_is_write_operation` will flag a benign tool whose
   name/args merely contain `scale`/`patch`/`drop` (false positives) and could miss an obscure
   destructive verb (false negatives). Treat it as one layer of four; tune `WRITE_VERBS` per fleet.
3. **As-built divergence — agents are simulated in this estate.** `_run_agent` and `incident`
   steps 2–6 fabricate findings; a naïve deploy will post plausible-but-empty advisories. Wire the
   real SDK loop first (§4.7).
4. **As-built divergence — Omniscience is a dry-run mock.** With the default `sk_live_mock_token` /
   `OMNISCIENCE_DRY_RUN`, the collector writes a local JSON artifact and never touches Neo4j.
   Topology falls back to the static `memory/topology.yaml`. Provision the real graph before relying
   on dynamic dependencies.
5. **As-built divergence — authoring leak in `collector.py`.** The mock handler hard-codes a
   personal home path + a conversation UUID as its artifact directory — must be sanitized to
   `{{ARTIFACT_DIR}}` and never shipped (§4.7).
6. **ClickHouse SQL is string-built.** `incident_store` interpolates values with a hand-rolled
   `_escape`/`_array_str`. Keep inputs constrained and prefer parameter binding; agent-derived
   strings reach these queries.
7. **As-built divergence — keyword retrieval ≠ semantic retrieval.** `search_similar` and
   `suggest_runbook` do keyword overlap and return `similarity_score = 1.0` placeholder. Do not
   trust "related incidents" ranking until Qdrant embeddings are wired.
8. **Runbook parser is format-coupled.** `_parse_runbook` keys off exact `### Step N:` / `## Symptoms`
   headings and fenced code fences; a drifted doc silently yields zero steps. Lint runbooks in CI.
9. **As-built divergence — in-memory dedup / approval / rate-limit state.** `AlertDeduplicator`,
   `_pending_approvals`, and the sliding-window counters live in process, yet the Deployment targets
   `replicas: 2` — so state is per-pod and dedup/cost caps are approximate under HA. Externalize
   (Redis) before scaling out or tightening caps.
10. **As-built divergence — daily cost cap resets on a rolling 24h from process start**, not at UTC
    midnight, and is per-pod. Budgeting is approximate; the meta-alert on `ai_sre_daily_cost_usd` is
    the real backstop.
11. **Structlog vs stdlib logging mismatch.** Some modules call `logger.warning(..., key=val)`
    (structlog kwargs) on a stdlib `logging` logger; verify a single logging config or messages will
    be malformed. Standardize on structlog across services.
12. **NetworkPolicy egress `0.0.0.0/0:443`** is required for the K8s API but is broad; pair with the
    read-only RBAC (Layer 2) so wide egress cannot become a write path.
13. **As-built divergence — no committed ADR governs this system.** The advisory-only invariant and
    the Omniscience graph integration are the two most consequential decisions here yet have no
    dedicated, committed ADR in `docs/adrs/` (only the unverified `ADR-0055` draft, §9). A rebuild
    should author a committed ADR for both before promoting past Stage 1 of the maturity ladder.

---

## 8. Acceptance checklist

- [ ] `kubectl auth can-i --list` for every `ai-sre-*` ServiceAccount shows **only** `get/list/watch`
      (+`pods/log:get`); no verb grants create/update/patch/delete anywhere.
- [ ] With `KUBERNETES_MCP_READ_ONLY=true`, a deliberately requested write tool is refused at the
      MCP layer **and** blocked by `ToolCallGuard.validate()` (unit test on `_is_write_operation`).
- [ ] `ToolCallGuard` blocks a tool outside the role allowlist, and blocks once `max_tool_calls` is
      exceeded (per-role limits from `DEFAULT_GUARDRAILS`).
- [ ] An Alertmanager webhook storm of identical alerts within 5 min produces exactly **one**
      investigation (`alerts_deduplicated_total` increments).
- [ ] `route_alert()` maps each documented prefix to the correct role; an unknown alert routes to
      `oncall-copilot`.
- [ ] A runbook `approval_required` step returns `pending_approval` and posts Approve/Deny buttons;
      an approval older than 15 min is rejected; approve/deny is written to `ai_sre.audit_log` with
      user id + timestamp.
- [ ] `secret_scanner.scan_text()` redacts AWS key / bearer / JWT / Slack / GitHub token / private
      key patterns; advisory output containing a secret is redacted before Slack.
- [ ] All five migrations apply cleanly; `ai_sre.audit_log`, `agent_usage`, `findings`, `incidents`,
      `feedback` exist with monthly partitions + 365-day TTL.
- [ ] Orchestrator pod runs non-root, `readOnlyRootFilesystem`, caps dropped; `ExternalSecret`
      materializes `ai-sre-secrets`; no secret in any manifest or image.
- [ ] Meta-alerts fire in test: kill orchestrator → `AISRESystemDown`; force error rate >30% →
      `AISREHighErrorRate` then `AISRECircuitBreakerOpen`; push cost >$100 → `AISREDailyCostExceeded`.
- [ ] Self-SLO report renders (availability / p95 latency / accuracy) and `ai_sre_accuracy_ratio`
      updates from a simulated Slack feedback reaction.
- [ ] Collector with a real `{{OMNISCIENCE_URL}}`/token performs a live `POST /api/v1/graph/sync`
      (mock transport disabled); with the mock, it writes only to a sanitized `{{ARTIFACT_DIR}}`.
- [ ] GitOps remediation opens a **PR** (never a direct apply/merge) and restores the original branch.

---

## 9. Dependencies on other specs

- **SPEC-07 (Observability)** — the AI-SRE **consumes** this stack: VictoriaMetrics (alerts source
  via VMAlert webhooks + `query_metrics`), ClickHouse (log search + all `ai_sre.*` tables), and it
  **produces** its own Prometheus metrics + VMAlert meta-rules that live alongside platform alerting.
  Related: `ADR-0026 observability target architecture`, `ADR-0038 ML observability / drift→PagerDuty`,
  `ADR-0039 self-serve observability`.
- **SPEC-04 (Delivery / GitOps)** — the remediation path opens Pull Requests into the GitOps repo;
  approved fixes reconcile through the platform's ArgoCD/CI, not through the agent.
- **SPEC-00 (Overview)** — source of `{{ORG}}`, `{{PRIMARY_REGION}}`, and secret-store placeholders;
  register any recurring placeholder introduced here (`{{OMNISCIENCE_URL}}`, `{{AGENT_NAMESPACE}}`).
- **On-call governance** — `ADR-0040 SOC2 posture + ML on-call` frames how advisories integrate with
  the human on-call rotation (PagerDuty/Slack) and the control-to-evidence audit expectation the
  `audit_log` satisfies.

> **ADR caveat (honesty).** The graph-of-record model behind Omniscience corresponds to
> `ADR-0055 logical-units: graph-of-record vs tag-projection`, but that ADR is **not present in the
> `docs/adrs/` snapshot** this spec was reverse-engineered from (it exists only as an untracked
> draft in the source repo). Its content is therefore **unverified here** — cite it, but confirm
> against the committed ADR before treating it as authoritative. No other ADR in the committed set
> is dedicated to the AI-SRE system; the citations above are the governing adjacent decisions.
