# Karpenter Helm Chart Installation
# This file demonstrates how to install Karpenter after EKS and VPC modules are deployed
#
# Prerequisites:
# 1. EKS cluster is deployed with Karpenter submodule enabled
# 2. VPC has proper tags for Karpenter discovery
# 3. kubectl context is configured for the cluster
#
# Usage:
# 1. Deploy VPC and EKS modules first
# 2. Run: terraform init && terraform apply
# 3. Apply NodePool manifests: kubectl apply -f kubernetes/karpenter/

terraform {
  required_version = ">= 1.3"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

# Data sources to get EKS cluster information
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Data source for ECR Public authorization token
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

# AWS provider for us-east-1 (required for ECR Public)
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

# Karpenter Helm Release
# CRDs are automatically installed by the Helm chart (skipCRDs: false is default)
resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  create_namespace    = false
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = var.karpenter_version

  # Ensure CRDs are installed by Helm
  skip_crds = false

  values = [
    yamlencode({
      # Settings for EKS Pod Identity (v21+)
      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = data.aws_eks_cluster.cluster.endpoint
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
        resources = {
          requests = {
            cpu    = "500m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
        }
      }

      # Webhook configuration
      webhook = {
        enabled = true
        port    = 8443
      }

      # Tolerations to run on Karpenter controller nodes
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]

      # Node selector to run on dedicated nodes
      nodeSelector = {
        "karpenter.sh/controller" = "true"
      }

      # Replicas for high availability
      replicas = 2

      # Pod disruption budget
      podDisruptionBudget = {
        enabled      = true
        minAvailable = 1
      }

      # Log level
      logLevel = "info"
    })
  ]
}

# Variables
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.8.1"  # Updated 2026-01-28 from 1.1.1
}

variable "karpenter_controller_role_arn" {
  description = "IAM role ARN for Karpenter controller (from EKS module output)"
  type        = string
}

variable "karpenter_interruption_queue_name" {
  description = "SQS queue name for Karpenter interruption handling (from EKS module output)"
  type        = string
}

# Outputs
output "karpenter_chart_version" {
  description = "Version of installed Karpenter chart"
  value       = helm_release.karpenter.version
}

output "karpenter_namespace" {
  description = "Namespace where Karpenter is installed"
  value       = helm_release.karpenter.namespace
}

output "karpenter_status" {
  description = "Status of Karpenter Helm release"
  value       = helm_release.karpenter.status
}
