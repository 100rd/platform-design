package main

import (
	"log"
)

type RegistrarClient interface {
	GetNameservers(domain string) ([]string, error)
	UpdateNameservers(domain string, nameservers []string) error
	VerifyPropagation(domain string, nameservers []string) (bool, error)
}

// MockRegistrarClient for development/testing
type MockRegistrarClient struct{}

func NewRegistrarClient() RegistrarClient {
	// In production, this would switch based on config (e.g., Namecheap, GoDaddy)
	return &MockRegistrarClient{}
}

func (c *MockRegistrarClient) GetNameservers(domain string) ([]string, error) {
	log.Printf("[MockRegistrar] Getting NS for %s", domain)
	return []string{"ns1.cloudflare.com", "ns1.route53.aws.com"}, nil
}

func (c *MockRegistrarClient) UpdateNameservers(domain string, nameservers []string) error {
	log.Printf("[MockRegistrar] Updating NS for %s to %v", domain, nameservers)
	return nil
}

func (c *MockRegistrarClient) VerifyPropagation(domain string, nameservers []string) (bool, error) {
	log.Printf("[MockRegistrar] Verifying propagation for %s", domain)
	return true, nil
}
