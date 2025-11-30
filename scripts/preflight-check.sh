#!/bin/bash

##############################################################################
# Platform-Design Pre-flight Check Script
#
# Validates environment before deployment
#
# Usage:
#   ./scripts/preflight-check.sh
#
##############################################################################

set -e
set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

##############################################################################
# Functions
##############################################################################

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; CHECKS_PASSED=$((CHECKS_PASSED+1)); }
log_error() { echo -e "${RED}✗${NC} $1"; CHECKS_FAILED=$((CHECKS_FAILED+1)); }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; CHECKS_WARNING=$((CHECKS_WARNING+1)); }

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

check_required_tools() {
    print_header "🔧 Checking Required Tools"

    # Terraform
    if command -v terraform &> /dev/null; then
        local version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1 | cut -d'v' -f2)
        log_success "terraform $version"

        # Check minimum version (1.3.0)
        if [ "$(printf '%s\n' "1.3.0" "$version" | sort -V | head -n1)" = "1.3.0" ]; then
            log_success "Terraform version >= 1.3.0"
        else
            log_error "Terraform version must be >= 1.3.0 (found: $version)"
        fi
    else
        log_error "terraform not found"
        echo "  Install: https://www.terraform.io/downloads"
    fi

    # AWS CLI
    if command -v aws &> /dev/null; then
        local version=$(aws --version | cut -d' ' -f1 | cut -d'/' -f2)
        log_success "aws-cli $version"

        # Check minimum version (2.0.0)
        local major=$(echo "$version" | cut -d'.' -f1)
        if [ "$major" -ge 2 ]; then
            log_success "AWS CLI version >= 2.0"
        else
            log_warning "AWS CLI version 2.x recommended (found: $version)"
        fi
    else
        log_error "aws cli not found"
        echo "  Install: https://aws.amazon.com/cli/"
    fi

    # kubectl
    if command -v kubectl &> /dev/null; then
        local version=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 | sed 's/v//' || kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' | sed 's/v//')
        log_success "kubectl $version"
    else
        log_error "kubectl not found"
        echo "  Install: https://kubernetes.io/docs/tasks/tools/"
    fi

    # jq
    if command -v jq &> /dev/null; then
        local version=$(jq --version | cut -d'-' -f2)
        log_success "jq $version"
    else
        log_error "jq not found"
        echo "  Install: https://stedolan.github.io/jq/"
    fi

    # envsubst (optional but recommended)
    if command -v envsubst &> /dev/null; then
        log_success "envsubst (gettext) installed"
    else
        log_warning "envsubst not found (optional, for template rendering)"
        echo "  Install: brew install gettext (macOS) or apt-get install gettext-base (Linux)"
    fi

    # helm (optional)
    if command -v helm &> /dev/null; then
        local version=$(helm version --short | cut -d'+' -f1)
        log_success "helm $version"
    else
        log_info "helm not found (optional)"
    fi
}

check_aws_credentials() {
    print_header "🔐 Checking AWS Credentials"

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        echo "  Run: aws configure"
        echo "  Or set: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN"
        return 1
    fi

    local account=$(aws sts get-caller-identity --query Account --output text)
    local arn=$(aws sts get-caller-identity --query Arn --output text)
    local user=$(echo "$arn" | rev | cut -d'/' -f1 | rev)

    log_success "AWS Account: $account"
    log_success "AWS User/Role: $user"

    # Check region
    local region=$(aws configure get region || echo "not set")
    if [ "$region" != "not set" ]; then
        log_success "Default region: $region"
    else
        log_warning "AWS region not configured"
        echo "  Run: aws configure set region us-east-1"
    fi
}

check_aws_permissions() {
    print_header "🔑 Checking AWS Permissions"

    log_info "Testing required AWS permissions..."

    # Test EC2 permissions
    if aws ec2 describe-vpcs --max-results 1 &> /dev/null; then
        log_success "EC2 permissions: OK"
    else
        log_error "Missing EC2 permissions"
    fi

    # Test EKS permissions
    if aws eks list-clusters --max-results 1 &> /dev/null; then
        log_success "EKS permissions: OK"
    else
        log_error "Missing EKS permissions"
    fi

    # Test IAM permissions
    if aws iam list-roles --max-items 1 &> /dev/null; then
        log_success "IAM permissions: OK"
    else
        log_error "Missing IAM permissions"
    fi

    # Test VPC permissions
    if aws ec2 describe-subnets --max-results 1 &> /dev/null; then
        log_success "VPC permissions: OK"
    else
        log_error "Missing VPC permissions"
    fi
}

check_aws_quotas() {
    print_header "📊 Checking AWS Service Quotas"

    local region=$(aws configure get region || echo "us-east-1")

    log_info "Checking quotas in region: $region"

    # VPCs
    local vpcs=$(aws ec2 describe-vpcs --region "$region" --query 'Vpcs | length(@)' --output text 2>/dev/null || echo "0")
    log_info "VPCs in use: $vpcs / 5 (default limit)"
    if [ "$vpcs" -ge 5 ]; then
        log_warning "VPC quota may be reached"
    fi

    # Elastic IPs
    local eips=$(aws ec2 describe-addresses --region "$region" --query 'Addresses | length(@)' --output text 2>/dev/null || echo "0")
    log_info "Elastic IPs in use: $eips / 5 (default limit)"
    if [ "$eips" -ge 5 ]; then
        log_warning "Elastic IP quota may be reached (need 3 for NAT Gateways)"
    fi

    # EKS clusters
    local clusters=$(aws eks list-clusters --region "$region" --query 'clusters | length(@)' --output text 2>/dev/null || echo "0")
    log_info "EKS clusters in use: $clusters / 100 (default limit)"

    # EC2 instance quota (simplified check)
    log_info "Note: Verify EC2 instance quotas in AWS Service Quotas console"
    log_info "  Required: m6i, c6i, r6i, m7g, c7g, r7g instance families"
}

check_terraform_state() {
    print_header "📁 Checking Terraform State"

    if [ -f "terraform/terraform.tfstate" ]; then
        log_warning "Existing Terraform state found"

        local resources=$(grep -c '"type":' terraform/terraform.tfstate 2>/dev/null || echo "0")
        log_info "Existing resources: $resources"

        if [ "$resources" -gt 0 ]; then
            log_warning "Infrastructure may already be deployed"
            log_info "Run './scripts/cleanup.sh' to destroy existing resources first"
        fi
    else
        log_success "No existing Terraform state (fresh deployment)"
    fi

    if [ -d "terraform/.terraform" ]; then
        log_info "Terraform initialized"
    else
        log_info "Terraform not initialized (will be initialized during deployment)"
    fi
}

check_disk_space() {
    print_header "💾 Checking Disk Space"

    local available=$(df -h . | tail -1 | awk '{print $4}')
    log_info "Available disk space: $available"

    # Convert to GB for comparison (simplified)
    local available_gb=$(df -g . | tail -1 | awk '{print $4}')
    if [ "$available_gb" -lt 5 ]; then
        log_warning "Low disk space (< 5GB available)"
    else
        log_success "Sufficient disk space"
    fi
}

check_network_connectivity() {
    print_header "🌐 Checking Network Connectivity"

    # Test AWS API
    if curl -s --max-time 5 https://sts.amazonaws.com > /dev/null; then
        log_success "AWS API reachable"
    else
        log_error "Cannot reach AWS API"
    fi

    # Test Terraform Registry
    if curl -s --max-time 5 https://registry.terraform.io > /dev/null; then
        log_success "Terraform Registry reachable"
    else
        log_error "Cannot reach Terraform Registry"
    fi

    # Test GitHub (for Karpenter CRDs)
    if curl -s --max-time 5 https://github.com > /dev/null; then
        log_success "GitHub reachable"
    else
        log_warning "Cannot reach GitHub (may affect Karpenter installation)"
    fi

    # Test Docker Hub (for container images)
    if curl -s --max-time 5 https://hub.docker.com > /dev/null; then
        log_success "Docker Hub reachable"
    else
        log_warning "Cannot reach Docker Hub"
    fi
}

check_cost_awareness() {
    print_header "💰 Cost Awareness Check"

    echo ""
    echo "Estimated Monthly Costs (us-east-1):"
    echo "  ├─ EKS Control Plane:     ~\$73/month"
    echo "  ├─ NAT Gateways (3):      ~\$100-150/month"
    echo "  ├─ EC2 Nodes:             Variable (depends on workload)"
    echo "  │  ├─ m6i.large:          ~\$70/month each"
    echo "  │  ├─ m7g.large:          ~\$50/month each (Graviton)"
    echo "  │  └─ Spot instances:     30-70% discount"
    echo "  └─ Data Transfer:         Variable"
    echo ""
    echo "Total Estimated: \$200-500/month (dev environment)"
    echo "                 \$500-2000/month (production environment)"
    echo ""

    log_warning "Review AWS Cost Explorer regularly"
    log_info "Recommendation: Set up AWS Budget alerts"
}

estimate_deployment_time() {
    print_header "⏱️  Deployment Time Estimate"

    echo ""
    echo "Estimated deployment phases:"
    echo "  1. Terraform init:         ~2 minutes"
    echo "  2. Terraform plan:         ~1 minute"
    echo "  3. VPC creation:           ~5 minutes"
    echo "  4. EKS cluster:            ~10-15 minutes"
    echo "  5. Karpenter setup:        ~3 minutes"
    echo "  6. NodePool deployment:    ~1 minute"
    echo "  7. First node provision:   ~1 minute"
    echo ""
    echo "Total estimated time: 20-30 minutes"
    echo ""
}

print_summary() {
    print_header "📊 Pre-flight Check Summary"

    echo "Checks passed:   $CHECKS_PASSED"
    echo "Checks failed:   $CHECKS_FAILED"
    echo "Warnings:        $CHECKS_WARNING"
    echo ""

    if [ "$CHECKS_FAILED" -eq 0 ]; then
        log_success "All critical checks passed! ✨"
        echo ""
        echo "You're ready to deploy!"
        echo ""
        echo "Next steps:"
        echo "  1. Review the deployment plan: ./scripts/deploy.sh --help"
        echo "  2. Start deployment: ./scripts/deploy.sh"
        echo ""
        return 0
    else
        log_error "$CHECKS_FAILED check(s) failed"
        echo ""
        echo "Please fix the issues above before deploying."
        echo ""
        return 1
    fi
}

##############################################################################
# Main execution
##############################################################################

main() {
    print_header "🚀 Platform-Design Pre-flight Check"

    echo "Checking environment readiness for deployment..."
    echo "Started: $(date)"
    echo ""

    # Run all checks
    check_required_tools
    check_aws_credentials
    check_aws_permissions
    check_aws_quotas
    check_terraform_state
    check_disk_space
    check_network_connectivity
    check_cost_awareness
    estimate_deployment_time

    # Print summary
    echo ""
    print_summary
}

main
