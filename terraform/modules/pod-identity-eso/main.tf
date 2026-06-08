# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity — External Secrets Operator (ESO) — ADR-0018
# ---------------------------------------------------------------------------------------------------------------------
# Third workload in the ADR-0018 cutover order (YACE -> observability stack -> ESO
# -> LB controller). ESO is a primary consumer of workload identity.
#
# ADR-0018 sub-decision — ESO + Pod Identity specifics:
#   - ESO supports Pod Identity but CANNOT use `serviceAccountRef`. With Pod
#     Identity the agent injects credentials into the ESO controller's pod
#     directly, so ESO uses the identity bound to its OWN controller
#     ServiceAccount (`external-secrets` in namespace `external-secrets`) via a
#     PodIdentityAssociation — NOT the IRSA-style "act as this SA" indirection.
#   - ESO Generators adopted (no Vault): `ECRAuthorizationToken` mints short-lived
#     ECR pull creds; `Password` generator -> `PushSecret` writes credentials INTO
#     Secrets Manager. Hence this role needs SecretsManager read+write, KMS
#     decrypt/encrypt (CMK that encrypts those secrets), and ECR auth-token.
#
# What this module creates:
#   1. An IAM role whose TRUST policy targets the EKS Auth service principal
#      `pods.eks.amazonaws.com` (NOT a per-cluster OIDC issuer), allowing both
#      `sts:AssumeRole` AND `sts:TagSession` (TagSession injects the ABAC tags).
#   2. A least-privilege policy: SecretsManager get/describe/list + create/put for
#      the PushSecret flow, KMS decrypt/generate-data-key for the encrypting CMK,
#      and ECR GetAuthorizationToken for the ECRAuthorizationToken generator.
#   3. An `aws_eks_pod_identity_association` binding (cluster, namespace
#      `external-secrets`, ServiceAccount `external-secrets`) -> the role above.
#
# Coexistence (ADR-0018): IRSA stays supported for not-yet-migrated workloads. Do
# NOT configure both an IRSA annotation AND an association on the same SA. ESO's
# controller SA must not carry `eks.amazonaws.com/role-arn` once this association
# exists.
#
# Fargate caveat: Pod Identity is NOT supported on Fargate. Verify the ESO
# controller is not Fargate-scheduled before migrating.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  role_name = "${var.project}-${var.cluster_name}-${var.service_account}"

  default_tags = {
    ManagedBy        = "Terraform"
    Module           = "pod-identity-eso"
    ADR              = "ADR-0018"
    WorkloadIdentity = "eks-pod-identity"
    Namespace        = var.namespace
    ServiceAccount   = var.service_account
  }
  effective_tags = merge(local.default_tags, var.tags)

  # Secrets Manager ARN scope for the secrets ESO reads/writes. Defaults to all
  # secrets in the account/region ("*"); pass `secret_arn_patterns` to narrow to a
  # path prefix (e.g. ["arn:aws:secretsmanager:*:*:secret:/platform/*"]).
  secret_arns = length(var.secret_arn_patterns) > 0 ? var.secret_arn_patterns : ["*"]

  # KMS key ARNs ESO may decrypt/encrypt (the CMK(s) protecting those secrets).
  # Defaults to "*"; pass `kms_key_arns` to pin to the platform secrets CMK.
  kms_key_arns = length(var.kms_key_arns) > 0 ? var.kms_key_arns : ["*"]
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
# ESO permissions — Secrets Manager + KMS + ECR auth-token (ABAC namespace-scoped)
# ---------------------------------------------------------------------------------------------------------------------
# Every statement is ABAC-scoped to sessions whose `kubernetes-namespace` tag ==
# var.namespace (the `external-secrets` namespace). EKS injects that PrincipalTag
# on every Pod Identity session because the trust allows `sts:TagSession`. This is
# the ADR-0018 mechanism that lets one role serve a namespace's workloads instead
# of cutting a new role per workload.
data "aws_iam_policy_document" "eso" {
  # Read flow — fetch secrets into the cluster (ExternalSecret).
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:ListSecrets",
    ]
    resources = local.secret_arns

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # Write flow — Password generator -> PushSecret writes credentials INTO Secrets
  # Manager (in-cluster-originated rotation; ADR-0018, no Vault needed).
  statement {
    sid    = "SecretsManagerPushSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:TagResource",
      "secretsmanager:UpdateSecret",
    ]
    resources = local.secret_arns

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # KMS — decrypt secrets read, generate data keys for secrets pushed. Scoped to
  # the CMK(s) protecting the secrets.
  statement {
    sid    = "KmsSecretsAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = local.kms_key_arns

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace]
    }
  }

  # ECR — ECRAuthorizationToken generator mints short-lived registry pull creds.
  # `GetAuthorizationToken` is account/region-global and does not support a
  # per-resource ARN, so Resource is "*", ABAC-constrained by namespace.
  statement {
    sid    = "EcrAuthorizationToken"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
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
  description          = "EKS Pod Identity role for External Secrets Operator in namespace ${var.namespace} (ADR-0018)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration
  path                 = var.iam_path

  tags = local.effective_tags
}

resource "aws_iam_policy" "eso" {
  name        = "${local.role_name}-eso"
  description = "ESO SecretsManager + KMS + ECR auth-token, ABAC-scoped to the ${var.namespace} namespace (ADR-0018)"
  path        = var.iam_path
  policy      = data.aws_iam_policy_document.eso.json

  tags = local.effective_tags
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.eso.arn
}

# ---------------------------------------------------------------------------------------------------------------------
# Pod Identity association — binds (cluster, namespace, ServiceAccount) -> role
# ---------------------------------------------------------------------------------------------------------------------
# Replaces the IRSA `eks.amazonaws.com/role-arn` annotation on the ESO controller
# SA. ESO uses THIS identity (its own controller SA), never `serviceAccountRef`.
resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this.arn

  tags = local.effective_tags
}
