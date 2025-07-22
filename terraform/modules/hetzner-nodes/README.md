# Hetzner Node Module

This module provisions additional Kubernetes worker nodes on Hetzner Cloud. It
can be used to extend an existing Amazon EKS cluster with nodes running outside
of AWS. Nodes are created using the `hcloud` provider and bootstrapped via
cloud-init.

The default user data installs Docker, kubeadm and joins the EKS cluster using
the provided token and certificate hash. You can supply custom user data if
different provisioning is required (for example, installing EKS Anywhere).

## Variables

- `name_prefix` – Prefix for server names.
- `node_count` – Number of servers to create.
- `server_type` – Hetzner server type (e.g. `cx31`).
- `image` – OS image to use (default `ubuntu-22.04`).
- `location` – Hetzner location (e.g. `fsn1`).
- `ssh_keys` – List of SSH key IDs to inject.
- `user_data` – Cloud-init script for node bootstrap.
- `labels` – Labels to apply to servers.

## Outputs

- `node_names` – Names of created servers.
- `node_ips` – Public IPv4 addresses of the nodes.
