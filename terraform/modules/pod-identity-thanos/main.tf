# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity — Thanos (S3 object storage) — ADR-0018
# ---------------------------------------------------------------------------------------------------------------------
# Part of the observability-stack step in the ADR-0018 cutover order (YACE ->
# observability stack -> ESO -> LB controller). Thanos (store/compactor/sidecar)
# reads and writes long-term metrics blocks in S3 and previously authenticated via
# an IRSA role (`thanos-s3-access`); this module replaces that with a Pod Identity
# association.
#
# What this module creates:
#   1. An IAM role whose TRUST policy targets the EKS Auth service principal
#      `pods.eks.amazonaws.com` (NOT a per-cluster OIDC issuer), allowing both
#      `sts:AssumeRole` AND `sts:TagSession` (TagSession injects the ABAC tags).
#   2. An S3 object-storage policy scoped to Thanos's bucket(s): list on the bucket
#      ARNs, object CRUD on the bucket object ARNs, plus KMS decrypt/data-key for
#      SSE-KMS buckets. ABAC-scoped by the kubernetes-namespace session tag.
#   3. An `aws_eks_pod_identity_association` binding (cluster, namespace
#      `monitoring`, ServiceAccount `thanos`) -> the role above.
#
# Coexistence (ADR-0018): IRSA stays supported for not-yet-migrated workloads. Do
# NOT configure both an IRSA annotation AND an association on the same SA. The
# Thanos SA must drop its `eks.amazonaws.com/role-arn` annotation once this
# association exists (the kube-prometheus-stack Thanos SA template).
#
# Fargate caveat: Pod Identity is NOT supported on Fargate. Verify Thanos pods are
# not Fargate-scheduled before migrating.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  role_name = "${var.project}-${var.cluster_name}-${var.service_account}"

  default_tags = {
    ManagedBy        = "Terraform"
    Module           = "pod-identity-thanos"
    ADR              = "ADR-0018"
    WorkloadIdentity = "eks-pod-identity"
    Namespace        = var.namespace
    ServiceAccount   = var.service_account
  }
  effective_tags = merge(local.default_tags, var.tags)

  # Bucket-level ARNs (for ListBucket / GetBucketLocation) and object-level ARNs
  # (for object CRUD). Empty `bucket_names` falls back to "*" so the module plans
  # without a real bucket list; pass the Thanos bucket name(s) in production.
  bucket_arns = length(var.bucket_names) > 0 ? [for b in var.bucket_names : "arn:${var.aws_partition}:s3:::${b}"] : ["*"]
  object_arns = length(var.bucket_names) > 0 ? [for b in var.bucket_names : "arn:${var.aws_partition}:s3:::${b}/*"] : ["*"]

  # KMS key ARNs for SSE-KMS buckets. Empty list -> "*" (allow any key); pin to the
  # bucket CMK in production.
  kms_key_arns = length(var.kms_key_arns) > 0 ? var.kms_key_arns : ["*"]
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
# Thanos S3 object-storage permissions (ABAC namespace-scoped)
# ---------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "thanos_s3" {
  # Bucket-level — list blocks + locate region. Scoped to Thanos's bucket ARNs.
  statement {
    sid    = "S3BucketList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = local.bucket_arns

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # Object-level — metrics block CRUD. Scoped to bucket/* ARNs.
  statement {
    sid    = "S3ObjectCrud"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = local.object_arns

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # KMS — SSE-KMS encrypt/decrypt for the bucket CMK. Scoped to the supplied keys.
  statement {
    sid    = "KmsBucketAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = local.kms_key_arns

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
  description          = "EKS Pod Identity role for Thanos S3 object storage in namespace ${var.namespace} (ADR-0018)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration
  path                 = var.iam_path

  tags = local.effective_tags
}

resource "aws_iam_policy" "thanos_s3" {
  name        = "${local.role_name}-thanos-s3"
  description = "Thanos S3 object-storage access, ABAC-scoped to the ${var.namespace} namespace (ADR-0018)"
  path        = var.iam_path
  policy      = data.aws_iam_policy_document.thanos_s3.json

  tags = local.effective_tags
}

resource "aws_iam_role_policy_attachment" "thanos_s3" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.thanos_s3.arn
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
