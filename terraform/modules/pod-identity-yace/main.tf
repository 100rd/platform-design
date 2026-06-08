# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity — YACE (CloudWatch exporter) — ADR-0018
# ---------------------------------------------------------------------------------------------------------------------
# First workload migrated to EKS Pod Identity (the lowest-blast-radius canary in
# the ADR-0018 cutover order: YACE -> observability stack -> ESO -> LB controller).
#
# What this module creates:
#   1. An IAM role whose TRUST policy targets the EKS Auth service principal
#      `pods.eks.amazonaws.com` (NOT a per-cluster OIDC issuer), allowing both
#      `sts:AssumeRole` AND `sts:TagSession`. TagSession is REQUIRED so EKS can
#      inject the ABAC session tags (kubernetes-namespace, kubernetes-service-
#      account, eks-cluster-name, ...).
#   2. A CloudWatch read-only + tagging-read permissions policy (exactly what YACE
#      needs to discover resources and pull metrics).
#   3. An `aws_eks_pod_identity_association` binding (cluster, namespace
#      `observability`, ServiceAccount `yace`) -> the role above.
#
# Why no OIDC issuer in the trust policy (vs IRSA): with Pod Identity the trust is
# on the EKS service principal, so ONE role is portable across clusters. The
# per-cluster OIDC provider / `enable_irsa` can be dropped once a cluster's
# workloads are fully migrated (ADR-0018).
#
# Coexistence (ADR-0018): IRSA stays supported for not-yet-migrated workloads.
# Do NOT configure both an IRSA annotation AND an association on the same
# ServiceAccount — AWS leaves that precedence undocumented, so the YACE SA drops
# its `eks.amazonaws.com/role-arn` annotation as the final migration step.
#
# Fargate caveat: Pod Identity is NOT supported on Fargate (the agent is a
# node-level DaemonSet). YACE here runs on Graviton EC2/Karpenter nodes, so it is
# eligible; verify the schedule before reusing this pattern elsewhere.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  role_name = "${var.project}-${var.cluster_name}-${var.service_account}"

  default_tags = {
    ManagedBy        = "Terraform"
    Module           = "pod-identity-yace"
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
# Principal is the EKS Auth service (`pods.eks.amazonaws.com`), NOT a cluster OIDC
# issuer. `sts:TagSession` MUST accompany `sts:AssumeRole` so EKS can attach the
# ABAC session tags it injects on every pod credential vend.
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
# CloudWatch read-only + resource-tagging-read permissions (YACE)
# ---------------------------------------------------------------------------------------------------------------------
# YACE needs:
#   - cloudwatch:GetMetricData / ListMetrics / GetMetricStatistics — pull metrics
#   - tag:GetResources — discovery (find resources by tag)
#   - <service>:Describe*/List* — resolve resource dimensions (ELB/EBS/S3 here)
# These are scoped to read-only actions on "*" because CloudWatch metric APIs and
# the Resource Groups Tagging API are account/region-global and do not support
# per-resource ARNs in their IAM Resource field.
#
# ABAC DEMONSTRATION (ADR-0018) — narrowing identity to ONE namespace.
# A single role can serve many workloads if its policy is scoped on the session
# tags EKS injects. Below we add a `condition` so this role's CloudWatch access is
# only usable by a session whose `kubernetes-namespace` tag == var.namespace
# (i.e. the `observability` namespace). The tag is injected automatically by EKS
# because the trust policy allows `sts:TagSession`. This is the mechanism that, at
# scale, replaces role-per-workload: one ABAC-scoped role, condition-keyed on
# `aws:PrincipalTag/kubernetes-namespace` (and optionally
# `.../kubernetes-service-account`, `.../eks-cluster-name`).
data "aws_iam_policy_document" "cloudwatch_read" {
  statement {
    sid    = "CloudWatchMetricsRead"
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricStream",
      "cloudwatch:ListMetricStreams",
    ]
    resources = ["*"]

    # ABAC: scope this statement to sessions tagged for the observability
    # namespace. EKS injects `kubernetes-namespace` as a PrincipalTag on every
    # Pod Identity session (because the trust allows sts:TagSession).
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  statement {
    sid    = "ResourceTaggingRead"
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "tag:GetTagKeys",
      "tag:GetTagValues",
    ]
    resources = ["*"]

    # Same ABAC namespace guard on the discovery (tagging) statement.
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # Describe/List for the services YACE discovers (ELB v1/v2, EBS via EC2, S3
  # bucket metadata). Read-only; required to resolve metric dimensions to
  # resource identifiers.
  statement {
    sid    = "ResourceDescribeRead"
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeTags",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTags",
      "s3:ListAllMyBuckets",
      "s3:GetBucketTagging",
      "apigateway:GET",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # ----------------------------------------------------------------------------
  # ABAC pattern — fuller example (commented; not applied).
  # At scale a SINGLE shared role can be reused across clusters AND workloads by
  # condition-keying on multiple injected session tags. For example, to also pin
  # the ServiceAccount and cluster (defence in depth) you would add:
  #
  #   condition {
  #     test     = "StringEquals"
  #     variable = "aws:PrincipalTag/kubernetes-service-account"
  #     values   = ["yace"]
  #   }
  #   condition {
  #     test     = "StringEquals"
  #     variable = "aws:PrincipalTag/eks-cluster-name"
  #     values   = [var.cluster_name]
  #   }
  #
  # All six tags EKS injects are usable as `aws:PrincipalTag/<key>`:
  #   eks-cluster-arn, eks-cluster-name, kubernetes-namespace,
  #   kubernetes-service-account, kubernetes-pod-name, kubernetes-pod-uid.
  # ----------------------------------------------------------------------------
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM role + policy
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  name                 = local.role_name
  description          = "EKS Pod Identity role for YACE (CloudWatch exporter) in namespace ${var.namespace} (ADR-0018)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration
  path                 = var.iam_path

  tags = local.effective_tags
}

resource "aws_iam_policy" "cloudwatch_read" {
  name        = "${local.role_name}-cloudwatch-read"
  description = "CloudWatch metrics + resource-tagging read for YACE, ABAC-scoped to the ${var.namespace} namespace (ADR-0018)"
  path        = var.iam_path
  policy      = data.aws_iam_policy_document.cloudwatch_read.json

  tags = local.effective_tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_read" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.cloudwatch_read.arn
}

# ---------------------------------------------------------------------------------------------------------------------
# Pod Identity association — binds (cluster, namespace, ServiceAccount) -> role
# ---------------------------------------------------------------------------------------------------------------------
# This is the resource that replaces the IRSA `eks.amazonaws.com/role-arn`
# annotation. No OIDC issuer is involved. `target_role_arn` (cross-account, GA
# 2025-06) is left null here — YACE reads CloudWatch in the same account.
resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this.arn

  tags = local.effective_tags
}
