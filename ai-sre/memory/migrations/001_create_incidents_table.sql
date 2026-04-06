-- Create incidents table for agent memory / knowledge base
-- Run against ClickHouse: clickhouse-client --multiquery < 001_create_incidents_table.sql

CREATE DATABASE IF NOT EXISTS ai_sre;

CREATE TABLE IF NOT EXISTS ai_sre.incidents
(
    incident_id UUID,
    timestamp DateTime64(3),
    title String,
    cluster String,
    namespace String DEFAULT '',
    severity LowCardinality(String),
    alertnames Array(String),
    symptoms Array(String),
    root_cause String DEFAULT '',
    root_cause_category LowCardinality(String) DEFAULT '',
    resolution_steps Array(String),
    resolution_source LowCardinality(String) DEFAULT 'agent',
    affected_services Array(String),
    related_alerts Array(String),
    time_to_detect_seconds Float32 DEFAULT 0,
    time_to_mitigate_seconds Float32 DEFAULT 0,
    time_to_resolve_seconds Float32 DEFAULT 0,
    metrics_snapshot String DEFAULT '{}',
    postmortem_url String DEFAULT '',
    tags Array(String),
    INDEX idx_cluster cluster TYPE set(20) GRANULARITY 1,
    INDEX idx_root_cause_category root_cause_category TYPE set(50) GRANULARITY 1,
    INDEX idx_symptoms symptoms TYPE bloom_filter(0.01) GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (cluster, timestamp)
TTL timestamp + INTERVAL 365 DAY;
