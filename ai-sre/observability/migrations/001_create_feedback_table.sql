-- Advisory feedback table for tracking human ratings on AI SRE advisories
-- Linked to advisory_id for correlation with audit_log entries
CREATE TABLE IF NOT EXISTS ai_sre.advisory_feedback (
    timestamp DateTime64(3),
    advisory_id String,
    agent_role LowCardinality(String),
    feedback_type LowCardinality(String),
    user_id String,
    channel String,
    message_ts String,
    INDEX idx_agent_role agent_role TYPE set(20) GRANULARITY 1
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (agent_role, timestamp)
TTL timestamp + INTERVAL 365 DAY;
