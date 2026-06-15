# Module: `aws-ml-abac-iam`

> **ADRs:** [0018](../../../docs/adrs/0018-eks-pod-identity-as-default-workload-identity.md)
> (EKS Pod Identity as default workload identity),
> [0028](../../../docs/adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md)
> (the ABAC condition `aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system`),
> [0048](../../../docs/adrs/0048-aws-ml-cicd-registry-drift.md) (the S3 artifact store /
> RDS-Secrets backends this role reaches). WS-E owns the least-privilege + ABAC delta.

WS-E **IAM least-privilege + ABAC** role for ML workloads on the greenfield EKS GPU
cluster. Provides an EKS **Pod Identity** role whose permission policy is **scoped to a
single `platform:system` axis** by the ADR-0028 ABAC condition, so a pod may only act on
S3 / KMS / Secrets resources tagged with its own system — cross-system access is denied
even when the ARN is explicitly listed.

## Apply-gated / default-OFF

**With default inputs, `terraform plan` creates ZERO IAM.** The role, policy, attachment,
and Pod Identity association are all gated on `var.enabled` (default `false`) via `count`.
IAM is identity-critical; enabling requires an explicit human apply.

## Least-privilege + ABAC contract

- **Least-privilege:** only the S3 (`GetObject`/`PutObject`/`DeleteObject`/`ListBucket`/
  `GetBucketLocation`), KMS (`Decrypt`/`GenerateDataKey`), and Secrets Manager
  (`GetSecretValue`/`DescribeSecret`) actions the ML pipeline needs — **no `Action:*`,
  no `Resource:*`**. Each statement is emitted only when its resource list is non-empty.
- **ABAC:** every grant carries
  `aws:ResourceTag/platform:system == ${aws:PrincipalTag/platform:system}`. The role's
  `platform:system` principal tag (derived from `var.platform_system`) is what EKS Pod
  Identity surfaces in the session, so the tag-match is enforced at request time.
- **Keyless:** the trust policy admits only `pods.eks.amazonaws.com` (Pod Identity); the
  companion `aws-ml-scp-parity` SCP denies `iam:CreateAccessKey` org-side, so static keys
  are not a fallback (ADR-0018 forcing function).
- **No secrets in code:** the module references Secrets Manager ARNs (MLflow RDS creds via
  ESO, ADR-0008/0031) — it never embeds secret material.

## Inputs of note

| Variable | Purpose |
|---|---|
| `platform_system` | the `$system` axis the role is scoped to (ABAC match key) |
| `artifact_bucket_arns` / `kms_key_arns` / `secret_arns` | resource scoping (ABAC adds ownership scoping) |
| `eks_cluster_name` / `service_account_*` | Pod Identity association (created only when cluster name set) |

## ADR-0028 taxonomy

Role + policy + association carry `platform:system` (from `var.platform_system`),
`platform:component=ml-iam`, `platform:owner=team-ml-platform`,
`platform:managed-by=terragrunt`; overridable via `var.tags`. Surfaced on `platform_tags`.

## Validation (plan/validate-only)

`terraform fmt`, `terraform init -backend=false`, `terraform validate`, and
`terraform test` (mocked `aws` provider, **5/5 pass**) — default-OFF gate, ABAC condition
present in every grant, no wildcard action/resource, taxonomy tags, Pod-Identity gating.
The ABAC-condition *generation* from the `statement` blocks is additionally enforced by
`terraform validate` and `tests/opa/platform_tags_ml.rego` against the real plan JSON in
CI. **No `terraform apply`, no IAM created** at plan/validate time.
