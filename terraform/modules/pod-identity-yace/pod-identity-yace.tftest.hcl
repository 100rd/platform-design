# The aws_iam_policy_document data source computes its `.json` attribute from the
# provider; a bare mock returns null, which fails the role/policy JSON validation
# at plan. We mock the data source with a REPRESENTATIVE policy JSON that carries
# the same principal/actions/ABAC-tag strings the real module renders, so the
# role/policy JSON validation passes AND the content assertions stay meaningful.
# The authoritative content check is `terraform validate` + the real rendered
# documents (this mock only stands in for plan-time JSON validation).
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"sts:AssumeRole\",\"sts:TagSession\",\"cloudwatch:GetMetricData\"],\"Principal\":{\"Service\":\"pods.eks.amazonaws.com\"},\"Condition\":{\"StringEquals\":{\"aws:PrincipalTag/kubernetes-namespace\":\"observability\"}}}]}"
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

run "defaults_to_observability_yace" {
  command = plan

  assert {
    condition     = var.namespace == "observability"
    error_message = "namespace should default to observability (where the YACE chart deploys)"
  }

  assert {
    condition     = var.service_account == "yace"
    error_message = "service_account should default to yace"
  }
}

run "pod_identity_association_targets_cluster_ns_sa" {
  command = plan

  assert {
    condition     = aws_eks_pod_identity_association.this.cluster_name == "platform-dev"
    error_message = "association must target the supplied cluster"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this.namespace == "observability"
    error_message = "association must target the observability namespace"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this.service_account == "yace"
    error_message = "association must target the yace ServiceAccount"
  }
}

run "trust_policy_uses_pod_identity_principal_and_tagsession" {
  command = plan

  # Trust principal must be the EKS Auth service, not an OIDC issuer.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.trust.json, "pods.eks.amazonaws.com")
    error_message = "trust policy must target the pods.eks.amazonaws.com service principal"
  }

  # Both AssumeRole and TagSession are required for Pod Identity ABAC.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.trust.json, "sts:AssumeRole")
    error_message = "trust policy must allow sts:AssumeRole"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.trust.json, "sts:TagSession")
    error_message = "trust policy must allow sts:TagSession (required to inject ABAC session tags)"
  }
}

run "cloudwatch_policy_is_abac_scoped_by_namespace" {
  command = plan

  assert {
    condition     = strcontains(data.aws_iam_policy_document.cloudwatch_read.json, "aws:PrincipalTag/kubernetes-namespace")
    error_message = "CloudWatch policy must be ABAC-scoped on the kubernetes-namespace session tag"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.cloudwatch_read.json, "cloudwatch:GetMetricData")
    error_message = "CloudWatch policy must allow cloudwatch:GetMetricData (YACE's core read action)"
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
