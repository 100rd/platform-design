// Package terraform contains integration tests for Terraform modules.
package terraform

import (
	"fmt"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/100rd/platform-design/tests/terraform/helpers"
)

// TestEKSPlanValidation verifies that the EKS module produces a valid plan.
// This test uses plan-only mode to avoid the 15-20 minute cluster creation time.
func TestEKSPlanValidation(t *testing.T) {
	t.Parallel()
	helpers.SkipIfShort(t)
	helpers.SkipIfCI(t)

	uniqueID := random.UniqueId()
	clusterName := fmt.Sprintf("terratest-eks-%s", uniqueID)
	awsRegion := helpers.GetAWSRegion()

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/eks",
		Vars: map[string]interface{}{
			"cluster_name":    clusterName,
			"cluster_version": "1.30",
			"aws_region":      awsRegion,
			"test_name":       t.Name(),
			"vpc_cidr":        "10.10.0.0/16",
			"azs":             []string{"us-east-1a", "us-east-1b"},
			"tags": map[string]string{
				"Environment": "test",
				"ManagedBy":   "terratest",
				"TestID":      uniqueID,
			},
		},
		NoColor: true,
	}

	// Initialize and plan (no apply)
	terraform.Init(t, terraformOptions)
	planOutput := terraform.Plan(t, terraformOptions)

	// Verify plan creates expected resources
	assert.Contains(t, planOutput, "module.eks", "Plan should include EKS module")
	assert.Contains(t, planOutput, "module.vpc", "Plan should include VPC module")
}

// TestEKSClusterCreation is a full integration test that creates a real EKS cluster.
// This test is expensive (~$0.10/hour for the cluster) and slow (15-20 minutes).
// Only run manually with: go test -run TestEKSClusterCreation -v -timeout 30m
func TestEKSClusterCreation(t *testing.T) {
	t.Parallel()
	helpers.SkipIfShort(t)
	helpers.SkipIfCI(t)

	// Skip by default unless explicitly enabled
	if testing.Short() {
		t.Skip("Skipping EKS cluster creation test (expensive and slow)")
	}

	uniqueID := random.UniqueId()
	clusterName := fmt.Sprintf("terratest-eks-%s", uniqueID)
	awsRegion := helpers.GetAWSRegion()

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/eks",
		Vars: map[string]interface{}{
			"cluster_name":    clusterName,
			"cluster_version": "1.30",
			"aws_region":      awsRegion,
			"test_name":       t.Name(),
			"vpc_cidr":        "10.11.0.0/16",
			"azs":             []string{"us-east-1a", "us-east-1b"},
			"tags": map[string]string{
				"Environment": "test",
				"ManagedBy":   "terratest",
				"TestID":      uniqueID,
			},
		},
		NoColor:            true,
		RetryableTerraformErrors: map[string]string{
			".*": "Retrying due to transient error",
		},
		MaxRetries:         3,
		TimeBetweenRetries: 5 * time.Second,
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify cluster was created
	clusterNameOutput := terraform.Output(t, terraformOptions, "cluster_name")
	require.Equal(t, clusterName, clusterNameOutput, "Cluster name should match")

	clusterEndpoint := terraform.Output(t, terraformOptions, "cluster_endpoint")
	require.NotEmpty(t, clusterEndpoint, "Cluster endpoint should not be empty")
	assert.Contains(t, clusterEndpoint, "eks.amazonaws.com", "Endpoint should be an EKS endpoint")

	clusterVersion := terraform.Output(t, terraformOptions, "cluster_version")
	assert.Equal(t, "1.30", clusterVersion, "Cluster version should match")
}

// TestEKSClusterVersions verifies the module works with different Kubernetes versions.
func TestEKSClusterVersions(t *testing.T) {
	t.Parallel()
	helpers.SkipIfShort(t)
	helpers.SkipIfCI(t)

	testCases := []struct {
		name    string
		version string
	}{
		{"k8s-1.29", "1.29"},
		{"k8s-1.30", "1.30"},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := random.UniqueId()
			clusterName := fmt.Sprintf("terratest-%s-%s", tc.name, uniqueID)
			awsRegion := helpers.GetAWSRegion()

			terraformOptions := &terraform.Options{
				TerraformDir: "./fixtures/eks",
				Vars: map[string]interface{}{
					"cluster_name":    clusterName,
					"cluster_version": tc.version,
					"aws_region":      awsRegion,
					"test_name":       t.Name(),
					"vpc_cidr":        fmt.Sprintf("10.%d.0.0/16", 20+len(tc.version)),
					"azs":             []string{"us-east-1a", "us-east-1b"},
					"tags": map[string]string{
						"Environment": "test",
						"ManagedBy":   "terratest",
						"TestID":      uniqueID,
					},
				},
				NoColor: true,
			}

			// Plan only - don't create expensive clusters
			terraform.Init(t, terraformOptions)
			planOutput := terraform.Plan(t, terraformOptions)

			assert.Contains(t, planOutput, tc.version, "Plan should use specified Kubernetes version")
		})
	}
}
