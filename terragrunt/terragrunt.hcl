terraform {
  source = "../terraform"
}

inputs = {
  region                 = "us-east-1"
  name                   = "platform"
  cluster_name           = "platform-eks"
  enable_hetzner_nodes   = true
  hetzner_token          = get_env("HCLOUD_TOKEN", "")
  hetzner_node_count     = 2
  hetzner_server_type    = "cx31"
  hetzner_image          = "ubuntu-22.04"
  hetzner_location       = "fsn1"
=======
locals {
  region      = "us-east-1"
  environment = "dev"
}

remote_state {
  backend = "s3"
  config = {
    bucket         = "my-terraform-states"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.region
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "aws" {
      region = "${local.region}"
    }
  EOT
}
