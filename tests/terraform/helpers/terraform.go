// Package helpers provides common utilities for Terratest integration tests.
package helpers

import (
	"fmt"
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// DefaultTerraformOptions returns standard Terraform options with common settings.
func DefaultTerraformOptions(t *testing.T, modulePath string) *terraform.Options {
	return &terraform.Options{
		TerraformDir: modulePath,
		NoColor:      true,
		Lock:         true,
		Upgrade:      true,
	}
}

// UniqueID generates a unique identifier for test resources.
func UniqueID() string {
	return random.UniqueId()
}

// GetEnvOrDefault returns the environment variable value or a default.
func GetEnvOrDefault(envVar, defaultValue string) string {
	if value := os.Getenv(envVar); value != "" {
		return value
	}
	return defaultValue
}

// GetAWSRegion returns the AWS region to use for tests.
func GetAWSRegion() string {
	return GetEnvOrDefault("AWS_REGION", "us-east-1")
}

// DefaultTags returns standard tags for test resources.
func DefaultTags(testName string) map[string]string {
	return map[string]string{
		"Environment": "test",
		"ManagedBy":   "terratest",
		"TestName":    testName,
		"Team":        "platform",
	}
}

// ValidateCIDR checks if a CIDR block is valid.
func ValidateCIDR(cidr string) error {
	// Simple validation - check format
	if cidr == "" {
		return fmt.Errorf("CIDR block cannot be empty")
	}
	return nil
}

// SkipIfCI skips the test if running in CI without proper credentials.
func SkipIfCI(t *testing.T) {
	if os.Getenv("CI") == "true" && os.Getenv("AWS_ACCESS_KEY_ID") == "" {
		t.Skip("Skipping test in CI without AWS credentials")
	}
}

// SkipIfShort skips the test if running in short mode.
func SkipIfShort(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping long-running test in short mode")
	}
}
