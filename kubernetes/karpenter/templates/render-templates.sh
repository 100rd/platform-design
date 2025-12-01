#!/bin/bash
# Render Karpenter NodePool templates with Terraform outputs
# Usage: ./render-templates.sh [terraform-dir]

set -e

TERRAFORM_DIR="${1:-../../../terraform}"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$(dirname "$TEMPLATE_DIR")"

echo "Karpenter NodePool Template Renderer"
echo "====================================="
echo ""

# Check if terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "Error: Terraform directory not found: $TERRAFORM_DIR"
    echo "Usage: $0 [terraform-dir]"
    exit 1
fi

# Navigate to Terraform directory
cd "$TERRAFORM_DIR"

# Check if Terraform is initialized
if [ ! -d ".terraform" ]; then
    echo "Error: Terraform not initialized. Run 'terraform init' first."
    exit 1
fi

echo "Extracting Terraform outputs..."

# Get Terraform outputs
NODE_ROLE_NAME=$(terraform output -raw karpenter_node_iam_role_name 2>/dev/null || echo "")
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
REGION=$(terraform output -raw region 2>/dev/null || echo "")
CLUSTER_ENDPOINT=$(terraform output -raw eks_cluster_endpoint 2>/dev/null || echo "")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")

# Validate required outputs
if [ -z "$NODE_ROLE_NAME" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$REGION" ]; then
    echo "Error: Missing required Terraform outputs."
    echo ""
    echo "Required outputs:"
    echo "  - karpenter_node_iam_role_name: ${NODE_ROLE_NAME:-NOT FOUND}"
    echo "  - cluster_name: ${CLUSTER_NAME:-NOT FOUND}"
    echo "  - region: ${REGION:-NOT FOUND}"
    echo ""
    echo "Run 'terraform apply' first to create the infrastructure."
    exit 1
fi

echo "Using values:"
echo "  Node IAM Role: $NODE_ROLE_NAME"
echo "  Cluster Name:  $CLUSTER_NAME"
echo "  Region:        $REGION"
echo "  VPC ID:        $VPC_ID"
echo ""

# Export variables for envsubst
export node_role_name="$NODE_ROLE_NAME"
export cluster_name="$CLUSTER_NAME"
export region="$REGION"
export cluster_endpoint="$CLUSTER_ENDPOINT"
export vpc_id="$VPC_ID"

# Render x86 NodePool
echo "Rendering x86 NodePool..."
envsubst < "$TEMPLATE_DIR/x86-nodepool.yaml.tpl" > "$OUTPUT_DIR/x86-nodepool-rendered.yaml"
echo "  -> $OUTPUT_DIR/x86-nodepool-rendered.yaml"

# Render ARM64 NodePool
echo "Rendering ARM64 NodePool..."
envsubst < "$TEMPLATE_DIR/arm64-nodepool.yaml.tpl" > "$OUTPUT_DIR/arm64-nodepool-rendered.yaml"
echo "  -> $OUTPUT_DIR/arm64-nodepool-rendered.yaml"

# Render C-series NodePool
echo "Rendering C-series NodePool..."
envsubst < "$TEMPLATE_DIR/c-series-nodepool.yaml.tpl" > "$OUTPUT_DIR/c-series-nodepool-rendered.yaml"
echo "  -> $OUTPUT_DIR/c-series-nodepool-rendered.yaml"

# Render Spot NodePool
echo "Rendering Spot NodePool..."
envsubst < "$TEMPLATE_DIR/spot-nodepool.yaml.tpl" > "$OUTPUT_DIR/spot-nodepool-rendered.yaml"
echo "  -> $OUTPUT_DIR/spot-nodepool-rendered.yaml"

echo ""
echo "Templates rendered successfully!"
echo ""
echo "To apply to your cluster:"
echo "  kubectl apply -f $OUTPUT_DIR/x86-nodepool-rendered.yaml"
echo "  kubectl apply -f $OUTPUT_DIR/arm64-nodepool-rendered.yaml"
echo "  kubectl apply -f $OUTPUT_DIR/c-series-nodepool-rendered.yaml"
echo "  kubectl apply -f $OUTPUT_DIR/spot-nodepool-rendered.yaml"
echo ""
echo "To verify:"
echo "  kubectl get nodepool"
echo "  kubectl get ec2nodeclass"
echo ""
echo "To test autoscaling:"
echo "  kubectl apply -f - <<EOF"
echo "  apiVersion: apps/v1"
echo "  kind: Deployment"
echo "  metadata:"
echo "    name: inflate-test"
echo "  spec:"
echo "    replicas: 5"
echo "    selector:"
echo "      matchLabels:"
echo "        app: inflate"
echo "    template:"
echo "      metadata:"
echo "        labels:"
echo "          app: inflate"
echo "      spec:"
echo "        nodeSelector:"
echo "          karpenter.sh/nodepool: x86-general-purpose"
echo "        containers:"
echo "        - name: inflate"
echo "          image: public.ecr.aws/eks-distro/kubernetes/pause:3.7"
echo "          resources:"
echo "            requests:"
echo "              cpu: 1"
echo "  EOF"
