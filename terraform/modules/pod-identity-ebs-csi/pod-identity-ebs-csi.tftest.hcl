# Mock the aws_iam_policy_document data source with a REPRESENTATIVE policy JSON so
# the role/policy JSON validation passes at plan AND the content assertions stay
# meaningful (bare mocks return null .json, which fails validation).
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"sts:AssumeRole\",\"sts:TagSession\",\"ec2:CreateVolume\",\"ec2:AttachVolume\",\"ec2:DescribeVolumes\"],\"Principal\":{\"Service\":\"pods.eks.amazonaws.com\"},\"Condition\":{\"StringEquals\":{\"aws:PrincipalTag/kubernetes-namespace\":\"kube-system\"}}}]}"
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

run "defaults_to_kube_system_ebs_csi_controller" {
  command = plan

  assert {
    condition     = var.namespace == "kube-system"
    error_message = "namespace should default to kube-system (where the EBS CSI controller deploys)"
  }

  assert {
    condition     = var.service_account == "ebs-csi-controller-sa"
    error_message = "service_account should default to ebs-csi-controller-sa"
  }
}

run "pod_identity_association_targets_cluster_ns_sa" {
  command = plan

  assert {
    condition     = aws_eks_pod_identity_association.this.cluster_name == "platform-dev"
    error_message = "association must target the supplied cluster"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this.namespace == "kube-system"
    error_message = "association must target the kube-system namespace"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this.service_account == "ebs-csi-controller-sa"
    error_message = "association must target the ebs-csi-controller-sa ServiceAccount"
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

run "ebs_policy_is_abac_scoped_and_covers_volume_ops" {
  command = plan

  assert {
    condition     = strcontains(data.aws_iam_policy_document.ebs_csi.json, "aws:PrincipalTag/kubernetes-namespace")
    error_message = "EBS CSI policy must be ABAC-scoped on the kubernetes-namespace session tag"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.ebs_csi.json, "ec2:CreateVolume")
    error_message = "EBS CSI policy must allow ec2:CreateVolume (volume provisioning)"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.ebs_csi.json, "ec2:AttachVolume")
    error_message = "EBS CSI policy must allow ec2:AttachVolume (volume attach)"
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
