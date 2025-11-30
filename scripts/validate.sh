#!/bin/bash

##############################################################################
# Platform-Design Validation Script
#
# Validates the deployed infrastructure and Karpenter configuration
#
# Usage:
#   ./scripts/validate.sh [--cluster NAME] [--region REGION]
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

# Defaults
CLUSTER_NAME="${CLUSTER_NAME:-platform-design-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

##############################################################################
# Functions
##############################################################################

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; PASSED=$((PASSED+1)); }
log_error() { echo -e "${RED}✗${NC} $1"; FAILED=$((FAILED+1)); }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; WARNINGS=$((WARNINGS+1)); }

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

check_aws_connection() {
    print_header "🔍 Checking AWS Connection"

    if aws sts get-caller-identity &> /dev/null; then
        local account=$(aws sts get-caller-identity --query Account --output text)
        log_success "AWS Account: $account"
    else
        log_error "Cannot connect to AWS"
        return 1
    fi
}

check_cluster_status() {
    print_header "🔍 Checking EKS Cluster"

    # Check cluster exists
    if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
        log_success "Cluster '$CLUSTER_NAME' exists"

        # Check cluster status
        local status=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.status' --output text)
        if [ "$status" = "ACTIVE" ]; then
            log_success "Cluster status: ACTIVE"
        else
            log_error "Cluster status: $status (expected ACTIVE)"
        fi

        # Check version
        local version=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.version' --output text)
        log_info "Cluster version: $version"

        # Check endpoint
        local endpoint=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.endpoint' --output text)
        log_info "Cluster endpoint: $endpoint"

    else
        log_error "Cluster '$CLUSTER_NAME' not found in region $AWS_REGION"
        return 1
    fi
}

check_kubectl_access() {
    print_header "🔍 Checking kubectl Access"

    if kubectl cluster-info &> /dev/null; then
        log_success "kubectl can access the cluster"

        # Check current context
        local context=$(kubectl config current-context)
        log_info "Current context: $context"
    else
        log_error "kubectl cannot access the cluster"
        log_info "Run: aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION"
        return 1
    fi
}

check_nodes() {
    print_header "🔍 Checking Cluster Nodes"

    local total_nodes=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')

    if [ "$total_nodes" -gt 0 ]; then
        log_success "Found $total_nodes node(s)"

        # Show node details
        echo ""
        kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.conditions[-1].type,\
ARCH:.metadata.labels.kubernetes\\.io/arch,\
INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type

        # Check for both architectures if multiple nodes
        if [ "$total_nodes" -gt 1 ]; then
            local amd64_nodes=$(kubectl get nodes -l kubernetes.io/arch=amd64 --no-headers | wc -l | tr -d ' ')
            local arm64_nodes=$(kubectl get nodes -l kubernetes.io/arch=arm64 --no-headers | wc -l | tr -d ' ')

            if [ "$amd64_nodes" -gt 0 ]; then
                log_success "x86/amd64 nodes: $amd64_nodes"
            fi

            if [ "$arm64_nodes" -gt 0 ]; then
                log_success "ARM64 nodes: $arm64_nodes"
            fi
        fi
    else
        log_error "No nodes found"
        return 1
    fi
}

check_karpenter_controller() {
    print_header "🔍 Checking Karpenter Controller"

    # Check Karpenter pods
    local karpenter_pods=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [ "$karpenter_pods" -gt 0 ]; then
        log_success "Karpenter controller pods: $karpenter_pods"

        # Check pod status
        local ready_pods=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter --no-headers 2>/dev/null | grep -c "Running" || echo "0")

        if [ "$ready_pods" -eq "$karpenter_pods" ]; then
            log_success "All Karpenter pods are running"
        else
            log_warning "$ready_pods/$karpenter_pods pods running"
        fi

        # Show pod details
        echo ""
        kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter

        # Check for errors in logs
        log_info "Checking for errors in Karpenter logs..."
        local errors=$(kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100 2>/dev/null | grep -i "error" | wc -l | tr -d ' ')
        if [ "$errors" -gt 0 ]; then
            log_warning "Found $errors error messages in recent logs"
        else
            log_success "No errors in recent logs"
        fi
    else
        log_error "Karpenter controller not found"
        return 1
    fi
}

check_nodepools() {
    print_header "🔍 Checking Karpenter NodePools"

    # Check if NodePool CRD exists
    if ! kubectl get crd nodepools.karpenter.sh &> /dev/null; then
        log_error "NodePool CRD not installed"
        return 1
    fi

    # Check NodePools
    local nodepools=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [ "$nodepools" -gt 0 ]; then
        log_success "Found $nodepools NodePool(s)"

        # Show NodePool details
        echo ""
        kubectl get nodepools

        # Check for specific NodePools
        if kubectl get nodepool x86-general-purpose &> /dev/null; then
            log_success "x86-general-purpose NodePool exists"
        else
            log_warning "x86-general-purpose NodePool not found"
        fi

        if kubectl get nodepool arm64-graviton &> /dev/null; then
            log_success "arm64-graviton NodePool exists"
        else
            log_warning "arm64-graviton NodePool not found"
        fi
    else
        log_error "No NodePools found"
        log_info "Deploy NodePools: kubectl apply -f kubernetes/karpenter/"
        return 1
    fi
}

check_ec2nodeclasses() {
    print_header "🔍 Checking EC2NodeClasses"

    # Check if EC2NodeClass CRD exists
    if ! kubectl get crd ec2nodeclasses.karpenter.k8s.aws &> /dev/null; then
        log_error "EC2NodeClass CRD not installed"
        return 1
    fi

    # Check EC2NodeClasses
    local nodeclasses=$(kubectl get ec2nodeclasses --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [ "$nodeclasses" -gt 0 ]; then
        log_success "Found $nodeclasses EC2NodeClass(es)"

        # Show details
        echo ""
        kubectl get ec2nodeclasses
    else
        log_error "No EC2NodeClasses found"
        return 1
    fi
}

check_example_deployments() {
    print_header "🔍 Checking Example Deployments"

    # Check x86 example
    if kubectl get deployment x86-nginx-example &> /dev/null; then
        log_success "x86-nginx-example deployment exists"

        local desired=$(kubectl get deployment x86-nginx-example -o jsonpath='{.spec.replicas}')
        local ready=$(kubectl get deployment x86-nginx-example -o jsonpath='{.status.readyReplicas}')

        if [ "$ready" = "$desired" ]; then
            log_success "x86-nginx-example: $ready/$desired pods ready"
        else
            log_warning "x86-nginx-example: $ready/$desired pods ready"
        fi
    else
        log_info "x86-nginx-example deployment not found (optional)"
    fi

    # Check ARM64 example
    if kubectl get deployment arm64-nginx-example &> /dev/null; then
        log_success "arm64-nginx-example deployment exists"

        local desired=$(kubectl get deployment arm64-nginx-example -o jsonpath='{.spec.replicas}')
        local ready=$(kubectl get deployment arm64-nginx-example -o jsonpath='{.status.readyReplicas}')

        if [ "$ready" = "$desired" ]; then
            log_success "arm64-nginx-example: $ready/$desired pods ready"
        else
            log_warning "arm64-nginx-example: $ready/$desired pods ready"
        fi
    else
        log_info "arm64-nginx-example deployment not found (optional)"
    fi
}

check_networking() {
    print_header "🔍 Checking Networking"

    # Check VPC CNI
    local vpc_cni_pods=$(kubectl get pods -n kube-system -l k8s-app=aws-node --no-headers | wc -l | tr -d ' ')
    if [ "$vpc_cni_pods" -gt 0 ]; then
        log_success "VPC CNI pods running: $vpc_cni_pods"
    else
        log_error "VPC CNI pods not found"
    fi

    # Check CoreDNS
    local coredns_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | wc -l | tr -d ' ')
    if [ "$coredns_pods" -gt 0 ]; then
        log_success "CoreDNS pods running: $coredns_pods"
    else
        log_error "CoreDNS pods not found"
    fi

    # Check kube-proxy
    local kube_proxy_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers | wc -l | tr -d ' ')
    if [ "$kube_proxy_pods" -gt 0 ]; then
        log_success "kube-proxy pods running: $kube_proxy_pods"
    else
        log_error "kube-proxy pods not found"
    fi
}

check_iam_roles() {
    print_header "🔍 Checking IAM Roles"

    # Get Terraform outputs if available
    if [ -f "terraform/terraform.tfstate" ]; then
        cd terraform

        # Check Karpenter controller role
        if terraform output karpenter_controller_role_arn &> /dev/null; then
            local role_arn=$(terraform output -raw karpenter_controller_role_arn)
            log_success "Karpenter controller role: $role_arn"
        else
            log_warning "Karpenter controller role output not found"
        fi

        # Check node IAM role
        if terraform output karpenter_node_iam_role_name &> /dev/null; then
            local role_name=$(terraform output -raw karpenter_node_iam_role_name)
            log_success "Karpenter node role: $role_name"
        else
            log_warning "Karpenter node role output not found"
        fi

        cd ..
    else
        log_info "Terraform state not found (skipping IAM role checks)"
    fi
}

print_summary() {
    print_header "📊 Validation Summary"

    echo "Tests passed:    $PASSED"
    echo "Tests failed:    $FAILED"
    echo "Warnings:        $WARNINGS"
    echo ""

    if [ "$FAILED" -eq 0 ]; then
        log_success "All critical checks passed! ✨"
        return 0
    else
        log_error "$FAILED check(s) failed"
        return 1
    fi
}

##############################################################################
# Parse arguments
##############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--cluster NAME] [--region REGION]"
            exit 1
            ;;
    esac
done

##############################################################################
# Main execution
##############################################################################

main() {
    print_header "🔍 Platform-Design Validation"

    echo "Cluster:  $CLUSTER_NAME"
    echo "Region:   $AWS_REGION"
    echo "Started:  $(date)"
    echo ""

    # Run all checks
    check_aws_connection
    check_cluster_status
    check_kubectl_access
    check_nodes
    check_karpenter_controller
    check_nodepools
    check_ec2nodeclasses
    check_example_deployments
    check_networking
    check_iam_roles

    # Print summary
    echo ""
    print_summary
}

main
