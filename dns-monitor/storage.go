package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"

	_ "github.com/lib/pq"
)

type Storage struct {
	db *sql.DB
}

type Provider struct {
	ID                   string
	Name                 string
	HealthCheckEndpoints []string
}

type HealthResult struct {
	ProviderID        string
	NameserverAddress string
	QueryDomain       string
	ResponseTimeMs    int
	Success           bool
	ErrorMessage      string
	CheckLocation     string
}

func NewStorage(connStr string) (*Storage, error) {
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return nil, err
	}
	if err := db.Ping(); err != nil {
		return nil, err
	}
	return &Storage{db: db}, nil
}

func (s *Storage) Close() {
	s.db.Close()
}

func (s *Storage) GetProviders(ctx context.Context) ([]Provider, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT id, name, health_check_endpoints FROM dns_providers WHERE status != 'failed'")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var providers []Provider
	for rows.Next() {
		var p Provider
		var endpointsJSON []byte
		if err := rows.Scan(&p.ID, &p.Name, &endpointsJSON); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(endpointsJSON, &p.HealthCheckEndpoints); err != nil {
			return nil, err
		}
		providers = append(providers, p)
	}
	return providers, nil
}

func (s *Storage) SaveResult(ctx context.Context, r HealthResult) error {
	query := `
		INSERT INTO health_check_results 
		(provider_id, nameserver_address, query_domain, response_time_ms, success, error_message, check_location, check_timestamp)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`
	_, err := s.db.ExecContext(ctx, query, 
		r.ProviderID, r.NameserverAddress, r.QueryDomain, r.ResponseTimeMs, r.Success, r.ErrorMessage, r.CheckLocation, time.Now())
	return err
}
