# ADR-0008: External Secrets Operator over native K8s secrets

- Status: **Accepted** — decision is *adopted (live in source estate)*
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

Platform workloads need secrets — database credentials, upstream model-provider
API keys for the inference gateway, object-store and observability tokens,
certificates. GitOps (ADR-0006) explicitly does not put plaintext secrets in Git.
Options for managing secrets:

1. **Native K8s Secrets** — base64 in etcd, created out-of-band.
2. **Sealed Secrets (Bitnami)** — encrypted secrets committed to Git.
3. **External Secrets Operator (ESO)** — sync from an external provider.
4. **HashiCorp Vault** — with injector sidecar.

## Decision

Use **External Secrets Operator (ESO)** with **AWS Secrets Manager** as the
backend, authenticated via IRSA, exposed through a `ClusterSecretStore`. A
reviewer can check conformance by confirming workloads consume `ExternalSecret`
manifests (synced from Secrets Manager) rather than hand-created `Secret`
objects or Git-committed sealed secrets.

## Alternatives considered

### Alternative A: HashiCorp Vault
Self-managed secrets engine with an injector sidecar.
Rejected because: Vault adds significant operational burden (HA, unseal, backup)
the platform does not want to run. AWS Secrets Manager is a managed service with
no infrastructure to operate, and the estate is already AWS-native.

### Alternative B: Sealed Secrets
Encrypt secrets and commit them to Git.
Rejected because: requires managing the controller's encryption key and
re-encrypting on every rotation, and does not integrate with AWS-native secret
storage or rotation. Rotation becomes a Git operation rather than an AWS one.

### Alternative C: Status quo (native K8s Secrets)
Create secrets manually in each cluster.
Rejected because: no single source of truth, no automatic rotation propagation,
and manual creation does not fit the GitOps model.

## Consequences

### Positive
- Single source of truth: secrets live in AWS Secrets Manager, managed by
  Terraform/Terragrunt (ADR-0004). No secrets in Git, no manual K8s creation.
- Automatic rotation: ESO polls on an interval; rotated AWS secrets propagate to
  K8s automatically.
- IRSA auth — no static credentials.
- Multi-cluster: one set of Secrets Manager secrets serves dev/stage/prod via a
  `ClusterSecretStore` mapped to account-specific IAM roles.
- Audit trail: secret access logged in CloudTrail (Secrets Manager API) and K8s
  audit logs.

### Negative
- Dependency on AWS Secrets Manager (vendor lock-in for secret storage).
- Another CRD/controller to operate.
- Sync-interval latency vs. real-time reads.
- Must author `ExternalSecret` manifests per workload.

### Risks
- Secrets Manager cost grows with secret count ($0.40/secret/month + API charges).
  Accepted — small relative to the platform's spend; mitigated by consolidating
  related keys per secret where safe.

## Implementation notes

- ESO installed via Helm (GitOps); `ClusterSecretStore` per account, IRSA-bound.
- Secrets provisioned in Secrets Manager by Terragrunt; workloads reference them
  by `ExternalSecret`.

## References

- ESO docs: <https://external-secrets.io/>
- Ported from `infra` ADR-006 (ESO over native secrets) and `argocd`
  `ClusterSecretStore` usage
- Related: ADR-0006 (ArgoCD GitOps)

---
*Ported from infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live).*
