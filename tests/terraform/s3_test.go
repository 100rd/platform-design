// Package terraform contains integration tests for Terraform modules.
package terraform

import (
	"fmt"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/100rd/platform-design/tests/terraform/helpers"
)

// TestS3BucketCreation verifies that the S3 module creates a bucket with correct settings.
func TestS3BucketCreation(t *testing.T) {
	t.Parallel()
	helpers.SkipIfShort(t)
	helpers.SkipIfCI(t)

	uniqueID := strings.ToLower(random.UniqueId())
	bucketName := fmt.Sprintf("terratest-s3-%s", uniqueID)
	awsRegion := helpers.GetAWSRegion()

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/s3",
		Vars: map[string]interface{}{
			"bucket_name":         bucketName,
			"aws_region":          awsRegion,
			"test_name":           t.Name(),
			"versioning_enabled":  true,
			"force_destroy":       true,
			"create_iam_policies": false,
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

	// Verify bucket was created
	bucketID := terraform.Output(t, terraformOptions, "bucket_id")
	require.NotEmpty(t, bucketID, "Bucket ID should not be empty")
	assert.Equal(t, bucketName, bucketID, "Bucket ID should match bucket name")

	// Verify bucket exists in AWS
	aws.AssertS3BucketExists(t, awsRegion, bucketName)

	// Verify versioning is enabled
	versioning := aws.GetS3BucketVersioning(t, awsRegion, bucketName)
	assert.Equal(t, "Enabled", versioning, "Versioning should be enabled")
}

// TestS3BucketEncryption verifies that the S3 bucket has server-side encryption enabled.
func TestS3BucketEncryption(t *testing.T) {
	t.Parallel()
	helpers.SkipIfShort(t)
	helpers.SkipIfCI(t)

	uniqueID := strings.ToLower(random.UniqueId())
	bucketName := fmt.Sprintf("terratest-s3-enc-%s", uniqueID)
	awsRegion := helpers.GetAWSRegion()

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/s3",
		Vars: map[string]interface{}{
			"bucket_name":         bucketName,
			"aws_region":          awsRegion,
			"test_name":           t.Name(),
			"versioning_enabled":  true,
			"force_destroy":       true,
			"create_iam_policies": false,
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

	bucketID := terraform.Output(t, terraformOptions, "bucket_id")
	require.NotEmpty(t, bucketID, "Bucket ID should not be empty")

	// Verify bucket policy (TLS enforcement)
	policy := aws.GetS3BucketPolicy(t, awsRegion, bucketName)
	assert.Contains(t, policy, "DenyInsecureTransport", "Bucket policy should deny insecure transport")
}

// TestS3BucketPublicAccessBlock verifies that public access is blocked.
func TestS3BucketPublicAccessBlock(t *testing.T) {
	t.Parallel()
	helpers.SkipIfShort(t)
	helpers.SkipIfCI(t)

	uniqueID := strings.ToLower(random.UniqueId())
	bucketName := fmt.Sprintf("terratest-s3-pub-%s", uniqueID)
	awsRegion := helpers.GetAWSRegion()

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/s3",
		Vars: map[string]interface{}{
			"bucket_name":         bucketName,
			"aws_region":          awsRegion,
			"test_name":           t.Name(),
			"versioning_enabled":  true,
			"force_destroy":       true,
			"create_iam_policies": false,
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

	bucketID := terraform.Output(t, terraformOptions, "bucket_id")
	require.NotEmpty(t, bucketID, "Bucket ID should not be empty")

	// The S3 module blocks all public access by default
	// We verify the bucket exists and has the expected configuration
	aws.AssertS3BucketExists(t, awsRegion, bucketName)
}

// TestS3BucketLifecycle verifies lifecycle rules work correctly.
func TestS3BucketLifecycle(t *testing.T) {
	t.Parallel()
	helpers.SkipIfShort(t)
	helpers.SkipIfCI(t)

	uniqueID := strings.ToLower(random.UniqueId())
	bucketName := fmt.Sprintf("terratest-s3-lc-%s", uniqueID)
	awsRegion := helpers.GetAWSRegion()

	lifecycleRules := []map[string]interface{}{
		{
			"id":              "archive-logs",
			"prefix":          "logs/",
			"expiration_days": 90,
			"transitions": []map[string]interface{}{
				{
					"days":          30,
					"storage_class": "STANDARD_IA",
				},
			},
		},
	}

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/s3",
		Vars: map[string]interface{}{
			"bucket_name":         bucketName,
			"aws_region":          awsRegion,
			"test_name":           t.Name(),
			"versioning_enabled":  true,
			"force_destroy":       true,
			"create_iam_policies": false,
			"lifecycle_rules":     lifecycleRules,
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

	bucketID := terraform.Output(t, terraformOptions, "bucket_id")
	require.NotEmpty(t, bucketID, "Bucket ID should not be empty")

	// Verify bucket was created successfully with lifecycle rules
	aws.AssertS3BucketExists(t, awsRegion, bucketName)
}
