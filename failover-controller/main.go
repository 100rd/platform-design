package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"net/http"
)

func main() {
	log.Println("Starting DNS Failover Controller...")

	// Initialize Storage
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL environment variable is required")
	}
	// Reusing storage implementation from monitor (shared code in real repo, duplicated here for simplicity)
	storage, err := NewStorage(dbURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer storage.Close()

	// Initialize Registrar Client
	registrar := NewRegistrarClient()

	// Initialize State Machine
	sm := NewStateMachine(storage, registrar)

	// Start Metrics Server
	go func() {
		http.Handle("/metrics", promhttp.Handler())
		log.Println("Metrics server listening on :8080")
		if err := http.ListenAndServe(":8080", nil); err != nil {
			log.Fatalf("Metrics server failed: %v", err)
		}
	}()

	// Main Loop
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle Graceful Shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		log.Println("Shutting down...")
		cancel()
	}()

	// Initial Run
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
