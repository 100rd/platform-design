package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
	log.Println("Starting DNS Failover Controller...")

	// ---------------------------------------------------------------
	// Initialize Database Storage
	// ---------------------------------------------------------------
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL environment variable is required")
	}

	storage, err := NewStorage(dbURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer storage.Close()

	// ---------------------------------------------------------------
	// Initialize Health Store (queries dns-monitor's database)
	// ---------------------------------------------------------------
	healthStore := NewPostgresHealthStore(storage.db)

	// ---------------------------------------------------------------
	// Initialize State Persistence
	// ---------------------------------------------------------------
	statePath := os.Getenv("STATE_FILE")
	if statePath == "" {
		statePath = "/var/lib/failover-controller/state.json"
	}
	stateStore := NewStateStore(statePath)

	// Verify we can load (or create default) state at startup.
	initialState, err := stateStore.Load()
	if err != nil {
		log.Fatalf("Failed to load persisted state: %v", err)
	}
	log.Printf("Loaded state: %s (last transition: %s)",
		initialState.CurrentState, initialState.LastTransitionTime.Format(time.RFC3339))

	// ---------------------------------------------------------------
	// Initialize Registrar Client
	// ---------------------------------------------------------------
	registrar := NewRegistrarClient()

	// ---------------------------------------------------------------
	// Initialize State Machine
	// ---------------------------------------------------------------
	sm := NewStateMachine(storage, registrar, healthStore, stateStore)

	// ---------------------------------------------------------------
	// Start HTTP Server (metrics, health checks, state endpoint)
	// ---------------------------------------------------------------
	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("ok"))
		})
		mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
			if _, loadErr := stateStore.Load(); loadErr != nil {
				http.Error(w, "not ready", http.StatusServiceUnavailable)
				return
			}
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("ok"))
		})
		mux.HandleFunc("/state", func(w http.ResponseWriter, r *http.Request) {
			st, loadErr := stateStore.Load()
			if loadErr != nil {
				http.Error(w, loadErr.Error(), http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(st)
		})

		log.Println("HTTP server listening on :8080 (/metrics, /healthz, /readyz, /state)")
		if err := http.ListenAndServe(":8080", mux); err != nil {
			log.Fatalf("HTTP server failed: %v", err)
		}
	}()

	// ---------------------------------------------------------------
	// Main Evaluation Loop
	// ---------------------------------------------------------------
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Graceful shutdown on SIGINT/SIGTERM.
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigChan
		log.Printf("Received signal %s, shutting down...", sig)
		cancel()
	}()

	// Run immediately on startup.
	log.Println("Running initial state evaluation...")
	sm.Evaluate(ctx)

	for {
		select {
		case <-ticker.C:
			log.Println("Running scheduled state evaluation...")
			sm.Evaluate(ctx)
		case <-ctx.Done():
			log.Println("Failover Controller stopped.")
			return
		}
	}
}
