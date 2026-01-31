package main

import (
	"log"
)

// RegistrarClient abstracts the domain registrar API. The controller uses
// this interface to read and update nameserver records for a domain.
//
// To implement a real registrar client (e.g., Namecheap, GoDaddy, Cloudflare
// Registrar), create a struct that satisfies this interface and wire it in
// main.go based on a REGISTRAR_TYPE environment variable.
//
// Example for a Namecheap implementation:
//
//	type NamecheapRegistrarClient struct {
//	    apiUser string
//	    apiKey  string
//	    baseURL string
//	    client  *http.Client
//	}
//
//	func NewNamecheapRegistrarClient(apiUser, apiKey string) *NamecheapRegistrarClient {
//	    return &NamecheapRegistrarClient{
//	        apiUser: apiUser,
//	        apiKey:  apiKey,
//	        baseURL: "https://api.namecheap.com/xml.response",
//	        client:  &http.Client{Timeout: 30 * time.Second},
//	    }
//	}
//
//	func (c *NamecheapRegistrarClient) GetNameservers(domain string) ([]string, error) {
//	    // Call namecheap.domains.dns.getList API
//	    // Parse XML response and return nameserver list
//	}
//
//	func (c *NamecheapRegistrarClient) UpdateNameservers(domain string, ns []string) error {
//	    // Call namecheap.domains.dns.setCustom API
//	    // Pass nameservers as comma-separated string
//	    // Verify HTTP 200 + ApiResponse Status="OK"
//	}
//
//	func (c *NamecheapRegistrarClient) VerifyPropagation(domain string, ns []string) (bool, error) {
//	    // Query public DNS resolvers (8.8.8.8, 1.1.1.1) for the domain's NS records
//	    // Compare returned NS with expected NS
//	    // Return true only if all resolvers agree
//	}
type RegistrarClient interface {
	// GetNameservers returns the currently configured nameservers for the domain.
	GetNameservers(domain string) ([]string, error)

	// UpdateNameservers sets the domain's nameservers to the provided list.
	// This is the core failover/failback operation.
	UpdateNameservers(domain string, nameservers []string) error

	// VerifyPropagation checks whether the expected nameservers have propagated
	// to public DNS resolvers. Returns true when propagation is confirmed.
	VerifyPropagation(domain string, nameservers []string) (bool, error)
}

// MockRegistrarClient is used for development and testing. It logs all
// operations and returns success without making any real API calls.
type MockRegistrarClient struct {
	// currentNS tracks what the mock thinks the nameservers are, so tests
	// can verify the sequence of updates.
	currentNS map[string][]string
}

// NewRegistrarClient returns a MockRegistrarClient. In production, switch on
// an environment variable to return the real implementation:
//
//	func NewRegistrarClient() RegistrarClient {
//	    switch os.Getenv("REGISTRAR_TYPE") {
//	    case "namecheap":
//	        return NewNamecheapRegistrarClient(
//	            os.Getenv("NAMECHEAP_API_USER"),
//	            os.Getenv("NAMECHEAP_API_KEY"),
//	        )
//	    case "godaddy":
//	        return NewGoDaddyRegistrarClient(
//	            os.Getenv("GODADDY_API_KEY"),
//	            os.Getenv("GODADDY_API_SECRET"),
//	        )
//	    default:
//	        return &MockRegistrarClient{currentNS: make(map[string][]string)}
//	    }
//	}
func NewRegistrarClient() RegistrarClient {
	return &MockRegistrarClient{
		currentNS: make(map[string][]string),
	}
}

func (c *MockRegistrarClient) GetNameservers(domain string) ([]string, error) {
	log.Printf("[MockRegistrar] GetNameservers(%s)", domain)
	if ns, ok := c.currentNS[domain]; ok {
		return ns, nil
	}
	// Default: return a typical dual-provider setup.
	return []string{"ns1.primary-provider.com", "ns2.primary-provider.com"}, nil
}

func (c *MockRegistrarClient) UpdateNameservers(domain string, nameservers []string) error {
	log.Printf("[MockRegistrar] UpdateNameservers(%s, %v)", domain, nameservers)
	c.currentNS[domain] = nameservers
	return nil
}

func (c *MockRegistrarClient) VerifyPropagation(domain string, nameservers []string) (bool, error) {
	log.Printf("[MockRegistrar] VerifyPropagation(%s, %v)", domain, nameservers)
	// The mock always reports success. A real implementation would query
	// multiple public resolvers and compare NS records.
	return true, nil
}
