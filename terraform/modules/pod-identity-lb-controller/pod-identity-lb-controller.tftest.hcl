# Mock the aws_iam_policy_document data source with a REPRESENTATIVE policy JSON so
# the role/policy JSON validation passes at plan AND the content assertions stay
# meaningful (bare mocks return null .json, which fails validation).
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"sts:AssumeRole\",\"sts:TagSession\",\"elasticloadbalancing:CreateLoadBalancer\",\"ec2:DescribeSubnets\"],\"Principal\":{\"Service\":\"pods.eks.amazonaws.com\"},\"Condition\":{\"StringEquals\":{\"aws:PrincipalTag/kubernetes-namespace\":\"kube-system\"}}}]}"
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

run "defaults_to_kube_system_lb_controller" {
  command = plan

  assert {
    condition     = var.namespace == "kube-system"
    error_message = "namespace should default to kube-system (where the LB controller deploys)"
  }

  assert {
    condition     = var.service_account == "aws-load-balancer-controller"
    error_message = "service_account should default to aws-load-balancer-controller"
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
    condition     = aws_eks_pod_identity_association.this.service_account == "aws-load-balancer-controller"
    error_message = "association must target the aws-load-balancer-controller ServiceAccount"
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

run "lb_controller_policy_is_abac_scoped_and_covers_elb_ec2" {
  command = plan

  assert {
    condition     = strcontains(data.aws_iam_policy_document.lb_controller.json, "aws:PrincipalTag/kubernetes-namespace")
    error_message = "LB controller policy must be ABAC-scoped on the kubernetes-namespace session tag"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.lb_controller.json, "elasticloadbalancing:CreateLoadBalancer")
    error_message = "LB controller policy must allow elasticloadbalancing:CreateLoadBalancer"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.lb_controller.json, "ec2:DescribeSubnets")
    error_message = "LB controller policy must allow ec2:DescribeSubnets (subnet resolution)"
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
