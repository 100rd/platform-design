# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity — EBS CSI Driver (controller) — ADR-0018
# ---------------------------------------------------------------------------------------------------------------------
# The aws-ebs-csi-driver controller provisions/attaches/snapshots EBS volumes for
# PersistentVolumeClaims. It previously authenticated via an IRSA role; this module
# replaces that with a Pod Identity association on the EBS CSI controller SA.
#
# What this module creates:
#   1. An IAM role whose TRUST policy targets the EKS Auth service principal
#      `pods.eks.amazonaws.com` (NOT a per-cluster OIDC issuer), allowing both
#      `sts:AssumeRole` AND `sts:TagSession` (TagSession injects the ABAC tags).
#   2. An EC2 volume-operations policy (create/attach/detach/delete volumes,
#      create/delete snapshots, describe, tag) plus optional KMS grants for
#      encrypted volumes. ABAC-scoped by the kubernetes-namespace session tag.
#   3. An `aws_eks_pod_identity_association` binding (cluster, namespace
#      `kube-system`, ServiceAccount `ebs-csi-controller-sa`) -> the role above.
#
# Coexistence (ADR-0018): IRSA stays supported for not-yet-migrated workloads. Do
# NOT configure both an IRSA annotation AND an association on the same SA. The EBS
# CSI controller SA must not carry `eks.amazonaws.com/role-arn` once this
# association exists. The EBS CSI driver may be installed as an EKS managed addon,
# in which case the addon's `service_account_role_arn` is dropped in favour of this
# association.
#
# Fargate caveat: Pod Identity is NOT supported on Fargate (and EBS volumes are not
# attachable to Fargate pods anyway). The controller runs on EC2/Karpenter nodes.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  role_name = "${var.project}-${var.cluster_name}-${var.service_account}"

  default_tags = {
    ManagedBy        = "Terraform"
    Module           = "pod-identity-ebs-csi"
    ADR              = "ADR-0018"
    WorkloadIdentity = "eks-pod-identity"
    Namespace        = var.namespace
    ServiceAccount   = var.service_account
  }
  effective_tags = merge(local.default_tags, var.tags)

  # KMS key ARNs for encrypted EBS volumes. Empty list -> "*" (allow any key); pin
  # to the volume-encryption CMK(s) in production.
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
# EBS CSI driver permissions — EC2 volume operations (ABAC namespace-scoped)
# ---------------------------------------------------------------------------------------------------------------------
# Mirrors the upstream AmazonEBSCSIDriverPolicy: describe (resource discovery),
# volume lifecycle (create/attach/detach/delete), snapshot lifecycle, and tagging,
# plus KMS grants for CMK-encrypted volumes. Describe/CreateVolume/CreateSnapshot
# are account/region-global EC2 actions that do not support per-resource ARNs, so
# Resource is "*", ABAC-constrained by the kubernetes-namespace session tag.
data "aws_iam_policy_document" "ebs_csi" {
  # Describe — discover volumes/snapshots/instances/AZs for reconcile.
  statement {
    sid    = "Ec2DescribeRead"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ec2:DescribeSnapshots",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeVolumesModifications",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # Volume lifecycle — provision/attach/detach/delete/modify EBS volumes for PVCs.
  statement {
    sid    = "Ec2VolumeLifecycle"
    effect = "Allow"
    actions = [
      "ec2:CreateVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:DeleteVolume",
      "ec2:ModifyVolume",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # Snapshot lifecycle — VolumeSnapshot support.
  statement {
    sid    = "Ec2SnapshotLifecycle"
    effect = "Allow"
    actions = [
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # Tagging — the driver tags volumes/snapshots it creates (and is restricted by
  # CreateAction at the EC2 level).
  statement {
    sid    = "Ec2Tagging"
    effect = "Allow"
    actions = [
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

  # KMS — encrypt/decrypt + grant management for CMK-encrypted EBS volumes. Scoped
  # to the supplied keys.
  statement {
    sid    = "KmsVolumeEncryption"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
      "kms:DescribeKey",
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
  description          = "EKS Pod Identity role for the EBS CSI driver controller in namespace ${var.namespace} (ADR-0018)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration
  path                 = var.iam_path

  tags = local.effective_tags
}

resource "aws_iam_policy" "ebs_csi" {
  name        = "${local.role_name}-ebs-csi"
  description = "EBS CSI driver EC2 volume operations, ABAC-scoped to the ${var.namespace} namespace (ADR-0018)"
  path        = var.iam_path
  policy      = data.aws_iam_policy_document.ebs_csi.json

  tags = local.effective_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.ebs_csi.arn
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
