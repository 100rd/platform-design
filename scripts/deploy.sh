#!/bin/bash

##############################################################################
# Platform-Design Deployment Script
#
# Deploys complete EKS + Karpenter infrastructure with multi-architecture support
#
# Usage:
#   ./scripts/deploy.sh [OPTIONS]
#
# Options:
#   --auto-approve    Skip confirmation prompts
#   --region REGION   AWS region (default: us-east-1)
#   --cluster NAME    Cluster name (default: platform-design-dev)
#   --skip-tests      Skip post-deployment tests
#   --help            Show this help message
#
##############################################################################

set -e  # Exit on error
set -o pipefail  # Catch errors in pipes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AUTO_APPROVE=false
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="platform-design-dev"
SKIP_TESTS=false

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

##############################################################################
# Functions
##############################################################################

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

confirm() {
    if [ "$AUTO_APPROVE" = true ]; then
        return 0
    fi

    read -p "$1 (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Operation cancelled by user"
        exit 1
    fi
}

check_prerequisites() {
    print_header "🔍 Checking Prerequisites"

    local missing_tools=()

    # Check required tools
    for tool in terraform aws kubectl jq; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
            log_error "$tool is not installed"
        else
            local version=$($tool --version 2>&1 | head -n1)
            log_success "$tool: $version"
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Install missing tools:"
        echo "  - terraform: https://www.terraform.io/downloads"
        echo "  - aws: https://aws.amazon.com/cli/"
        echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "  - jq: https://stedolan.github.io/jq/"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        echo "Run: aws configure"
        exit 1
    else
        local aws_account=$(aws sts get-caller-identity --query Account --output text)
        local aws_user=$(aws sts get-caller-identity --query Arn --output text)
        log_success "AWS Account: $aws_account"
        log_success "AWS User: $aws_user"
    fi

    # Check Terraform version
    local tf_version=$(terraform version -json | jq -r '.terraform_version')
    if [ "$(printf '%s\n' "1.3.0" "$tf_version" | sort -V | head -n1)" != "1.3.0" ]; then
        log_error "Terraform version must be >= 1.3.0 (found: $tf_version)"
        exit 1
    fi

    log_success "All prerequisites met"
}

show_deployment_plan() {
    print_header "📋 Deployment Plan"

    echo "AWS Region:     $AWS_REGION"
    echo "Cluster Name:   $CLUSTER_NAME"
    echo "Terraform Dir:  $PROJECT_DIR/terraform"
    echo ""
    echo "Resources to be created:"
    echo "  - VPC with 3 public + 3 private subnets"
    echo "  - NAT Gateways (3)"
    echo "  - EKS Cluster v1.34"
    echo "  - EKS Managed Node Group (for Karpenter controller)"
    echo "  - Karpenter controller (Helm)"
    echo "  - Karpenter NodePools (x86 + ARM64)"
    echo "  - IAM Roles (3+)"
    echo "  - Security Groups"
    echo "  - SQS Queue (spot interruption handling)"
    echo ""
    echo "Estimated deployment time: 20-30 minutes"
    echo "Estimated cost: \$200-500/month"
    echo ""
}

deploy_terraform() {
    print_header "🚀 Deploying Terraform Infrastructure"

    cd "$PROJECT_DIR/terraform"

    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init -upgrade

    # Validate configuration
    log_info "Validating configuration..."
    terraform validate

    # Format code
    log_info "Formatting code..."
    terraform fmt -recursive

    # Create plan
    log_info "Creating execution plan..."
    terraform plan \
        -var="cluster_name=$CLUSTER_NAME" \
        -var="region=$AWS_REGION" \
        -out=tfplan

    # Show plan summary
    echo ""
    log_warning "Review the plan above carefully!"
    confirm "Proceed with deployment?"

    # Apply
    log_info "Applying Terraform configuration..."
    terraform apply tfplan

    # Clean up plan file
    rm -f tfplan

    log_success "Infrastructure deployment complete"
}

configure_kubectl() {
    print_header "⚙️  Configuring kubectl"

    log_info "Updating kubeconfig..."
    aws eks update-kubeconfig \
        --name "$CLUSTER_NAME" \
        --region "$AWS_REGION"

    # Verify connection
    log_info "Verifying cluster connection..."
    if kubectl cluster-info &> /dev/null; then
        log_success "Successfully connected to cluster"
        kubectl get nodes
    else
        log_error "Failed to connect to cluster"
        exit 1
    fi
}

deploy_karpenter_nodepools() {
    print_header "🎯 Deploying Karpenter NodePools"

    cd "$PROJECT_DIR"

    # Check if templates are already rendered
    if [ -f "kubernetes/karpenter/generated/x86-nodepool.yaml" ]; then
        log_info "Using pre-rendered NodePool manifests..."

        log_info "Deploying x86 NodePool..."
        kubectl apply -f kubernetes/karpenter/generated/x86-nodepool.yaml

        log_info "Deploying ARM64 NodePool..."
        kubectl apply -f kubernetes/karpenter/generated/arm64-nodepool.yaml
    else
        log_warning "NodePool templates not rendered yet"
        log_info "Rendering templates now..."

        # Export Terraform outputs as environment variables
        cd "$PROJECT_DIR/terraform"
        export CLUSTER_NAME=$(terraform output -raw cluster_name)
        export NODE_ROLE_NAME=$(terraform output -raw karpenter_node_iam_role_name)
        export REGION=$(terraform output -raw region)

        cd "$PROJECT_DIR"

        # Render templates
        bash kubernetes/karpenter/templates/render-templates.sh

        # Apply rendered manifests
        log_info "Deploying x86 NodePool..."
        kubectl apply -f kubernetes/karpenter/generated/x86-nodepool.yaml

        log_info "Deploying ARM64 NodePool..."
        kubectl apply -f kubernetes/karpenter/generated/arm64-nodepool.yaml
    fi

    log_success "NodePools deployed"
}

verify_deployment() {
    print_header "✅ Verifying Deployment"

    # Check Karpenter controller
    log_info "Checking Karpenter controller..."
    local karpenter_pods=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter --no-headers | wc -l)
    if [ "$karpenter_pods" -ge 1 ]; then
        log_success "Karpenter controller running ($karpenter_pods pods)"
        kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
    else
        log_error "Karpenter controller not found"
        return 1
    fi

    # Check NodePools
    log_info "Checking NodePools..."
    local nodepools=$(kubectl get nodepools --no-headers | wc -l)
    if [ "$nodepools" -ge 2 ]; then
        log_success "NodePools created ($nodepools)"
        kubectl get nodepools
    else
        log_warning "Expected 2 NodePools, found $nodepools"
        kubectl get nodepools
    fi

    # Check nodes
    log_info "Checking cluster nodes..."
    kubectl get nodes -o wide

    # Show Karpenter logs
    log_info "Recent Karpenter logs:"
    kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=20
}

run_tests() {
    print_header "🧪 Running Post-Deployment Tests"

    cd "$PROJECT_DIR"

    # Test 1: Deploy x86 example
    log_info "Test 1: Deploying x86 example workload..."
    kubectl apply -f kubernetes/deployments/x86-example.yaml

    # Wait for pods
    log_info "Waiting for x86 pods to start..."
    kubectl wait --for=condition=ready pod -l app=x86-nginx --timeout=300s || true

    # Check nodes
    log_info "Checking x86 nodes..."
    kubectl get nodes -l kubernetes.io/arch=amd64

    # Test 2: Deploy ARM64 example
    log_info "Test 2: Deploying ARM64 example workload..."
    kubectl apply -f kubernetes/deployments/arm64-graviton-example.yaml

    # Wait for pods
    log_info "Waiting for ARM64 pods to start..."
    kubectl wait --for=condition=ready pod -l app=arm64-nginx --timeout=300s || true

    # Check nodes
    log_info "Checking ARM64 nodes..."
    kubectl get nodes -l kubernetes.io/arch=arm64

    # Show all nodes
    log_info "All nodes:"
    kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
ARCH:.metadata.labels.kubernetes\\.io/arch,\
INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type

    log_success "Tests completed"
}

print_next_steps() {
    print_header "🎉 Deployment Complete!"

    echo "Next steps:"
    echo ""
    echo "1. View cluster resources:"
    echo "   kubectl get all --all-namespaces"
    echo ""
    echo "2. Check Karpenter status:"
    echo "   kubectl get nodepools"
    echo "   kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f"
    echo ""
    echo "3. View example applications:"
    echo "   kubectl get pods -o wide"
    echo "   kubectl get svc"
    echo ""
    echo "4. Test auto-scaling:"
    echo "   kubectl scale deployment x86-nginx-example --replicas=10"
    echo "   watch kubectl get nodes"
    echo ""
    echo "5. Access Terraform outputs:"
    echo "   cd terraform && terraform output"
    echo ""
    echo "6. Monitor costs:"
    echo "   aws ce get-cost-and-usage --time-period Start=\$(date -v-7d +%Y-%m-%d),End=\$(date +%Y-%m-%d) --granularity DAILY --metrics BlendedCost"
    echo ""

    if [ -f "$PROJECT_DIR/KARPENTER_IMPLEMENTATION.md" ]; then
        echo "📚 For more information, see:"
        echo "   - KARPENTER_IMPLEMENTATION.md (comprehensive guide)"
        echo "   - DEPLOYMENT_CHECKLIST.md (deployment checklist)"
        echo "   - kubernetes/KARPENTER_USAGE.md (usage guide)"
    fi
    echo ""
}

show_help() {
    echo "Platform-Design Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --auto-approve     Skip confirmation prompts"
    echo "  --region REGION    AWS region (default: us-east-1)"
    echo "  --cluster NAME     Cluster name (default: platform-design-dev)"
    echo "  --skip-tests       Skip post-deployment tests"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --region us-west-2 --cluster my-cluster"
    echo "  $0 --auto-approve --skip-tests"
    echo ""
}

##############################################################################
# Parse arguments
##############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

##############################################################################
# Main execution
##############################################################################

main() {
    print_header "🚀 Platform-Design Deployment"

    echo "Starting deployment at $(date)"
    echo ""

    # Run pre-flight checks
    check_prerequisites

    # Show what will be deployed
    show_deployment_plan
    confirm "Start deployment?"

    # Deploy infrastructure
    deploy_terraform

    # Configure kubectl
    configure_kubectl

    # Deploy Karpenter NodePools
    deploy_karpenter_nodepools

    # Verify everything is working
    verify_deployment

    # Run tests unless skipped
    if [ "$SKIP_TESTS" = false ]; then
        run_tests
    else
        log_warning "Skipping post-deployment tests (--skip-tests flag set)"
    fi

    # Show next steps
    print_next_steps

    echo ""
    echo "Deployment completed at $(date)"
    log_success "All done! 🎉"
}

# Run main function
main
