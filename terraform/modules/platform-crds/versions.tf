terraform {
  required_version = "~> 1.11"

  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
