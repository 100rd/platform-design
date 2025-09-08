package main

import (
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	healthzCheck = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "healthz_requests_total",
			Help: "Total healthz (liveness) probe requests.",
		},
	)
	readyzCheck = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "readyz_requests_total",
			Help: "Total readyz (readiness) probe requests.",
		},
	)
	rootRequests = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "root_requests_total",
			Help: "Total root endpoint requests.",
		},
	)
)

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	healthzCheck.Inc()
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func readyzHandler(w http.ResponseWriter, r *http.Request) {
	readyzCheck.Inc()
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
	rootRequests.Inc()
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("hello world"))
}

func main() {
	prometheus.MustRegister(healthzCheck, readyzCheck, rootRequests)

	http.HandleFunc("/", rootHandler)
	http.HandleFunc("/healthz", healthzHandler)
	http.HandleFunc("/readyz", readyzHandler)
	http.Handle("/metrics", promhttp.Handler())

	addr := ":8080"
	if p := os.Getenv("PORT"); p != "" {
		addr = ":"+p
	}
	log.Printf("Starting server on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

