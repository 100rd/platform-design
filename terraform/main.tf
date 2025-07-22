terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.39.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "hcloud" {
  token = var.hetzner_token
}

module "vpc" {
  source = "./modules/vpc"
  name   = var.name
  vpc_cidr = var.vpc_cidr
  tags   = var.tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  tags = var.tags
}

module "hetzner_nodes" {
  source = "./modules/hetzner-nodes"
  count  = var.enable_hetzner_nodes ? 1 : 0

  name_prefix  = var.cluster_name
  node_count   = var.hetzner_node_count
  server_type  = var.hetzner_server_type
  image        = var.hetzner_image
  location     = var.hetzner_location
  ssh_keys     = var.hetzner_ssh_keys

  user_data = var.hetzner_user_data == "" ?
    templatefile("${path.module}/user_data/hetzner-kubeadm.sh", {
      cluster_endpoint = module.eks.cluster_endpoint,
      bootstrap_token  = var.hetzner_bootstrap_token,
      ca_cert_hash     = var.hetzner_ca_cert_hash,
    }) : var.hetzner_user_data

  labels = var.tags
}
