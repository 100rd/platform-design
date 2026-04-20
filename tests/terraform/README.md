# Terratest Integration Tests

This directory contains Go-based integration tests for Terraform modules using [Terratest](https://terratest.gruntwork.io/).

## Directory Structure

```
tests/terraform/
├── README.md           # This file
├── go.mod              # Go module definition
├── go.sum              # Go module checksums
├── helpers/            # Shared test utilities
│   └── terraform.go
├── fixtures/           # Terraform configurations for tests
│   ├── vpc/
│   ├── s3/
│   └── eks/
├── vpc_test.go         # VPC module tests
├── s3_test.go          # S3 module tests
└── eks_test.go         # EKS module tests
```

## Prerequisites

- Go 1.22+
- Terraform 1.6+
- AWS credentials configured
- Sufficient IAM permissions to create test resources

## Running Tests

### Local Development

```bash
cd tests/terraform

# Download dependencies
go mod download

# Run all tests (requires AWS credentials)
go test -v ./...

# Run specific test
go test -v -run TestVPCCreatesSubnets ./...

# Run tests in short mode (skips long-running tests)
go test -v -short ./...

# Run with timeout
go test -v -timeout 30m ./...
```

### Test Categories

1. **Unit Tests** - No AWS credentials needed, validate Go code
   ```bash
   go build ./...
   go vet ./...
   ```

2. **Plan Tests** - Require AWS credentials, run `terraform plan` only
   ```bash
   go test -v -run "PlanValidation" ./...
   ```

3. **Full Integration Tests** - Create real infrastructure (expensive)
   ```bash
   go test -v -timeout 30m -run "TestVPCCreatesSubnets" ./...
   ```

## Test Modules

### VPC Module Tests (`vpc_test.go`)

| Test | Description | Duration |
|------|-------------|----------|
| `TestVPCCreatesSubnets` | Verifies subnet creation | ~5 min |
| `TestVPCWithHANAT` | Tests HA NAT gateway configuration | ~5 min |
| `TestVPCCIDRAllocation` | Validates CIDR allocation | ~5 min |

### S3 Module Tests (`s3_test.go`)

| Test | Description | Duration |
|------|-------------|----------|
| `TestS3BucketCreation` | Basic bucket creation | ~2 min |
| `TestS3BucketEncryption` | Verifies encryption settings | ~2 min |
| `TestS3BucketPublicAccessBlock` | Tests public access block | ~2 min |
| `TestS3BucketLifecycle` | Validates lifecycle rules | ~2 min |

### EKS Module Tests (`eks_test.go`)

| Test | Description | Duration |
|------|-------------|----------|
| `TestEKSPlanValidation` | Plan-only validation | ~1 min |
| `TestEKSClusterCreation` | Full cluster creation | ~20 min |
| `TestEKSClusterVersions` | Tests K8s version support | ~2 min |

## CI/CD Integration

Tests run automatically via GitHub Actions:

- **On PR**: Plan validation tests only
- **Nightly (2:00 UTC)**: Full integration tests
- **Manual**: Trigger via workflow_dispatch

See `.github/workflows/terratest.yml` for configuration.

## Adding New Tests

1. Create a fixture in `fixtures/<module>/`:
   - `main.tf` - Module wrapper
   - `variables.tf` - Input variables
   - `outputs.tf` - Outputs to verify

2. Create test file `<module>_test.go`:
   ```go
   func TestModuleFeature(t *testing.T) {
       t.Parallel()
       helpers.SkipIfShort(t)
       helpers.SkipIfCI(t)

       // Test implementation
   }
   ```

3. Update `terratest.yml` to include the new test in the matrix.

## Cost Considerations

- VPC tests: ~$0.05 per run (NAT Gateway hourly charges)
- S3 tests: ~$0.01 per run (minimal storage)
- EKS tests: ~$0.10 per hour (cluster control plane)

All tests include `defer terraform.Destroy()` to clean up resources.

## Troubleshooting

### Common Issues

1. **Timeout errors**: Increase timeout with `-timeout 30m`
2. **Permission errors**: Check IAM permissions
3. **Resource conflicts**: Tests use unique IDs but may conflict on AWS limits

### Debugging

```bash
# Enable Terraform debug logging
TF_LOG=DEBUG go test -v -run TestVPCCreatesSubnets ./...

# Keep resources for inspection (remove defer Destroy)
# WARNING: Remember to manually clean up!
```
