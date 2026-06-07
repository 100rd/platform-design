# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity — AWS Load Balancer Controller — ADR-0018
# ---------------------------------------------------------------------------------------------------------------------
# Last workload in the ADR-0018 cutover order (YACE -> observability stack -> ESO
# -> LB controller). Ingress-critical, so migrated last (highest blast radius).
#
# What this module creates:
#   1. An IAM role whose TRUST policy targets the EKS Auth service principal
#      `pods.eks.amazonaws.com` (NOT a per-cluster OIDC issuer), allowing both
#      `sts:AssumeRole` AND `sts:TagSession` (TagSession injects the ABAC tags).
#   2. The AWS Load Balancer Controller least-privilege policy: elasticloadbalancing
#      create/modify/delete + ec2 describe + wafv2/shield/acm/cognito read, scoped
#      by an ABAC kubernetes-namespace condition where the API supports conditions.
#   3. An `aws_eks_pod_identity_association` binding (cluster, namespace
#      `kube-system`, ServiceAccount `aws-load-balancer-controller`) -> the role.
#
# Note on ABAC scope: most LBC actions are describe/manage on ELBv2/EC2 resources
# whose ARNs are created at runtime; the controller is a singleton in kube-system,
# so the namespace ABAC condition pins it to the kube-system controller session.
#
# Coexistence (ADR-0018): IRSA stays supported for not-yet-migrated workloads. Do
# NOT configure both an IRSA annotation AND an association on the same SA. The LBC
# SA must not carry `eks.amazonaws.com/role-arn` once this association exists.
#
# Fargate caveat: Pod Identity is NOT supported on Fargate. Verify the LBC is not
# Fargate-scheduled before migrating.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  role_name = "${var.project}-${var.cluster_name}-${var.service_account}"

  default_tags = {
    ManagedBy        = "Terraform"
    Module           = "pod-identity-lb-controller"
    ADR              = "ADR-0018"
    WorkloadIdentity = "eks-pod-identity"
    Namespace        = var.namespace
    ServiceAccount   = var.service_account
  }
  effective_tags = merge(local.default_tags, var.tags)
}

# ---------------------------------------------------------------------------------------------------------------------
# Trust policy — EKS Pod Identity service principal
# ---------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "EksPodIdentityAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# AWS Load Balancer Controller permissions (ABAC namespace-scoped where supported)
# ---------------------------------------------------------------------------------------------------------------------
# Mirrors the upstream AWS Load Balancer Controller IAM policy, condensed to the
# action families it needs: ELBv2 provisioning, EC2/VPC describe for subnet and
# security-group resolution, security-group management for managed SGs, and the
# read-only integrations (WAFv2 / Shield / ACM / Cognito) the controller resolves
# when an Ingress requests them. Every statement is ABAC-scoped to sessions whose
# `kubernetes-namespace` tag == var.namespace (kube-system controller session).
data "aws_iam_policy_document" "lb_controller" {
  # EC2 / VPC describe — resolve subnets, security groups, AZs, ENIs.
  statement {
    sid    = "Ec2DescribeRead"
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "ec2:DescribeVpcEndpoints",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # Elastic Load Balancing — describe load balancers/target groups/listeners/rules.
  statement {
    sid    = "ElbDescribeRead"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores",
      "elasticloadbalancing:DescribeListenerAttributes",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # Elastic Load Balancing — provision/modify/delete (Ingress -> ALB, Service -> NLB).
  statement {
    sid    = "ElbProvision"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyListenerAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetWebAcl",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # Security groups — manage the LBC-managed SGs that front load balancers.
  statement {
    sid    = "SecurityGroupManage"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # Read-only integrations the controller resolves for Ingress annotations.
  statement {
    sid    = "IntegrationsRead"
    effect = "Allow"
    actions = [
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "cognito-idp:DescribeUserPoolClient",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM role + policy
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  name                 = local.role_name
  description          = "EKS Pod Identity role for the AWS Load Balancer Controller in namespace ${var.namespace} (ADR-0018)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration
  path                 = var.iam_path

  tags = local.effective_tags
}

resource "aws_iam_policy" "lb_controller" {
  name        = "${local.role_name}-lb-controller"
  description = "AWS Load Balancer Controller ELB/EC2 permissions, ABAC-scoped to the ${var.namespace} namespace (ADR-0018)"
  path        = var.iam_path
  policy      = data.aws_iam_policy_document.lb_controller.json

  tags = local.effective_tags
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# ---------------------------------------------------------------------------------------------------------------------
# Pod Identity association — binds (cluster, namespace, ServiceAccount) -> role
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this.arn

  tags = local.effective_tags
}
