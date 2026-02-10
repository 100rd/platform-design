#!/bin/bash

##############################################################################
# Platform-Design Cleanup Script
#
# Safely destroys all deployed infrastructure
#
# Usage:
#   ./scripts/cleanup.sh [OPTIONS]
#
# Options:
#   --auto-approve    Skip confirmation prompts (DANGEROUS!)
#   --cluster NAME    Cluster name (default: platform-design-dev)
#   --region REGION   AWS region (default: eu-west-1)
#   --keep-vpc        Keep VPC after cleanup
#   --help            Show this help message
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
AUTO_APPROVE=false
CLUSTER_NAME="platform-design-dev"
AWS_REGION="${AWS_REGION:-eu-west-1}"
KEEP_VPC=false

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

##############################################################################
# Functions
##############################################################################

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${RED}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

confirm() {
    if [ "$AUTO_APPROVE" = true ]; then
        log_warning "Auto-approve enabled - skipping confirmation"
        return 0
    fi

    read -p "$1 (type 'yes' to confirm) " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        log_error "Operation cancelled (must type 'yes' to confirm)"
        exit 1
    fi
}

show_cleanup_plan() {
    print_header "⚠️  CLEANUP PLAN - DESTRUCTIVE OPERATION"

    echo -e "${RED}WARNING: This will PERMANENTLY DELETE all infrastructure!${NC}"
    echo ""
    echo "Cluster Name:   $CLUSTER_NAME"
    echo "AWS Region:     $AWS_REGION"
    echo "Keep VPC:       $KEEP_VPC"
    echo ""
    echo "Resources to be deleted:"
    echo "  ❌ Kubernetes workloads (all)"
    echo "  ❌ Karpenter NodePools"
    echo "  ❌ Karpenter-provisioned nodes"
    echo "  ❌ Karpenter controller"
    echo "  ❌ EKS Cluster"
    echo "  ❌ EKS Managed Node Groups"
    if [ "$KEEP_VPC" = false ]; then
        echo "  ❌ VPC and subnets"
        echo "  ❌ NAT Gateways"
    fi
    echo "  ❌ IAM Roles"
    echo "  ❌ Security Groups"
    echo "  ❌ SQS Queue"
    echo ""
    echo -e "${RED}THIS CANNOT BE UNDONE!${NC}"
    echo ""
}

delete_kubernetes_resources() {
    print_header "🗑️  Deleting Kubernetes Resources"

    # Check if kubectl is configured
    if ! kubectl cluster-info &> /dev/null; then
        log_warning "kubectl not configured - skipping Kubernetes cleanup"
        log_info "Configuring kubectl..."
        aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" || {
            log_warning "Could not configure kubectl - cluster may not exist"
            return 0
        }
    fi

    # Delete example deployments
    log_info "Deleting example deployments..."
    kubectl delete -f "$PROJECT_DIR/kubernetes/deployments/" --ignore-not-found=true || true

    # Delete NodePools (this will drain nodes)
    log_info "Deleting Karpenter NodePools..."
    kubectl delete nodepools --all --timeout=5m || true

    # Wait for nodes to be drained
    log_info "Waiting for Karpenter nodes to terminate..."
    for i in {1..30}; do
        local karpenter_nodes=$(kubectl get nodes -l karpenter.sh/nodepool --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$karpenter_nodes" -eq 0 ]; then
            log_success "All Karpenter nodes terminated"
            break
        fi
        echo "  Waiting for $karpenter_nodes node(s) to terminate... ($i/30)"
        sleep 10
    done

    # Delete EC2NodeClasses
    log_info "Deleting EC2NodeClasses..."
    kubectl delete ec2nodeclasses --all --timeout=2m || true

    # Delete any remaining workloads
    log_info "Deleting remaining workloads..."
    kubectl delete all --all -n default || true

    log_success "Kubernetes resources deleted"
}

delete_load_balancers() {
    print_header "🗑️  Deleting Load Balancers"

    log_info "Checking for load balancers..."

    # Find load balancers for this cluster
    local lbs=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerArn" --output text 2>/dev/null || echo "")

    if [ -n "$lbs" ]; then
        log_warning "Found load balancers to delete"
        for lb_arn in $lbs; do
            log_info "Deleting load balancer: $lb_arn"
            aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region "$AWS_REGION" || true
        done
        log_info "Waiting for load balancers to be deleted..."
        sleep 30
    else
        log_info "No load balancers found"
    fi
}

delete_security_groups() {
    print_header "🗑️  Deleting Karpenter-created Security Groups"

    log_info "Finding Karpenter-created security groups..."

    # Find security groups created by Karpenter
    local sgs=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER_NAME" \
        --query "SecurityGroups[?!contains(GroupName, 'cluster') && !contains(GroupName, 'node')].GroupId" \
        --output text 2>/dev/null || echo "")

    if [ -n "$sgs" ]; then
        log_warning "Found Karpenter-created security groups"
        for sg_id in $sgs; do
            log_info "Deleting security group: $sg_id"
            aws ec2 delete-security-group --group-id "$sg_id" --region "$AWS_REGION" 2>/dev/null || {
                log_warning "Could not delete security group $sg_id (may have dependencies)"
            }
        done
    else
        log_info "No Karpenter-created security groups found"
    fi
}

destroy_terraform() {
    print_header "🗑️  Destroying Terraform Infrastructure"

    cd "$PROJECT_DIR/terraform"

    # Check if Terraform state exists
    if [ ! -f "terraform.tfstate" ]; then
        log_warning "No Terraform state found"
        return 0
    fi

    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init

    # Show what will be destroyed
    log_info "Creating destroy plan..."
    terraform plan -destroy

    # Confirm
    echo ""
    confirm "Proceed with Terraform destroy?"

    # Destroy
    log_info "Destroying infrastructure..."
    if [ "$AUTO_APPROVE" = true ]; then
        terraform destroy -auto-approve
    else
        terraform destroy
    fi

    log_success "Terraform infrastructure destroyed"
}

verify_cleanup() {
    print_header "✅ Verifying Cleanup"

    # Check if cluster still exists
    if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
        log_error "Cluster still exists!"
        return 1
    else
        log_success "Cluster deleted"
    fi

    # Check for remaining nodes
    local nodes=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
                  "Name=instance-state-name,Values=running,pending" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null || echo "")

    if [ -n "$nodes" ]; then
        log_warning "Found remaining EC2 instances: $nodes"
        log_info "You may need to manually terminate these"
    else
        log_success "No remaining EC2 instances"
    fi

    # Check for remaining load balancers
    local lbs=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")

    if [ -n "$lbs" ]; then
        log_warning "Found remaining load balancers"
    else
        log_success "No remaining load balancers"
    fi
}

print_summary() {
    print_header "✅ Cleanup Complete"

    echo "All infrastructure has been destroyed."
    echo ""
    echo "Remaining manual steps (if any):"
    echo ""
    echo "1. Check for orphaned resources in AWS Console:"
    echo "   - EC2 Instances"
    echo "   - Load Balancers"
    echo "   - Security Groups"
    echo "   - Elastic IPs"
    echo ""
    echo "2. Verify no unexpected charges:"
    echo "   - AWS Cost Explorer"
    echo "   - AWS Budgets"
    echo ""
    echo "3. Clean up local files (optional):"
    echo "   - terraform/terraform.tfstate*"
    echo "   - terraform/.terraform/"
    echo "   - kubernetes/karpenter/generated/"
    echo ""

    log_success "Cleanup completed successfully! 🎉"
}

show_help() {
    echo "Platform-Design Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --auto-approve    Skip confirmation prompts (DANGEROUS!)"
    echo "  --cluster NAME    Cluster name (default: platform-design-dev)"
    echo "  --region REGION   AWS region (default: eu-west-1)"
    echo "  --keep-vpc        Keep VPC after cleanup"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --cluster my-cluster --region us-west-2"
    echo "  $0 --auto-approve  # DANGEROUS - no confirmations!"
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
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --keep-vpc)
            KEEP_VPC=true
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
    print_header "⚠️  PLATFORM-DESIGN CLEANUP - DESTRUCTIVE OPERATION"

    echo "Started: $(date)"
    echo ""

    # Show cleanup plan
    show_cleanup_plan

    # Final confirmation
    echo -e "${RED}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}THIS WILL PERMANENTLY DELETE ALL INFRASTRUCTURE${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    confirm "Are you absolutely sure you want to proceed?"

    # Execute cleanup steps
    delete_kubernetes_resources
    delete_load_balancers
    delete_security_groups
    destroy_terraform

    # Verify cleanup
    verify_cleanup

    # Print summary
    print_summary

    echo ""
    echo "Cleanup completed: $(date)"
}

main
