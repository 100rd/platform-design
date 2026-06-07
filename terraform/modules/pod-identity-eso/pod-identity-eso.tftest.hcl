# The aws_iam_policy_document data source computes its `.json` attribute from the
# provider; a bare mock returns null, which fails the role/policy JSON validation
# at plan. We mock the data source with a REPRESENTATIVE policy JSON that carries
# the same principal/actions/ABAC-tag strings the real module renders, so the
# role/policy JSON validation passes AND the content assertions stay meaningful.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"sts:AssumeRole\",\"sts:TagSession\",\"secretsmanager:GetSecretValue\",\"secretsmanager:PutSecretValue\",\"kms:Decrypt\",\"ecr:GetAuthorizationToken\"],\"Principal\":{\"Service\":\"pods.eks.amazonaws.com\"},\"Condition\":{\"StringEquals\":{\"aws:PrincipalTag/kubernetes-namespace\":\"external-secrets\"}}}]}"
    }
  }
}

variables {
  project      = "platform-design"
  cluster_name = "platform-dev"
  tags = {
    Environment = "test"
    Team        = "platform"
  }
}

run "defaults_to_external_secrets_controller_sa" {
  command = plan

  assert {
    condition     = var.namespace == "external-secrets"
    error_message = "namespace should default to external-secrets (ESO controller namespace)"
  }

  assert {
    condition     = var.service_account == "external-secrets"
    error_message = "service_account should default to external-secrets (ESO controller SA — ESO uses its own SA, not serviceAccountRef)"
  }
}

run "pod_identity_association_targets_cluster_ns_sa" {
  command = plan

  assert {
    condition     = aws_eks_pod_identity_association.this.cluster_name == "platform-dev"
    error_message = "association must target the supplied cluster"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this.namespace == "external-secrets"
    error_message = "association must target the external-secrets namespace"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this.service_account == "external-secrets"
    error_message = "association must target the external-secrets ServiceAccount"
  }
}

run "trust_policy_uses_pod_identity_principal_and_tagsession" {
  command = plan

  assert {
    condition     = strcontains(data.aws_iam_policy_document.trust.json, "pods.eks.amazonaws.com")
    error_message = "trust policy must target the pods.eks.amazonaws.com service principal"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.trust.json, "sts:AssumeRole")
    error_message = "trust policy must allow sts:AssumeRole"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.trust.json, "sts:TagSession")
    error_message = "trust policy must allow sts:TagSession (required to inject ABAC session tags)"
  }
}

run "eso_policy_is_abac_scoped_and_covers_secrets_kms_ecr" {
  command = plan

  assert {
    condition     = strcontains(data.aws_iam_policy_document.eso.json, "aws:PrincipalTag/kubernetes-namespace")
    error_message = "ESO policy must be ABAC-scoped on the kubernetes-namespace session tag"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.eso.json, "secretsmanager:GetSecretValue")
    error_message = "ESO policy must allow secretsmanager:GetSecretValue (read flow)"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.eso.json, "secretsmanager:PutSecretValue")
    error_message = "ESO policy must allow secretsmanager:PutSecretValue (PushSecret write flow)"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.eso.json, "kms:Decrypt")
    error_message = "ESO policy must allow kms:Decrypt (decrypt managed secrets)"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.eso.json, "ecr:GetAuthorizationToken")
    error_message = "ESO policy must allow ecr:GetAuthorizationToken (ECRAuthorizationToken generator)"
  }
}

run "invalid_iam_path_is_rejected" {
  command = plan

  variables {
    iam_path = "no-leading-slash"
  }

  expect_failures = [
    var.iam_path,
  ]
}
