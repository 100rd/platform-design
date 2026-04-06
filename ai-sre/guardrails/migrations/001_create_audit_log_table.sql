-- Audit log table for AI SRE agent actions
-- Stores every MCP tool call, Slack message, and approval/denial immutably
CREATE TABLE IF NOT EXISTS ai_sre.audit_log (
    timestamp DateTime64(3),
    agent_id String,
    agent_role LowCardinality(String),
    action String,
    tool_name String,
    tool_input String,
    tool_output_summary String,
    cluster String,
    namespace String,
    approved_by Nullable(String),
    approval_timestamp Nullable(DateTime64(3)),
    tokens_used UInt32,
    duration_ms UInt32,
    error Nullable(String)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (agent_role, timestamp)
TTL timestamp + INTERVAL 365 DAY;
