// Package terraform contains integration tests for Terraform modules.
package terraform

import (
	"fmt"
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/100rd/platform-design/tests/terraform/helpers"
)

// TestVPCCreatesSubnets verifies that the VPC module creates the expected subnets.
func TestVPCCreatesSubnets(t *testing.T) {
	t.Parallel()
	helpers.SkipIfShort(t)
	helpers.SkipIfCI(t)

	uniqueID := random.UniqueId()
	vpcName := fmt.Sprintf("terratest-vpc-%s", uniqueID)
	awsRegion := helpers.GetAWSRegion()

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/vpc",
		Vars: map[string]interface{}{
			"vpc_name":        vpcName,
			"vpc_cidr":        "10.0.0.0/16",
			"azs":             []string{"us-east-1a", "us-east-1b", "us-east-1c"},
			"aws_region":      awsRegion,
			"test_name":       t.Name(),
			"enable_flow_log": false, // Disable for faster tests
			"tags": map[string]string{
				"Environment": "test",
				"ManagedBy":   "terratest",
				"TestID":      uniqueID,
			},
		},
		NoColor: true,
	}

	// Clean up resources at the end of the test
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply
	terraform.InitAndApply(t, terraformOptions)

	// Verify VPC was created
	vpcID := terraform.Output(t, terraformOptions, "vpc_id")
	require.NotEmpty(t, vpcID, "VPC ID should not be empty")

	// Verify public subnets
	publicSubnets := terraform.OutputList(t, terraformOptions, "public_subnets")
	assert.Len(t, publicSubnets, 3, "Should create 3 public subnets (one per AZ)")

	// Verify private subnets
	privateSubnets := terraform.OutputList(t, terraformOptions, "private_subnets")
	assert.Len(t, privateSubnets, 3, "Should create 3 private subnets (one per AZ)")

	// Verify VPC exists in AWS
	vpc := aws.GetVpcById(t, vpcID, awsRegion)
	assert.Equal(t, "10.0.0.0/16", *vpc.CidrBlock, "VPC CIDR should match")
}

// TestVPCWithHANAT verifies the HA NAT Gateway configuration.
func TestVPCWithHANAT(t *testing.T) {
	t.Parallel()
	helpers.SkipIfShort(t)
	helpers.SkipIfCI(t)

	uniqueID := random.UniqueId()
	vpcName := fmt.Sprintf("terratest-vpc-ha-%s", uniqueID)
	awsRegion := helpers.GetAWSRegion()

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/vpc",
		Vars: map[string]interface{}{
			"vpc_name":        vpcName,
			"vpc_cidr":        "10.1.0.0/16",
			"azs":             []string{"us-east-1a", "us-east-1b"},
			"aws_region":      awsRegion,
			"test_name":       t.Name(),
			"enable_ha_nat":   true, // Enable HA NAT
			"enable_flow_log": false,
			"tags": map[string]string{
				"Environment": "test",
				"ManagedBy":   "terratest",
				"TestID":      uniqueID,
			},
		},
		NoColor: true,
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	vpcID := terraform.Output(t, terraformOptions, "vpc_id")
	require.NotEmpty(t, vpcID, "VPC ID should not be empty")

	// Verify subnets for 2 AZs
	publicSubnets := terraform.OutputList(t, terraformOptions, "public_subnets")
	assert.Len(t, publicSubnets, 2, "Should create 2 public subnets for 2 AZs")

	privateSubnets := terraform.OutputList(t, terraformOptions, "private_subnets")
	assert.Len(t, privateSubnets, 2, "Should create 2 private subnets for 2 AZs")
}

// TestVPCCIDRAllocation verifies CIDR allocation for different configurations.
func TestVPCCIDRAllocation(t *testing.T) {
	t.Parallel()
	helpers.SkipIfShort(t)
	helpers.SkipIfCI(t)

	testCases := []struct {
		name     string
		cidr     string
		azCount  int
		expected int
	}{
		{"small-vpc", "10.2.0.0/20", 2, 2},
		{"medium-vpc", "10.3.0.0/18", 3, 3},
	}

	for _, tc := range testCases {
		tc := tc // Capture range variable
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			uniqueID := random.UniqueId()
			vpcName := fmt.Sprintf("terratest-%s-%s", tc.name, uniqueID)
			awsRegion := helpers.GetAWSRegion()

			azs := make([]string, tc.azCount)
			for i := 0; i < tc.azCount; i++ {
				azs[i] = fmt.Sprintf("%s%c", awsRegion, 'a'+i)
			}

			terraformOptions := &terraform.Options{
				TerraformDir: "./fixtures/vpc",
				Vars: map[string]interface{}{
					"vpc_name":        vpcName,
					"vpc_cidr":        tc.cidr,
					"azs":             azs,
					"aws_region":      awsRegion,
					"test_name":       t.Name(),
					"enable_flow_log": false,
					"tags": map[string]string{
						"Environment": "test",
						"ManagedBy":   "terratest",
						"TestID":      uniqueID,
					},
				},
				NoColor: true,
			}

			defer terraform.Destroy(t, terraformOptions)
			terraform.InitAndApply(t, terraformOptions)

			privateSubnets := terraform.OutputList(t, terraformOptions, "private_subnets")
			assert.Len(t, privateSubnets, tc.expected, "Should create expected number of private subnets")
		})
	}
}
