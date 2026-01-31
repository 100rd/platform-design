package main

import (
	"database/sql"

	_ "github.com/lib/pq"
)

// Storage wraps a Postgres connection pool. It is shared with the dns-monitor
// codebase (in a real repository this would be a shared Go module; here it is
// duplicated for simplicity). The failover-controller only needs the *sql.DB
// handle so that PostgresHealthStore can run queries against the same database
// that the dns-monitor writes health check results to.
type Storage struct {
	db *sql.DB
}

// NewStorage opens a Postgres connection and verifies it with a ping.
func NewStorage(connStr string) (*Storage, error) {
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return nil, err
	}
	if err := db.Ping(); err != nil {
		return nil, err
	}
	// Sensible pool defaults for a controller that runs one query per tick.
	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)
	return &Storage{db: db}, nil
}

// Close shuts down the connection pool.
func (s *Storage) Close() {
	s.db.Close()
}
