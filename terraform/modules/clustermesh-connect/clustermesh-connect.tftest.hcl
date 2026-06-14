mock_provider "kubernetes" {}
mock_provider "aws" {}

variables {}

run "no_connections_by_default" {
  command = plan

  assert {
    condition     = length(local.all_remotes) == 0
    error_message = "No remote clusters should be connected by default."
  }

  assert {
    condition     = length(kubernetes_secret.clustermesh_remote) == 0
    error_message = "No ClusterMesh secret should be created when there are no remotes."
  }
}

run "literal_remote_creates_secret" {
  command = plan

  variables {
    remote_clusters = {
      "staging-euc1" = {
        endpoint = "clustermesh.staging-euc1.internal:2379"
        ca_cert  = "CA"
        tls_cert = "CERT"
        tls_key  = "KEY"
      }
    }
  }

  assert {
    condition     = length(kubernetes_secret.clustermesh_remote) == 1
    error_message = "A literal remote cluster must create one ClusterMesh secret."
  }

  assert {
    condition     = kubernetes_secret.clustermesh_remote["staging-euc1"].metadata[0].name == "cilium-clustermesh-staging-euc1"
    error_message = "Secret name must follow cilium-clustermesh-<remote> convention."
  }
}

run "secrets_backed_remote_reads_secrets_manager" {
  command = plan

  variables {
    remote_clusters_from_secrets = {
      "staging-euc1" = {
        endpoint       = "clustermesh.staging-euc1.internal:2379"
        ca_secret_id   = "staging/eu-central-1/clustermesh/ca"
        cert_secret_id = "staging/eu-central-1/clustermesh/cert"
        key_secret_id  = "staging/eu-central-1/clustermesh/key"
      }
    }
  }

  assert {
    condition     = length(data.aws_secretsmanager_secret_version.ca) == 1
    error_message = "A secrets-backed remote must resolve its CA from Secrets Manager."
  }

  assert {
    condition     = length(kubernetes_secret.clustermesh_remote) == 1
    error_message = "A secrets-backed remote must create one ClusterMesh secret."
  }
}
