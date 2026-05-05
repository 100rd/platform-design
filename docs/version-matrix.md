# Version Matrix

Single-source pin list for every tool, module, and provider used by the
platform-design repo. **All values are mirrored** — pick one source-of-truth
file and propagate the change through the whole matrix in the same PR.

Closes part of issue #179.

## Source-of-truth precedence

| Layer | File | Pins |
|---|---|---|
| 1 | `terragrunt/versions.hcl` | terraform, terragrunt, AWS provider, helper providers |
| 2 | `.terraform-version`, `.terragrunt-version`, `.tool-versions` | asdf/mise/tfenv mirror of #1 |
| 3 | `terragrunt/mise.toml` | mise mirror of #1 |
| 4 | `.github/workflows/*.yml` env blocks | CI mirror of #1 |
| 5 | `terraform/modules/*/versions.tf` | per-module `required_providers` block (consumed by #1's pin) |

Bumping a value at level 1 **mandates** the same change at levels 2–5 in the
same PR. CI fails if any drift is detected (see `terraform-checks` workflow's
version-drift check, landing as part of #172).

## Tool versions

| Tool | Version | Pinned in |
|---|---|---|
| `terraform` | `1.14.8` | `terragrunt/versions.hcl`, `.terraform-version`, `.tool-versions`, `terragrunt/mise.toml`, `.github/workflows/terragrunt-{plan,apply,validate}.yml`, `.github/workflows/terraform-validate.yml`, `.github/workflows/conftest-opa.yml`, `.github/workflows/drift-detection.yml` |
| `terragrunt` | `0.99.5` | `terragrunt/versions.hcl`, `.terragrunt-version`, `.tool-versions`, `terragrunt/mise.toml`, `.github/workflows/terragrunt-{plan,apply,validate}.yml`, `.github/workflows/conftest-opa.yml`, `.github/workflows/drift-detection.yml` |
| `tflint` | `v0.53.0` | `.github/workflows/terraform-validate.yml` |
| `checkov` | `v12` (action major) | `.github/workflows/terraform-validate.yml`, `.github/workflows/well-architected.yml` |
| `trivy-action` | `v0.35.0` | `.github/workflows/terraform-validate.yml` (×2) |
| `tfsec-action` | `v1.0.3` | `.github/workflows/*` (legacy — known config issue with `minimum_severity`; cleanup tracked separately) |
| `conftest` | `0.57.0` | `.github/workflows/conftest-opa.yml` |
| `infracost-actions` | `@v3` (action major) | `.github/workflows/infracost.yml` |
| `setup-helm` | `@v4` | `.github/workflows/generate-inventory.yml`, `.github/workflows/helm-validate.yml` |
| `kubeconform` | (action default) | `.github/workflows/kubeconform.yml` |
| `gitleaks` | (action default) | `.github/workflows/secret-scan.yml` |
| `Go` (terratest) | `1.22` | `.github/workflows/terratest.yml` |

> Note: the `terraform-compliance.yml` workflow uses `~1.11` for the `terraform_version` input — this is **stale**. Tracked under issue #172 (consolidate CI workflows) for cleanup.

## Provider versions

Pinned in `terragrunt/versions.hcl::locals.provider_versions` and consumed by
the auto-generated `versions_override.tf` for every Terragrunt unit.
Per-module `versions.tf` files declare `required_providers` constraints that
**must be at least as permissive** as these pins.

| Provider | Constraint | Pinned in |
|---|---|---|
| `hashicorp/aws` | `~> 6.0` | `terragrunt/versions.hcl` |
| `hashicorp/helm` | `~> 2.12` | `terragrunt/versions.hcl` |
| `hashicorp/kubernetes` | `~> 2.30` | `terragrunt/versions.hcl` |
| `hashicorp/null` | `~> 3.2` | `terragrunt/versions.hcl` |
| `hashicorp/random` | `~> 3.6` | `terragrunt/versions.hcl` |
| `hashicorp/tls` | `~> 4.0` | `terragrunt/versions.hcl` |

## Module versions

Internal modules (under `terraform/modules/`) are unversioned — they're
referenced by relative path. Each Terragrunt unit pins its module via
`terraform { source = "${get_repo_root()}/.../modules/<name>" }`. Bumping
an internal module is therefore a same-PR concern.

External modules are not currently pinned via Terragrunt; if/when added,
they belong here too.

## Kubernetes / app-platform versions

Sourced from `PROJECT_STATUS.md` and `argocd/`/`helm/` charts. These pin
the runtime stack rather than the toolchain.

| Component | Version | Pinned in |
|---|---|---|
| EKS | 1.34 | `terragrunt/_envcommon/eks.hcl::cluster_version`, per-env unit overrides |
| Karpenter | 1.8.1 | `helm/karpenter/Chart.yaml`, `argocd/applicationsets/karpenter.yaml` |
| Cilium | 1.17.1 | `helm/cilium/Chart.yaml`, `argocd/applicationsets/cilium.yaml` |
| ArgoCD | 3.x | `argocd/applicationsets/argocd.yaml` |
| Kargo | 1.2.0 | `kargo/` charts |
| kube-prometheus-stack | 81.2.0 | `helm/monitoring/Chart.yaml` |
| Loki | 6.51.0 | `helm/loki/Chart.yaml` |
| Tempo | 1.24.0 | `helm/tempo/Chart.yaml` |
| OpenTelemetry Collector | 0.143.0 | `helm/otel/Chart.yaml` |
| Pyroscope | 1.18.0 | `helm/pyroscope/Chart.yaml` |
| OPA/Gatekeeper | 3.18.2 | `helm/gatekeeper/Chart.yaml` |
| Kyverno | 1.13.4 | `helm/kyverno/Chart.yaml` |
| External Secrets Operator | 0.14.1 | `helm/external-secrets/Chart.yaml` |
| Velero | 1.15.0 | `helm/velero/Chart.yaml` (issue #185 will drive deployment) |
| External DNS | 0.15.1 | `helm/external-dns/Chart.yaml` |

## Bump procedure

1. Identify the source-of-truth file from the precedence table above.
2. Open a PR titled `chore: bump <tool> from <old> to <new>`.
3. Update every mirror listed in the table for that tool.
4. Run the relevant CI checks locally if practical (`terraform fmt`,
   `terragrunt hcl fmt`).
5. CI's drift check (post-#172) will fail if any mirror is missed.
6. Soak in non-prod (`dev` then `staging`) before promoting via #172's
   apply-stage gating.

## CI version-drift check (planned)

Coming as part of #172 (consolidate CI workflows). The check will:
- Read the canonical pins from `terragrunt/versions.hcl`.
- Diff against `.terraform-version`, `.terragrunt-version`, `.tool-versions`,
  `terragrunt/mise.toml`, and the `_VERSION` env vars in
  `.github/workflows/*.yml`.
- Fail the build with an annotated diff if any mirror is out of sync.

Until that lands, drift is caught manually during PR review of bump PRs.

## References

- Issue #179 (this matrix)
- Issue #156 (introduced `versions.hcl`)
- Issue #174 (introduced root tool-version files)
- Issue #172 (CI consolidation; will add the drift check)
- Source repo: `qbiq-ai/infra` issue #51
