package main

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	dnsQueryDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name: "dns_query_duration_seconds",
		Help: "Duration of DNS queries in seconds",
		Buckets: []float64{0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0},
	}, []string{"provider", "nameserver"})

	dnsQuerySuccessTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "dns_query_success_total",
		Help: "Total number of successful DNS queries",
	}, []string{"provider", "nameserver"})

	dnsQueryFailureTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "dns_query_failure_total",
		Help: "Total number of failed DNS queries",
	}, []string{"provider", "nameserver"})

	dnsProviderHealthScore = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "dns_provider_health_score",
		Help: "Calculated health score of the DNS provider (0-100)",
	}, []string{"provider"})
)
