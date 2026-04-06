-- Create ai_sre database and alerts table for alert history
-- Run against ClickHouse: clickhouse-client --multiquery < 001_create_alerts_table.sql

CREATE DATABASE IF NOT EXISTS ai_sre;

CREATE TABLE IF NOT EXISTS ai_sre.alerts
(
    alert_id UUID,
    timestamp DateTime64(3),
    alertname String,
    cluster String,
    namespace String DEFAULT '',
    severity LowCardinality(String),
    status LowCardinality(String),
    labels Map(String, String),
    enrichment_data String,
    agent_advisory String DEFAULT '',
    resolution String DEFAULT '',
    ttfr_seconds Float32 DEFAULT 0,
    INDEX idx_alertname alertname TYPE set(100) GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (cluster, alertname, timestamp)
TTL timestamp + INTERVAL 90 DAY;
