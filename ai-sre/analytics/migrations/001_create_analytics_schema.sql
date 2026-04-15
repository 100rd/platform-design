-- AI SRE Analytics Schema
-- ClickHouse tables for agent usage, findings, feedback, and tool calls
-- All tables use MergeTree with monthly partitioning and 365-day TTL

CREATE DATABASE IF NOT EXISTS ai_sre;

-- ─────────────────────────────────────────────────────────────────────────────
-- Table 1: agent_usage  (one row per agent invocation)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_sre.agent_usage
(
    -- Identity
    invocation_id        UUID,
    timestamp            DateTime64(3),

    -- Agent info
    agent_role           LowCardinality(String),  -- incident_response, gpu_health, …
    model                LowCardinality(String),   -- claude-opus-4-*, claude-sonnet-4-*

    -- Trigger
    trigger_type         LowCardinality(String),   -- alert, slack_command, slack_mention, scheduled, cross_agent
    trigger_source       String,                   -- alertname, slash command name, etc.

    -- Context
    cluster              LowCardinality(String),
    namespace            String,

    -- Performance
    duration_ms          UInt32,
    tokens_input         UInt32,
    tokens_output        UInt32,
    tokens_thinking      UInt32,                   -- extended-thinking tokens (Opus)
    cost_usd             Float64,

    -- Tool usage
    tool_calls_count     UInt16,
    mcp_servers_used     Array(LowCardinality(String)),
    tools_used           Array(String),

    -- Outcome
    outcome              LowCardinality(String),   -- advisory_generated, escalated, error, no_action, timeout
    error_message        Nullable(String),
    finding_id           Nullable(UUID),           -- FK to findings if a finding was generated

    INDEX idx_agent_role  agent_role  TYPE set(20) GRANULARITY 1,
    INDEX idx_cluster     cluster     TYPE set(10) GRANULARITY 1,
    INDEX idx_outcome     outcome     TYPE set(10) GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (agent_role, timestamp)
TTL timestamp + INTERVAL 365 DAY;


-- ─────────────────────────────────────────────────────────────────────────────
-- Table 2: findings  (one row per issue discovered by an agent)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_sre.findings
(
    -- Identity
    finding_id                UUID,
    timestamp                 DateTime64(3),
    invocation_id             UUID,                        -- FK to agent_usage

    -- Classification
    finding_type              LowCardinality(String),
    -- incident | gpu_degradation | cost_waste | capacity_risk |
    -- security_finding | scaling_recommendation | config_drift | performance_degradation
    severity                  LowCardinality(String),      -- critical | high | medium | low | info
    category                  LowCardinality(String),
    -- deployment | hardware | config | capacity | network | security | cost | performance

    -- Context
    cluster                   LowCardinality(String),
    namespace                 String,
    affected_resource         String,                      -- node name, deployment name, etc.
    affected_resource_type    LowCardinality(String),      -- node | pod | deployment | service | ec2 | ebs

    -- Analysis
    root_cause_summary        String,
    confidence                LowCardinality(String),      -- high | medium | low
    recommendations           Array(String),
    evidence_sources          Array(String),               -- metrics | logs | events | git | aws

    -- Cross-layer signals
    k8s_signals_count         UInt8,
    aws_signals_count         UInt8,
    is_cross_layer            Bool,                        -- true when both K8s + AWS signals involved

    -- Resolution tracking
    status                    LowCardinality(String),      -- open | acknowledged | resolved | false_positive
    resolution_type           Nullable(LowCardinality(String)),
    -- manual_fix | auto_resolved | runbook_executed | false_positive
    resolved_by               Nullable(String),            -- slack user ID or "auto"
    resolved_at               Nullable(DateTime64(3)),

    -- SRE timing signals
    alert_fired_at            Nullable(DateTime64(3)),
    agent_started_at          DateTime64(3),
    advisory_posted_at        DateTime64(3),
    acknowledged_at           Nullable(DateTime64(3)),
    resolved_at_final         Nullable(DateTime64(3)),

    -- Computed durations (seconds)
    time_to_detect_sec        Nullable(Float32),           -- alert_fired → agent_started
    time_to_advise_sec        Float32,                     -- agent_started → advisory_posted
    time_to_acknowledge_sec   Nullable(Float32),           -- alert_fired → acknowledged
    time_to_resolve_sec       Nullable(Float32),           -- alert_fired → resolved

    INDEX idx_finding_type  finding_type  TYPE set(20) GRANULARITY 1,
    INDEX idx_severity      severity      TYPE set(5)  GRANULARITY 1,
    INDEX idx_cluster_f     cluster       TYPE set(10) GRANULARITY 1,
    INDEX idx_status        status        TYPE set(5)  GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (cluster, finding_type, timestamp)
TTL timestamp + INTERVAL 365 DAY;


-- ─────────────────────────────────────────────────────────────────────────────
-- Table 3: feedback  (one row per human reaction/button click)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_sre.feedback
(
    timestamp            DateTime64(3),
    finding_id           UUID,                    -- FK to findings
    invocation_id        UUID,                    -- FK to agent_usage

    -- Feedback
    feedback_type        LowCardinality(String),  -- reaction | button | slash_command
    feedback_value       LowCardinality(String),
    -- helpful | not_helpful | correct_rca | wrong_rca | false_positive | partially_correct
    feedback_by          String,                  -- Slack user ID
    feedback_comment     Nullable(String),

    -- Context
    agent_role           LowCardinality(String),
    cluster              LowCardinality(String)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (agent_role, timestamp)
TTL timestamp + INTERVAL 365 DAY;


-- ─────────────────────────────────────────────────────────────────────────────
-- Table 4: tool_calls  (one row per MCP tool call within an invocation)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_sre.tool_calls
(
    timestamp            DateTime64(3),
    invocation_id        UUID,
    agent_role           LowCardinality(String),

    tool_name            String,
    mcp_server           LowCardinality(String),
    duration_ms          UInt32,
    success              Bool,
    error_message        Nullable(String),
    result_size_bytes    UInt32
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (mcp_server, tool_name, timestamp)
TTL timestamp + INTERVAL 180 DAY;


-- ─────────────────────────────────────────────────────────────────────────────
-- Materialized view 1: hourly agent usage summary
-- ─────────────────────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS ai_sre.agent_usage_hourly
ENGINE = SummingMergeTree()
ORDER BY (agent_role, cluster, hour)
POPULATE
AS SELECT
    agent_role,
    cluster,
    toStartOfHour(timestamp)          AS hour,
    count()                           AS invocations,
    sum(tokens_input + tokens_output) AS total_tokens,
    sum(tokens_thinking)              AS total_thinking_tokens,
    sum(cost_usd)                     AS total_cost,
    avg(duration_ms)                  AS avg_duration_ms,
    countIf(outcome = 'error')        AS errors,
    countIf(outcome = 'advisory_generated') AS advisories_generated
FROM ai_sre.agent_usage
GROUP BY agent_role, cluster, hour;


-- ─────────────────────────────────────────────────────────────────────────────
-- Materialized view 2: daily findings summary
-- ─────────────────────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS ai_sre.findings_daily
ENGINE = SummingMergeTree()
ORDER BY (cluster, finding_type, severity, day)
POPULATE
AS SELECT
    cluster,
    finding_type,
    severity,
    toDate(timestamp)                       AS day,
    count()                                 AS findings_count,
    avg(time_to_advise_sec)                 AS avg_time_to_advise_sec,
    avg(time_to_resolve_sec)                AS avg_time_to_resolve_sec,
    countIf(status = 'resolved')            AS resolved_count,
    countIf(status = 'false_positive')      AS false_positive_count,
    countIf(status = 'acknowledged')        AS acknowledged_count,
    countIf(is_cross_layer = true)          AS cross_layer_count
FROM ai_sre.findings
GROUP BY cluster, finding_type, severity, day;


-- ─────────────────────────────────────────────────────────────────────────────
-- Materialized view 3: daily accuracy summary
-- ─────────────────────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS ai_sre.feedback_daily
ENGINE = SummingMergeTree()
ORDER BY (agent_role, cluster, day)
POPULATE
AS SELECT
    agent_role,
    cluster,
    toDate(timestamp)                          AS day,
    count()                                    AS feedback_count,
    countIf(feedback_value = 'helpful')        AS helpful_count,
    countIf(feedback_value = 'not_helpful')    AS not_helpful_count,
    countIf(feedback_value = 'correct_rca')    AS correct_rca_count,
    countIf(feedback_value = 'wrong_rca')      AS wrong_rca_count,
    countIf(feedback_value = 'false_positive') AS false_positive_count
FROM ai_sre.feedback
GROUP BY agent_role, cluster, day;


-- ─────────────────────────────────────────────────────────────────────────────
-- Materialized view 4: daily tool call summary
-- ─────────────────────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS ai_sre.tool_calls_daily
ENGINE = SummingMergeTree()
ORDER BY (mcp_server, tool_name, day)
POPULATE
AS SELECT
    mcp_server,
    tool_name,
    toDate(timestamp)          AS day,
    count()                    AS call_count,
    countIf(success = true)    AS success_count,
    countIf(success = false)   AS error_count,
    avg(duration_ms)           AS avg_duration_ms,
    sum(result_size_bytes)     AS total_result_bytes
FROM ai_sre.tool_calls
GROUP BY mcp_server, tool_name, day;
