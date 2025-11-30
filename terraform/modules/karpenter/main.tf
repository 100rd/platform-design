# Data source for ECR Public authorization token (required for Karpenter OCI registry)
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

# Karpenter Helm Release
# CRDs are automatically installed by the Helm chart
resource "helm_release" "karpenter" {
  namespace           = var.namespace
  create_namespace    = var.create_namespace
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = var.karpenter_version

  # Ensure CRDs are installed by Helm (this is the default, explicit for clarity)
  skip_crds = false

  # Wait for resources to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  values = [
    yamlencode(merge(
      {
        # Settings for EKS Pod Identity (v21+)
        settings = {
          clusterName       = var.cluster_name
          clusterEndpoint   = var.cluster_endpoint
          interruptionQueue = var.karpenter_interruption_queue_name
        }

        # Service account configuration
        serviceAccount = {
          create = true
          name   = "karpenter"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.karpenter_controller_role_arn
          }
        }

        # Controller configuration
        controller = {
          resources = var.controller_resources
        }

        # Webhook configuration
        webhook = {
          enabled = var.enable_webhook
          port    = var.webhook_port
        }

        # Tolerations to run on Karpenter controller nodes
        tolerations = var.tolerations

        # Node selector to run on dedicated nodes
        nodeSelector = var.node_selector

        # Replicas for high availability
        replicas = var.controller_replicas

        # Pod disruption budget
        podDisruptionBudget = {
          enabled      = var.enable_pod_disruption_budget
          minAvailable = var.pdb_min_available
        }

        # Log level
        logLevel = var.log_level
      },
      var.additional_helm_values
    ))
  ]
}
