package main

import (
	"context"
	"log"
	"math"
	"net"
	"time"

	"github.com/miekg/dns"
)

type Monitor struct {
	storage *Storage
}

func NewMonitor(storage *Storage) *Monitor {
	return &Monitor{storage: storage}
}

func (m *Monitor) RunChecks(ctx context.Context) {
	providers, err := m.storage.GetProviders(ctx)
	if err != nil {
		log.Printf("Error fetching providers: %v", err)
		return
	}

	for _, p := range providers {
		go m.checkProvider(ctx, p)
	}
}

func (m *Monitor) checkProvider(ctx context.Context, p Provider) {
	successCount := 0
	totalLatency := time.Duration(0)
	totalChecks := 0

	for _, ns := range p.HealthCheckEndpoints {
		start := time.Now()
		success, err := m.queryDNS(ns, "_health-check.example.com")
		latency := time.Since(start)

		totalChecks++
		if success {
			successCount++
		}
		totalLatency += latency

		// Record Result
		errStr := ""
		if err != nil {
			errStr = err.Error()
		}
		
		result := HealthResult{
			ProviderID:        p.ID,
			NameserverAddress: ns,
			QueryDomain:       "_health-check.example.com",
			ResponseTimeMs:    int(latency.Milliseconds()),
			Success:           success,
			ErrorMessage:      errStr,
			CheckLocation:     "us-east-1", // Hardcoded for now, would come from env
		}
		
		if err := m.storage.SaveResult(ctx, result); err != nil {
			log.Printf("Error saving result: %v", err)
		}

		// Update Prometheus Metrics
		dnsQueryDuration.WithLabelValues(p.Name, ns).Observe(latency.Seconds())
		if success {
			dnsQuerySuccessTotal.WithLabelValues(p.Name, ns).Inc()
		} else {
			dnsQueryFailureTotal.WithLabelValues(p.Name, ns).Inc()
		}
	}

	// Calculate Health Score
	// Score = (SuccessRate * 0.6) + (LatencyScore * 0.3) + (ConsistencyScore * 0.1)
	if totalChecks > 0 {
		successRate := float64(successCount) / float64(totalChecks)
		avgLatencyMs := float64(totalLatency.Milliseconds()) / float64(totalChecks)
		
		// Latency Score: 1.0 if < 50ms, 0.0 if > 1000ms
		latencyScore := math.Max(0, 1.0 - (avgLatencyMs - 50.0) / 950.0)
		if avgLatencyMs < 50 {
			latencyScore = 1.0
		}

		// Consistency Score (Simplified: 1.0 if all checks passed/failed same way)
		consistencyScore := 1.0 // Placeholder

		healthScore := (successRate * 60.0) + (latencyScore * 30.0) + (consistencyScore * 10.0)
		
		dnsProviderHealthScore.WithLabelValues(p.Name).Set(healthScore)
		log.Printf("Provider %s Health Score: %.2f", p.Name, healthScore)
	}
}

func (m *Monitor) queryDNS(nameserver, domain string) (bool, error) {
	c := new(dns.Client)
	c.Timeout = 5 * time.Second
	
	msg := new(dns.Msg)
	msg.SetQuestion(dns.Fqdn(domain), dns.TypeTXT)
	msg.RecursionDesired = false

	// Ensure nameserver has port
	if _, _, err := net.SplitHostPort(nameserver); err != nil {
		nameserver = net.JoinHostPort(nameserver, "53")
	}

	r, _, err := c.Exchange(msg, nameserver)
	if err != nil {
		return false, err
	}

	if r.Rcode != dns.RcodeSuccess {
		return false, nil
	}

	return true, nil
}
