#!/bin/bash
set -euo pipefail

apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update -y
apt-get install -y docker-ce
systemctl enable --now docker

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
apt-get update -y
apt-get install -y kubelet kubeadm kubectl

kubeadm join ${cluster_endpoint} \
  --token ${bootstrap_token} \
  --discovery-token-ca-cert-hash ${ca_cert_hash}
