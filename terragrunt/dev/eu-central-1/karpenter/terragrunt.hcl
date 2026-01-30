include "root" {
  path = find_in_parent_folders()
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/karpenter.hcl"
  expose = true
}

generate "k8s_providers" {
  path      = "k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "helm" {
      kubernetes {
        host                   = "${include.envcommon.dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${include.envcommon.dependency.eks.outputs.cluster_certificate_authority_data}")
        exec {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${include.envcommon.dependency.eks.outputs.cluster_name}"]
        }
      }
    }

    provider "kubernetes" {
      host                   = "${include.envcommon.dependency.eks.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${include.envcommon.dependency.eks.outputs.cluster_certificate_authority_data}")
      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", "${include.envcommon.dependency.eks.outputs.cluster_name}"]
      }
    }
  PROVIDERS
}
