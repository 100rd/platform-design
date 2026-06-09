terraform {
  required_version = "~> 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Required transitively by terraform-aws-modules/iam//modules/iam-oidc-provider
    # (v6.x), which reads the GitHub OIDC TLS certificate thumbprint.
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}
