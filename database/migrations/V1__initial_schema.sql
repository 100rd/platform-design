-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. DNS Providers
CREATE TABLE dns_providers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) NOT NULL UNIQUE, -- cloudflare, route53, ns1
    type VARCHAR(20) NOT NULL CHECK (type IN ('active', 'standby')),
    api_endpoint VARCHAR(255),
    health_check_endpoints JSONB NOT NULL DEFAULT '[]', -- Array of nameserver IPs/hostnames
    status VARCHAR(20) NOT NULL DEFAULT 'healthy' CHECK (status IN ('healthy', 'degraded', 'failed')),
    last_check_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. DNS Zones
CREATE TABLE dns_zones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    domain_name VARCHAR(255) NOT NULL UNIQUE,
    registrar VARCHAR(50) NOT NULL, -- namecheap, godaddy, etc.
    current_ns_records JSONB NOT NULL DEFAULT '[]',
    desired_ns_records JSONB NOT NULL DEFAULT '[]',
    sync_status VARCHAR(20) NOT NULL DEFAULT 'synced' CHECK (sync_status IN ('synced', 'out-of-sync', 'syncing')),
    last_sync_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. Health Check Results
CREATE TABLE health_check_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_id UUID NOT NULL REFERENCES dns_providers(id),
    check_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    nameserver_address VARCHAR(255) NOT NULL,
    query_domain VARCHAR(255) NOT NULL,
    response_time_ms INTEGER NOT NULL,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    check_location VARCHAR(50) NOT NULL -- us-east-1, eu-west-1, etc.
);

CREATE INDEX idx_health_results_provider_ts ON health_check_results(provider_id, check_timestamp DESC);

-- 4. Failover Events
CREATE TABLE failover_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN ('failover_initiated', 'failover_completed', 'recovery_started', 'recovery_completed', 'failover_failed', 'recovery_failed')),
    provider_id UUID REFERENCES dns_providers(id),
    trigger_reason TEXT NOT NULL,
    old_ns_records JSONB,
    new_ns_records JSONB,
    initiated_by VARCHAR(50) NOT NULL DEFAULT 'auto', -- auto, manual:username
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB
);

-- 5. State Machine History
CREATE TABLE state_machine_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    domain_name VARCHAR(255) NOT NULL, -- Can link to dns_zones if strictly relational, but keeping loose for flexibility
    previous_state VARCHAR(50) NOT NULL,
    current_state VARCHAR(50) NOT NULL,
    transition_reason TEXT,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_state_history_domain_ts ON state_machine_history(domain_name, timestamp DESC);
