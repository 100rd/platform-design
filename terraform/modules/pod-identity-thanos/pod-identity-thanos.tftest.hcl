# Mock the aws_iam_policy_document data source with a REPRESENTATIVE policy JSON so
# the role/policy JSON validation passes at plan AND the content assertions stay
# meaningful (bare mocks return null .json, which fails validation).
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"sts:AssumeRole\",\"sts:TagSession\",\"s3:GetObject\",\"s3:PutObject\",\"s3:ListBucket\"],\"Principal\":{\"Service\":\"pods.eks.amazonaws.com\"},\"Condition\":{\"StringEquals\":{\"aws:PrincipalTag/kubernetes-namespace\":\"monitoring\"}}}]}"
    }
  }
}

variables {
  project      = "platform-design"
  cluster_name = "platform-dev"
  bucket_names = ["platform-design-thanos-metrics"]
  tags = {
    Environment = "test"
    Team        = "platform"
  }
}

run "defaults_to_monitoring_thanos" {
  command = plan

  assert {
    condition     = var.namespace == "monitoring"
    error_message = "namespace should default to monitoring (where the kube-prometheus-stack Thanos SA is created)"
  }

  assert {
    condition     = var.service_account == "thanos"
    error_message = "service_account should default to thanos"
  }
}

run "pod_identity_association_targets_cluster_ns_sa" {
  command = plan

  assert {
    condition     = aws_eks_pod_identity_association.this.cluster_name == "platform-dev"
    error_message = "association must target the supplied cluster"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this.namespace == "monitoring"
    error_message = "association must target the monitoring namespace"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this.service_account == "thanos"
    error_message = "association must target the thanos ServiceAccount"
  }
}

run "trust_policy_uses_pod_identity_principal_and_tagsession" {
  command = plan

  assert {
    condition     = strcontains(data.aws_iam_policy_document.trust.json, "pods.eks.amazonaws.com")
    error_message = "trust policy must target the pods.eks.amazonaws.com service principal"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.trust.json, "sts:TagSession")
    error_message = "trust policy must allow sts:TagSession (required to inject ABAC session tags)"
  }
}

run "s3_policy_is_abac_scoped_and_covers_object_crud" {
  command = plan

  assert {
    condition     = strcontains(data.aws_iam_policy_document.thanos_s3.json, "aws:PrincipalTag/kubernetes-namespace")
    error_message = "Thanos S3 policy must be ABAC-scoped on the kubernetes-namespace session tag"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.thanos_s3.json, "s3:PutObject")
    error_message = "Thanos S3 policy must allow s3:PutObject (block writes)"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.thanos_s3.json, "s3:ListBucket")
    error_message = "Thanos S3 policy must allow s3:ListBucket (block listing)"
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
