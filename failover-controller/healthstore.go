package main

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// ProviderHealth holds the computed health score and metadata for a DNS provider.
type ProviderHealth struct {
	ProviderID   string
	ProviderName string
	Score        float64   // 0.0 to 1.0
	CheckCount   int       // number of checks in the scoring window
	LastCheck    time.Time // timestamp of the most recent check
}

// HealthStore abstracts health score retrieval so the state machine
// is decoupled from the underlying storage implementation.
type HealthStore interface {
	// GetProviderHealthScores returns the current health score for every
	// active provider, computed over the given lookback window.
	GetProviderHealthScores(ctx context.Context, window time.Duration) ([]ProviderHealth, error)

	// GetProviderHealthHistory returns the last N health scores for a
	// specific provider, ordered newest-first. This is used by the
	// degraded-state handler to confirm consecutive failures.
	GetProviderHealthHistory(ctx context.Context, providerID string, count int) ([]float64, error)
}

// PostgresHealthStore queries the dns-monitor database tables
// (dns_providers, health_check_results) to compute provider health.
type PostgresHealthStore struct {
	db *sql.DB
}

// NewPostgresHealthStore creates a HealthStore backed by the same Postgres
// database that the dns-monitor writes to. The caller passes in a *sql.DB
// that is already connected (typically the same connection used by Storage).
func NewPostgresHealthStore(db *sql.DB) *PostgresHealthStore {
	return &PostgresHealthStore{db: db}
}

// GetProviderHealthScores computes a health score for every active provider
// using the same formula as the dns-monitor:
//
//	score = (success_rate * 0.6) + (latency_score * 0.3) + (consistency * 0.1)
//
// The query aggregates health_check_results from the last `window` duration.
// Scores are normalized to the 0.0-1.0 range (the monitor uses 0-100
// internally but we normalize here for cleaner threshold comparisons).
func (s *PostgresHealthStore) GetProviderHealthScores(ctx context.Context, window time.Duration) ([]ProviderHealth, error) {
	query := `
		SELECT
			p.id,
			p.name,
			COUNT(r.id) AS check_count,
			MAX(r.check_timestamp) AS last_check,
			-- success rate: fraction of checks that succeeded
			COALESCE(AVG(CASE WHEN r.success THEN 1.0 ELSE 0.0 END), 0) AS success_rate,
			-- average response time in ms (only successful checks)
			COALESCE(AVG(CASE WHEN r.success THEN r.response_time_ms ELSE NULL END), 1000) AS avg_latency_ms
		FROM dns_providers p
		LEFT JOIN health_check_results r
			ON r.provider_id = p.id
			AND r.check_timestamp > $1
		WHERE p.status != 'failed'
		GROUP BY p.id, p.name
	`

	cutoff := time.Now().Add(-window)
	rows, err := s.db.QueryContext(ctx, query, cutoff)
	if err != nil {
		return nil, fmt.Errorf("query provider health scores: %w", err)
	}
	defer rows.Close()

	var results []ProviderHealth
	for rows.Next() {
		var ph ProviderHealth
		var successRate, avgLatencyMs float64
		var lastCheck sql.NullTime

		if err := rows.Scan(&ph.ProviderID, &ph.ProviderName, &ph.CheckCount, &lastCheck, &successRate, &avgLatencyMs); err != nil {
			return nil, fmt.Errorf("scan provider health row: %w", err)
		}

		if lastCheck.Valid {
			ph.LastCheck = lastCheck.Time
		}

		// Latency score: 1.0 if < 50ms, 0.0 if > 1000ms, linear between.
		latencyScore := 1.0
		if avgLatencyMs >= 1000 {
			latencyScore = 0.0
		} else if avgLatencyMs > 50 {
			latencyScore = 1.0 - (avgLatencyMs-50.0)/950.0
		}

		// Consistency score: simplified to 1.0 here (matching the monitor's
		// placeholder). A real implementation would measure variance.
		consistencyScore := 1.0

		// Composite score on 0-100 scale, then normalize to 0-1.
		rawScore := (successRate * 60.0) + (latencyScore * 30.0) + (consistencyScore * 10.0)
		ph.Score = rawScore / 100.0

		results = append(results, ph)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate provider health rows: %w", err)
	}

	return results, nil
}

// GetProviderHealthHistory retrieves the most recent `count` health scores
// for a single provider. Each score is computed per check-batch by grouping
// results into 30-second windows (matching the controller tick interval).
//
// Returns scores newest-first, normalized to 0.0-1.0.
func (s *PostgresHealthStore) GetProviderHealthHistory(ctx context.Context, providerID string, count int) ([]float64, error) {
	// We bucket results into 30-second windows and compute a score per bucket.
	query := `
		WITH bucketed AS (
			SELECT
				date_trunc('minute', check_timestamp) +
					(EXTRACT(SECOND FROM check_timestamp)::int / 30) * interval '30 seconds' AS bucket,
				AVG(CASE WHEN success THEN 1.0 ELSE 0.0 END) AS success_rate,
				COALESCE(AVG(CASE WHEN success THEN response_time_ms ELSE NULL END), 1000) AS avg_latency_ms
			FROM health_check_results
			WHERE provider_id = $1
			GROUP BY bucket
			ORDER BY bucket DESC
			LIMIT $2
		)
		SELECT success_rate, avg_latency_ms FROM bucketed ORDER BY bucket DESC
	`

	rows, err := s.db.QueryContext(ctx, query, providerID, count)
	if err != nil {
		return nil, fmt.Errorf("query provider health history: %w", err)
	}
	defer rows.Close()

	var scores []float64
	for rows.Next() {
		var successRate, avgLatencyMs float64
		if err := rows.Scan(&successRate, &avgLatencyMs); err != nil {
			return nil, fmt.Errorf("scan health history row: %w", err)
		}

		latencyScore := 1.0
		if avgLatencyMs >= 1000 {
			latencyScore = 0.0
		} else if avgLatencyMs > 50 {
			latencyScore = 1.0 - (avgLatencyMs-50.0)/950.0
		}

		rawScore := (successRate * 60.0) + (latencyScore * 30.0) + (1.0 * 10.0)
		scores = append(scores, rawScore/100.0)
	}

	return scores, nil
}
