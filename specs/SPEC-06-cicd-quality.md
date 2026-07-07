# SPEC-06 — CI/CD & Quality Gates

> Portable reverse-engineering spec. Rebuild the platform's continuous-integration,
> supply-chain, and quality-gate estate for a new client without reading the source repo.
> Placeholders (`{{...}}`) are defined in `SPEC-00-overview.md`; spec-local ones are listed in §5.

---

## 1. Scope & non-goals

This spec defines the **GitHub Actions CI/CD estate** that guards the Infrastructure-as-Code
(Terraform/OpenTofu + Terragrunt), Kubernetes/Helm manifests, container services, and ML
pipelines of the platform. It covers: the full workflow inventory (34 workflows + 10 composite
actions); the IaC verification loop wired as CI (`fmt → validate → tflint → checkov/tfsec →
plan → OPA/conftest → cost`); the split between **merge-gating** and **advisory** checks; the
**keyless OIDC** authentication model (no long-lived cloud keys in CI); the supply-chain chain
(harden-runner → build → Trivy → SBOM → cosign keyless sign); scheduled **drift detection**;
the **Infracost** cost gate; reusable/`workflow_call` pipeline factoring; the Go/controller test
strategy (`go-ci`, Terratest, OPA unit tests, BDD compliance); Dependabot posture; branch
protection assumptions; and how a client re-wires the same gates in GitLab CI.

**Non-goals.** This spec does *not* define: the runtime Kubernetes admission-policy layer
(Kyverno/VAP — `ADR-0020`, see the cluster-security spec); the ArgoCD/Kargo GitOps delivery
internals beyond the CI→CD handoff (`ADR-0006`, `ADR-0021`, see the delivery spec); the Terraform
module design itself (see the IaC spec); or the observability/alerting backends (see the
observability spec). It defines the *gates and their contracts*, not the modules they inspect.

---

## 2. Architecture

### 2.1 Two planes: PR-time gates vs post-merge delivery

```
 Developer ──PR──▶  ┌──────────────────────── PR GATES (block merge) ─────────────────────────┐
                    │  IaC loop:   fmt ▶ validate ▶ tflint ▶ (tfsec|checkov*) ▶ plan ▶ OPA*   │
                    │  Cost:       infracost diff  (block > $BLOCK_THRESHOLD, label bypass)    │
                    │  Manifests:  helm lint ▶ kubeconform -strict ▶ conftest                  │
                    │  Code:       go build/test/gosec* · CodeQL* · dep-scan · secret-scan     │
                    │  Hygiene:    yamllint · shellcheck · zizmor* · validate-agents · versions│
                    └───────────────┬─────────────────────────────────────────────────────────┘
                                    │  branch protection: required checks must be green
                          merge to  ▼  main
 ┌──────────────────────── POST-MERGE (mutate / deliver) ─────────────────────────────────┐
 │  terragrunt-apply  (push→main, GitHub Environment approval for staging/prod)            │
 │  container-build   (push→main → build ▶ Trivy ▶ SBOM ▶ push ECR ▶ cosign keyless sign)  │
 │  reusable-deploy-via-argocd  (bump image tag+digest in config repo → ArgoCD/Kargo sync) │
 │  ml-pipeline[-aws|-baremetal]  (train ▶ eval-debate gate ▶ register ▶ Kargo promote)    │
 │  generate-diagrams / generate-inventory  (auto-commit docs back to main)                │
 └──────────────────────────────────────────────────────────────────────────────────────────┘
 ┌──────────────────────── SCHEDULED (non-gating) ───────────────────────────────────────┐
 │  drift-detection  (cron 06:00 UTC daily) → open/close GitHub Issues (alert-only)        │
 │  terratest        (cron 02:00 UTC nightly) → real infra integration tests → issue       │
 └──────────────────────────────────────────────────────────────────────────────────────────┘
   * = advisory today (soft-fail); designed to flip to blocking once the backlog is clean.
```

### 2.2 Gate categories

- **Hard gates (fail the PR):** `terragrunt-validate`, `terraform-validate` (fmt/validate/tflint),
  `terragrunt-plan` (summary job), `terraform-compliance` (native `terraform test` only),
  `conftest-opa` (OPA unit tests always; conftest when OIDC wired), `secret-scan` (gitleaks),
  `yaml-lint`, `shellcheck`, `helm-validate`, `k8s-validate`, `version-manifest-validate`,
  `ml-monitoring-baremetal-validate`, `validate-agents`, `infracost` (over block threshold),
  `reusable-dep-scan` (default), and `reusable-build-and-push`'s Trivy (default `exit-code: 1`).
- **Advisory (soft-fail, report-only) today:** `tfsec`, `terraform-validate`'s Trivy+Checkov steps,
  `well-architected` (Checkov `soft_fail: true`), `terraform-compliance`'s BDD job, `zizmor`,
  `reusable-sast` (CodeQL), `go-ci` (`continue-on-error: true`), `policy-access-check`
  (`ADVISORY: true`), `container-build`'s Trivy (`exit-code: 0`). These upload SARIF to the
  GitHub Security tab and/or post PR comments; they are staged to become blocking (tracked as
  "Phase 1.1" of the in-repo sync roadmap) once the finding backlog is remediated.

### 2.3 The IaC verification loop as CI

The repo-enforced local loop (`fmt → validate → tflint → checkov → plan`) is decomposed across
workflows so each stage is an independently required status check:

| Loop stage | Workflow · job | Blocking? |
|---|---|---|
| `terragrunt hcl format --check` | `terragrunt-validate` / `hclfmt` | **hard** |
| `terraform fmt -check -recursive` | `terraform-validate` / `fmt-check` | **hard** |
| `terraform validate` (per module, `-backend=false`) | `terraform-validate` / `validate` (matrix) | **hard** |
| `tflint --recursive` (`--minimum-failure-severity error`) | `terraform-validate` / `tflint` | **hard** |
| `tfsec` HIGH+ | `tfsec` (all jobs `soft_fail`) | advisory |
| `checkov` CIS | `terraform-validate` / `checkov-cis` (`soft_fail`), `well-architected` | advisory |
| `terragrunt plan` (per changed unit, OIDC) | `terragrunt-plan` / `plan` → `plan-status` | **hard** (summary) |
| OPA policy on plan JSON (conftest) | `conftest-opa` | **hard** (when OIDC wired) |
| Infracost diff vs base | `infracost` | **hard** over threshold |

**Apply never runs from a PR or feature branch.** `terragrunt-apply` triggers only on `push` to
`main` (post-merge) and serializes (`concurrency: cancel-in-progress: false`, `max-parallel: 1`),
with staging/prod gated by GitHub Environment protection (required reviewers).

---

## 3. Decision record

| Decision | Rationale | Trade-off accepted | Source ADR |
|---|---|---|---|
| Reusable `workflow_call` pipelines (`reusable-*.yml`) + local composite actions in `.github/actions/` | DRY: one hardened build/scan/sign/deploy path reused by every service repo; the platform team owns the pipeline, app teams only pass `with:` inputs | Indirection; callers must keep input contracts in sync; local mocks here shadow a shared `{{PLATFORM_WORKFLOWS_REPO}}` in production | `ADR-0015 reusable-ci-pipelines` |
| Keyless OIDC to the cloud (`aws-actions/configure-aws-credentials`, GCP WIF) — **no static keys** | Short-lived, per-run, per-role credentials; nothing to leak or rotate; scoped plan-vs-apply roles | Requires an IAM OIDC provider + trust policy per role; steps must degrade gracefully when the role var is unset (forks) | `ADR-0015`, `ADR-0022` |
| Split IaC roles: `TERRAFORM_PLAN_ROLE_ARN` (read-only) vs `TERRAFORM_APPLY_ROLE_ARN` (write) | Least privilege: PRs can only plan; write is reachable only post-merge from `main` | Two roles + two trust policies to maintain | `ADR-0015` |
| Tier-1 supply-chain: Trivy scan → Syft SBOM → cosign **keyless** sign-by-digest → SBOM attest | Provenance + tamper evidence on every pushed image; sign the *digest*, not a mutable tag | Sigstore/Fulcio/Rekor dependency; cosign verify must be enforced at admission to have teeth | `ADR-0016 tier1-supply-chain-hardening` |
| CI runtime hardening: `step-security/harden-runner` (egress audit) first step; `zizmor` Actions-SAST; third-party actions SHA-pinned with version comment | Detect exfiltration/tampering in the runner; catch template-injection & unpinned-action risks in our own workflows | `audit` mode does not yet *block* egress; SHA pins need Renovate to stay current | `ADR-0022 ci-supply-chain-runtime-hardening` |
| Access-Analyzer policy gate on SCP/RCP diffs (`check-no-new-access`, `check-access-not-granted`) | Prove an org-policy change grants **no new effective access** and keeps sensitive actions denied, before it reaches `main` | Paid AWS feature → bounded to PRs touching `modules/{scps,rcps}`; advisory until backlog clean | `ADR-0017 resource-side-perimeter-and-declarative-org-controls` |
| Infracost PR gate with warn ($100) + block ($500) thresholds and a `cost-approved` label bypass | Make monthly cost delta visible on every IaC PR and hard-stop runaway spend without a human-in-loop escape hatch | Estimate ≠ bill; label bypass is an honor-system escape hatch | `ADR-0027 kubernetes-cost-opencost-cur` (PR-time complement to runtime OpenCost) |
| Scheduled drift detection → GitHub Issues (alert-only, no auto-remediation) | Daily proof that `main` still matches reality; a human decides apply-vs-import | Drift can persist a day; remediation is manual | (drift design; complements `ADR-0048`, `ADR-0038`) |
| OPA/conftest against plan JSON **plus** `opa test` rego unit tests | Policy-as-code enforced on real plans; policies themselves are unit-tested so a bad rule can't ship | Requires a plan (hence OIDC) for the conftest half; unit half always runs | `ADR-0028 unified-platform-tagging-and-labeling-taxonomy` (tag/label policies) |
| Native `terraform test` gates; `terraform-compliance` BDD is advisory | HCL-native tests are deterministic and offline; BDD `.feature` suite is exploratory | Two overlapping test frameworks to maintain | `ADR-0004 terragrunt-over-plain-terraform` |
| Terratest nightly (real infra) separate from PR path | Real create/destroy integration coverage without slowing or paying on every PR | Costs real cloud spend nightly; flakes open issues, not block merges | (test strategy) |
| ECR pull-through cache + registry hardening for image pulls | Reduce Docker Hub rate-limit/exfil risk; cache upstream images in-account | Cache warm-up; registry IAM to maintain | `ADR-0029 ecr-pull-through-cache` |
| ML CI/CD as control-plane only: CI triggers Airflow DAG, polls an **eval-debate** gate, registers to MLflow, promotes via Kargo | Training stays on the cluster (GPU); CI orchestrates and gates on eval, keeping GitHub runners cheap | CI depends on live Airflow/MLflow endpoints; eval gate is a timed poll | `ADR-0037 ml-cicd-pipeline-mlflow`, `ADR-0048 aws-ml-cicd-registry-drift` |
| Version-pin tooling in `versions.hcl` mirrored to `.tool-versions`; bump policy = PR (minor) / ADR (major) | One source of truth for TF/TG versions across `root.hcl`, CI matrices, and asdf/mise | Manual mirror between the two files | (see IaC spec; `ADR-0002 tf-only-state-backend`) |

---

## 4. Implementation blueprint

### 4.1 Directory layout

```
.github/
├── dependabot.yml                  # gomod, github-actions, docker, terraform ecosystems
├── zizmor.yml                      # Actions-SAST config
├── workflows/                      # 34 workflows (see §4.6 matrix)
│   ├── terragrunt-validate.yml     ├── terragrunt-plan.yml      ├── terragrunt-apply.yml
│   ├── terraform-validate.yml      ├── terraform-compliance.yml ├── tfsec.yml
│   ├── well-architected.yml        ├── conftest-opa.yml         ├── policy-access-check.yml
│   ├── infracost.yml               ├── drift-detection.yml      ├── terratest.yml
│   ├── secret-scan.yml             ├── zizmor.yml               ├── shellcheck.yml
│   ├── yaml-lint.yml               ├── go-ci.yml                ├── helm-validate.yml
│   ├── k8s-validate.yml            ├── version-manifest-validate.yml
│   ├── container-build.yml         ├── validate-agents.yml      ├── generate-diagrams.yml
│   ├── generate-inventory.yml      ├── ml-pipeline.yml          ├── ml-pipeline-aws.yml
│   ├── ml-pipeline-baremetal.yml   ├── ml-monitoring-baremetal-validate.yml
│   ├── reusable-build-and-push.yml ├── reusable-deploy-via-argocd.yml
│   ├── reusable-manifest-validate.yml ├── reusable-sast.yml     ├── reusable-dep-scan.yml
│   └── reusable-pipeline-demo.yml
└── actions/                        # 10 local composites (SHA-pinned third-party inside)
    ├── harden-runner/  argocd-tag-bump/  argocd-wait-sync-and-smoke/  cosign-sign/
    ├── manifest-validate/  syft-sbom/  trivy-scan/  sast-codeql/
    └── node-dep-scan/  python-dep-scan/
scripts/
    detect-drift.sh  policy-access-check.sh  break-glass.sh  deploy-state-backends.sh
    preflight-check.sh  validate.sh  cleanup.sh  version-diff.sh  validate-agents.py
    generate-infra-diagrams.py
tests/
    terraform/   # Terratest (Go): vpc_test.go s3_test.go eks_test.go + helpers/ fixtures/
    opa/         # rego deny rules + *_test.rego unit tests
    compliance/  # terraform-compliance BDD *.feature
    integration/ e2e/ gpu-inference/   # controller & cluster tests
terragrunt/versions.hcl  +  .tool-versions   # pinned tool versions (mirrored)
```

### 4.2 Tool & action version pins (as pinned in this estate)

`terragrunt/versions.hcl` (source of truth) + `.tool-versions` (mirror):

```hcl
terraform_version  = "1.14.8"      # = pinned; CI env TF_VERSION
terragrunt_version = "1.0.8"       # = pinned; CI env TG_VERSION
provider_versions = { aws = "~> 6.0", helm = "~> 2.12", kubernetes = "~> 2.30",
                      null = "~> 3.2", random = "~> 3.6", tls = "~> 4.0" }
```

CI-pinned tool versions: TFLint `v0.53.0`, tfsec `v1.28.11`, Conftest `0.57.0`, OPA `1.17.1`,
kubeconform `v0.6.7`, Helm `3.16.2`/`3.17.0`, Go `1.22`, Python `3.12`/`3.10`, Node `20`,
gosec `v2.22.0`, pip-audit `2.7.3`, osv-scanner `1.9.1`, cosign `v2.4.1`, syft via
`anchore/sbom-action`, Kubernetes schema target `1.32.0`.

Action-pin convention (`ADR-0022`): platform-owned actions use tag pins (`@v4`, `@v6`); the most
security-sensitive third-party actions are **commit-SHA pinned with a version comment** so Renovate
(`ADR-0015`) can bump them — e.g. `step-security/harden-runner@9af89fc7...  # v2.19.4`,
`sigstore/cosign-installer@1aa8e0f...  # v3.7.0`, `zizmorcore/zizmor-action@5f14fd08...  # v0.5.6`,
`aws-actions/configure-aws-credentials@e3dd6a42...  # v4.0.2`.

### 4.3 IaC PR gate — the load-bearing pieces

**Change detection → dynamic matrix** (shared shape across `terragrunt-plan`, `conftest-opa`,
`infracost`): diff against the base, keep only IaC files under known env roots, emit a JSON array:

```yaml
- run: |
    git diff --name-only origin/main...HEAD \
      | grep -E '\.(hcl|tf|tfvars)$' \
      | grep -E '^terragrunt/(dev|staging|prod|management|log-archive|security|network|third-party)/|^catalog/units/' \
      | xargs -n1 dirname | sort -u | jq -R -s -c 'split("\n") | map(select(length>0))'
```

**OIDC plan step** (soft when the role var is unset, so forks/mock repos pass):

```yaml
- name: Configure AWS credentials via OIDC
  uses: aws-actions/configure-aws-credentials@v6
  if: vars.TERRAFORM_PLAN_ROLE_ARN != ''       # skip on forks → advisory no-op
  continue-on-error: true
  with:
    role-to-assume: ${{ vars.TERRAFORM_PLAN_ROLE_ARN }}   # arn:aws:iam::{{PROD_ACCOUNT_ID}}:role/...
    aws-region: {{PRIMARY_REGION}}
- run: terragrunt plan -no-color -out=tfplan && terragrunt show -json tfplan > plan.json
```

**Summary gate job** turns a fan-out matrix into one required check:

```yaml
plan-status:
  needs: [detect-changes, plan]
  if: always()
  steps:
    - run: |
        if [ "${{ needs.plan.result }}" = "failure" ]; then
          echo "::error::Terragrunt plan failed"; exit 1
        fi
```

**tflint** is the hard security-lint gate; **tfsec/checkov are soft** today:

```yaml
- run: tflint --recursive --config "$(pwd)/.tflint.hcl" --format compact \
        --minimum-failure-severity error --chdir terraform/modules
- uses: bridgecrewio/checkov-action@v12
  with: { directory: terraform/modules, soft_fail: true, skip_check: "CKV_AWS_144,CKV_AWS_41,..." }
```

### 4.4 OPA/conftest gate (`conftest-opa.yml`)

Two independent hard sub-gates aggregated by `opa-status`:

```yaml
# (1) Always runs — no cloud creds needed — unit-tests the policies themselves:
- run: |
    opa check --strict tests/opa/
    opa test tests/opa/ -v          # runs *_test.rego (platform_tags_*_test.rego, ...)
# (2) Per changed module — conftest against the plan JSON (needs OIDC plan):
- run: |
    conftest test plan.json --policy "$GITHUB_WORKSPACE/tests/opa" --output json
```
The github-script step calls `core.setFailed(...)` on a conftest `failure`, which fails the job →
`opa-status` blocks the merge. Policies in `tests/opa/` enforce: no public S3
(`s3_no_public_access.rego`), no `0.0.0.0/0` SG ingress (`no_unrestricted_sg_ingress.rego`),
required platform tags (`platform_tags*.rego`, `required_tags.rego` — `ADR-0028`), no hardcoded
credentials (`no_hardcoded_credentials.rego`), encryption at rest (`encryption_at_rest.rego`).

### 4.5 Supply-chain build path (`container-build.yml` + composites)

Order is load-bearing — **harden-runner must be the first step**:

```yaml
permissions: { id-token: write, contents: read, security-events: write }
steps:
  - uses: ./.github/actions/harden-runner        # egress-policy: audit — FIRST
  - uses: actions/checkout@v4
  - uses: aws-actions/configure-aws-credentials@v6   # OIDC, if vars.AWS_ROLE_ARN != ''
    with: { role-to-assume: ${{ vars.AWS_ROLE_ARN }}, aws-region: {{PRIMARY_REGION}} }
  - uses: aws-actions/amazon-ecr-login@v2
  - uses: docker/build-push-action@v6            # build+load, push:false (scan before push)
  - uses: aquasecurity/trivy-action@v0.35.0      # exit-code:0 here (advisory), sarif upload
  - uses: ./.github/actions/syft-sbom            # spdx-json SBOM artifact
  - id: push-ecr
    if: github.ref == 'refs/heads/main' && github.event_name == 'push' && vars.AWS_ROLE_ARN != ''
    uses: docker/build-push-action@v6            # push:true only post-merge
  - if: steps.push-ecr.outputs.digest != ''
    uses: ./.github/actions/cosign-sign          # keyless sign the DIGEST + attest SBOM
    with: { image-ref: "${{ steps.meta.outputs.image }}@${{ steps.push-ecr.outputs.digest }}" }
```

The reusable variant (`reusable-build-and-push.yml`) is the hardened default: same chain but Trivy
`exit-code: "1"` (**blocking**) and `sign: true` by default. Callers pass
`app_name`/`ecr_repository`/`build_context` and get back `image_uri`, `image_digest`, `image_tag`
as `workflow_call` outputs. `reusable-pipeline-demo.yml` shows the canonical chain:
`build (reusable-build-and-push) → deploy (reusable-deploy-via-argocd)` wired through job outputs.
The signed ECR image is addressed as
`{{PROD_ACCOUNT_ID}}.dkr.ecr.{{PRIMARY_REGION}}.amazonaws.com/<repo>@sha256:...`.

### 4.6 Full pipeline matrix

| Workflow | Trigger | Gate/Advisory | Tools | Failure means |
|---|---|---|---|---|
| `terragrunt-validate` | PR/push (`terragrunt,catalog`) | **Gate** | `terragrunt hcl format`, brace check | HCL unformatted / malformed |
| `terraform-validate` | PR/push (`terraform,catalog`) | **Gate** (fmt/validate/tflint); advisory (trivy/checkov) | `terraform fmt/validate`, `tflint`, Trivy, Checkov | Module invalid or lint error |
| `terragrunt-plan` | PR (IaC paths) | **Gate** (summary) | Terragrunt plan + OIDC, PR comment | Plan errored for a changed unit |
| `terragrunt-apply` | push→main / dispatch | Post-merge deploy | Terragrunt apply + OIDC, Slack notify | Apply failed (Slack alert) |
| `terraform-compliance` | PR/push (`*.tf`,`*.feature`) | **Gate** (native `terraform test`); advisory (BDD) | `terraform test`, `terraform-compliance` | Native module test failed |
| `tfsec` | PR/push (IaC) | Advisory | tfsec HIGH+ → SARIF + PR comment | (reported, not blocked) |
| `well-architected` | PR/push (`terraform`) | Advisory | Checkov `soft_fail` | (reported) |
| `conftest-opa` | PR (IaC + `tests/opa`) | **Gate** (unit always; conftest w/ OIDC) | `opa check/test`, `conftest` | Policy violation / bad rego |
| `policy-access-check` | PR (`scps,rcps`) / dispatch | Advisory (`ADVISORY:true`) | AWS Access Analyzer custom checks | SCP/RCP widens access (reported) |
| `infracost` | PR (IaC) | **Gate** over $500 | `infracost breakdown/diff`, PR comment | Monthly delta > block threshold |
| `drift-detection` | cron 06:00 UTC daily / dispatch | Scheduled (non-gating) | `scripts/detect-drift.sh`, Issues API | Opens a `drift,automated` issue |
| `terratest` | cron 02:00 UTC / PR (test paths) / dispatch | Gate (unit); nightly (integration) | Go, Terratest, OIDC | Unit build/vet fail; nightly issue |
| `secret-scan` | PR/push | **Gate** | `gitleaks` (+ SARIF) | Secret detected |
| `zizmor` | PR/push (`.github/**`) | Advisory | `zizmor` Actions-SAST → SARIF | (reported via Code Scanning) |
| `shellcheck` | PR/push (`*.sh`) | **Gate** (severity=error) | `shellcheck` | Shell script error |
| `yaml-lint` | PR/push (`*.yml`) | **Gate** | `yamllint` | YAML lint violation |
| `go-ci` | PR/push (Go dirs) | Advisory (`continue-on-error`) | `go build/test -race`, `gosec` | (reported) |
| `helm-validate` | PR/push | **Gate** | `helm template` \| `kubeconform -strict` | Chart renders invalid manifests |
| `k8s-validate` | PR/push (`k8s,argocd,...`) | **Gate** | `kubeconform -strict` (matrix) | Manifest schema invalid |
| `version-manifest-validate` | PR/push (`versions/**`) | **Gate** | `ajv` schema, tag regex | Bad version manifest |
| `ml-monitoring-baremetal-validate` | PR (ML-mon paths) | **Gate** | helm lint, yamllint, terragrunt validate | Chart/label/HCL invalid |
| `container-build` | PR/push (service dirs) | Advisory scan; post-merge push+sign | Trivy, Syft, cosign, ECR | (scan reported; push/sign on main) |
| `validate-agents` | PR/push | **Gate** | `scripts/validate-agents.py` | Agent manifest invalid |
| `generate-diagrams` | PR (artifact)/push (commit) | Non-gating | `scripts/generate-infra-diagrams.py` | (auto-commit on main) |
| `generate-inventory` | push (`apps,envs,argocd`) | Non-gating | shell, Helm | (auto-commits `DEPLOYMENTS.md`) |
| `ml-pipeline` | dispatch / push (`models,adapters`) | Release (eval-gated) | GCP WIF, Airflow, MLflow, Kargo | Train/eval-debate gate failed |
| `ml-pipeline-aws` | same | Release (eval-gated) | AWS OIDC, ECR, Airflow, MLflow | same (AWS variant) |
| `ml-pipeline-baremetal` | same (`staging/prod`) | Release (eval-gated) | Airflow, MLflow+MinIO, cosign | same (Talos/UK-isolated) |
| `reusable-build-and-push` | `workflow_call` | **Gate** (Trivy `exit-code:1`) | build, Trivy, Syft, cosign | CRITICAL/HIGH CVE in image |
| `reusable-deploy-via-argocd` | `workflow_call` | Deploy (GitOps) | `argocd-tag-bump` (PR to config repo) | Bump PR fails (prod = human gate) |
| `reusable-manifest-validate` | `workflow_call` | Gate (lint/kubeconform); advisory (conftest) | helm, kubeconform, conftest | Rendered chart invalid |
| `reusable-sast` | `workflow_call` | Advisory (`fail_on_error:false`) | CodeQL | (reported via Code Scanning) |
| `reusable-dep-scan` | `workflow_call` | **Gate** (default) | pip-audit / npm audit + osv-scanner | CRITICAL/HIGH dependency CVE |
| `reusable-pipeline-demo` | dispatch only | Manual demo | chains the two reusables | n/a |

### 4.7 Drift detection & the cost gate

`drift-detection.yml` runs `scripts/detect-drift.sh --environment <env> --report-format json`
(exit `1` = drift, `0` = clean, `2` = script error) per env matrix, then the `report` job parses the
JSON and, per drifted env, **creates or comments on** a GitHub Issue labeled `drift,automated`;
`close-resolved` closes issues once drift clears. **Alert-only — never auto-applies** (the issue body
carries `terragrunt run --all apply` / `terraform import` guidance for a human).

`infracost.yml` sets `WARN_THRESHOLD: 100`, `BLOCK_THRESHOLD: 500` (USD/month), checks out base +
PR SHAs, runs `infracost breakdown` on each then `infracost diff --compare-to`, posts/updates one
PR comment, and enforces: `cost-approved` label ⇒ pass; else abs monthly increase `> $500` ⇒
`exit 1`; `> $100` ⇒ warning only. `secrets.INFRACOST_API_KEY` is the only secret.

### 4.8 Test strategy (`tests/`, controllers, `go-ci`)

- **Terratest (Go, `tests/terraform/`).** `vpc_test.go`, `s3_test.go`, `eks_test.go` + `helpers/`
  (`SkipIfShort`, `SkipIfCI`) + `fixtures/`. Three tiers: **unit** (`go build/vet`, no creds — the
  PR gate), **plan** (`terraform plan` only, needs OIDC), **integration** (`defer terraform.Destroy()`,
  real infra, nightly). `terratest.yml` runs unit+plan on PR and integration nightly (`0 2 * * *`).
- **OPA unit tests (`tests/opa/*_test.rego`).** Run by `opa test` in `conftest-opa` with no cloud
  creds — the policies are tested before they gate any plan.
- **BDD compliance (`tests/compliance/*.feature`).** `terraform-compliance` runs these against plan
  JSON but with `--no-failure` (advisory); native `terraform test` is the enforcing layer.
- **Controllers (`dns-monitor`, `failover-controller`, `services/hello-world`).** `go-ci.yml`:
  `go build`, `go test -race`, `gosec` — advisory (`continue-on-error: true`) today.
- **Cluster tests (`tests/integration/`, `tests/e2e/`, `tests/gpu-inference/`).** Python integration
  (`test_dns_sync.py`, `test_state_machine.py`, `test_health_monitoring.py`), a full-failover E2E, and
  GPU-inference YAML checks (DRA scheduling, NCCL benchmark, gang recovery).

### 4.9 Dependabot posture (`.github/dependabot.yml`)

Five update streams: `gomod` (weekly, `/dns-monitor`, `/failover-controller`), `github-actions`
(weekly, `/`), `docker` (weekly, both controllers), `terraform` (monthly, `/terraform/modules`).
Dependabot covers *version freshness*; Renovate (`ADR-0015`) owns the SHA-pin bumps for
security-sensitive third-party actions. `reusable-dep-scan` (pip-audit/npm+osv) covers *CVE* gating
at PR time; the three are complementary.

### 4.10 Branch protection assumptions

Branch protection on `main` is the enforcement point — the workflows only *produce* checks; they
block nothing unless `main` requires them. Assume, per rebuild:

- Require a PR before merge to `main` (no direct pushes, except the bot carve-out for
  `generate-diagrams`/`generate-inventory`, which push `[skip ci]` commits).
- Required status checks = every §2.2 hard gate (summary jobs where a matrix fans out:
  `plan-status`, `opa-status`, `compliance-summary`). Advisory gates are **not** required.
- Require branches up to date before merge; dismiss stale approvals; require conversation
  resolution.
- GitHub **Environments** `development` / `staging` / `production` carry the deploy approvals —
  `terragrunt-apply` and ML `deploy` map the target env to an Environment, and staging/prod require
  reviewers. This, not an `if:`, is the apply gate.
- Enable Code Scanning; make the advisory scanners' Code-Scanning checks *required* only when you
  flip them to blocking.

### 4.11 Ordering / dependencies (what must exist before what)

1. `versions.hcl` + `.tool-versions` (pins) → every workflow's `setup-*` step reads these.
2. GitHub OIDC provider + IAM roles (`TERRAFORM_PLAN_ROLE_ARN`, `..._APPLY_...`, `ECR_PUSH_ROLE_ARN`,
   `POLICY_CHECK_ROLE_ARN`, `AWS_CI_ROLE_ARN`) → OIDC steps are no-ops until these repo
   variables/secrets exist (deliberate, so the repo is CI-green from an empty account).
3. Remote state backend (`scripts/deploy-state-backends.sh`, `ADR-0002`) → before any `plan`/`apply`.
4. `tests/opa/` policies + `.tflint.hcl`, `.checkov.yml`, `.gitleaks.toml`, `.yamllint.yml`,
   `.audit-ignore`, `zizmor.yml` config → before the corresponding gates bite.
5. Branch protection with the hard-gate jobs as required checks → last, once they pass on a PR.
6. `{{PLATFORM_WORKFLOWS_REPO}}` + `{{ARGOCD_CONFIG_REPO}}` + `ARGOCD_BOT_TOKEN` → before
   reusable build/deploy pipelines can push image bumps.

### 4.12 Porting the gates to GitLab CI

The design maps cleanly onto GitLab — the pieces and their GitLab equivalents:

| GitHub Actions piece | GitLab CI equivalent |
|---|---|
| Reusable `workflow_call` workflow | `include:` a template + `extends:` / hidden `.job` anchors; or a CI/CD **component** (`spec: inputs:`) |
| Composite action (`.github/actions/*`) | shared job template in `{{PLATFORM_WORKFLOWS_REPO}}` + `include:` |
| OIDC `configure-aws-credentials` | GitLab OIDC `id_tokens:` + `aws sts assume-role-with-web-identity` (or `assume_role_with_web_identity`) |
| `permissions: id-token: write` | `id_tokens: { AWS_TOKEN: { aud: ... } }` |
| `on: pull_request` + `paths:` | `rules: - if: '$CI_PIPELINE_SOURCE == "merge_request_event"' changes:` |
| `on: schedule` (drift/nightly) | pipeline **schedules** + `rules: - if: '$CI_PIPELINE_SOURCE == "schedule"'` |
| Required status checks | Merge-request **approval rules** + "pipelines must succeed" |
| GitHub Environment approvals | **Protected environments** with required approvers |
| SARIF → Code Scanning | GitLab **SAST/Container-Scanning reports** (`artifacts: reports: sast/…`) |
| `gitleaks`, `trivy`, `checkov`, `tflint`, `conftest`, `infracost` | identical CLIs in `script:` — the tools are portable; only the wiring changes |
| Dynamic matrix (`fromJson(detect-changes)`) | `parallel: matrix:` or child-pipeline `trigger:` with a generated YAML |
| Auto-commit back to `main` | job with a project **access token**/CI push + `[skip ci]` (`$CI_COMMIT_MESSAGE`) |
| Dependabot | GitLab **Dependency Scanning** + **Renovate** (self-hosted) for version bumps |

Keep the reusable pieces reusable: put the hardened build/scan/sign template and the IaC-loop
template in a central project and `include:` them, exactly as the reusable workflows are meant to
live in `{{PLATFORM_WORKFLOWS_REPO}}` here.

### 4.13 Adoption order (which gates first)

For a client standing this up incrementally, land gates in this order (cheapest/safest → deepest):

1. **Hygiene, no creds:** `yaml-lint`, `shellcheck`, `secret-scan` (gitleaks), `terragrunt-validate`,
   `terraform-validate` (fmt/validate/tflint). Instant value, zero cloud wiring.
2. **Policy-as-code, no creds:** `opa test` half of `conftest-opa`; `helm-validate`, `k8s-validate`,
   `version-manifest-validate`. Still no cloud role required.
3. **OIDC + plan-time depth:** wire `TERRAFORM_PLAN_ROLE_ARN`, then `terragrunt-plan`, the conftest
   half of `conftest-opa`, and `infracost` (advisory first, then flip the block threshold on).
4. **Supply chain:** `harden-runner` + `reusable-build-and-push` (Trivy blocking, SBOM, cosign),
   `reusable-dep-scan`, `zizmor`, `reusable-sast`.
5. **Post-merge delivery:** `terragrunt-apply` (with Environment approvals), `reusable-deploy-via-argocd`.
6. **Scheduled + advanced:** `drift-detection`, `terratest` nightly, `policy-access-check`
   (flip `ADVISORY:false` once clean), ML pipelines.

Flip advisory scanners (`tfsec`, `checkov`/`well-architected`, `zizmor`, CodeQL, Access-Analyzer)
to blocking only after their finding backlog is remediated.

---

## 5. Parameterization table

### 5.1 Placeholders (register recurring ones in SPEC-00)

| Placeholder | Meaning | Default/shape here |
|---|---|---|
| `{{VCS_ORG}}` | Git hosting org | (SPEC-00) |
| `{{PRIMARY_REGION}}` | CI cloud region | `eu-west-1` (Terratest uses `us-east-1`) |
| `{{PROD_ACCOUNT_ID}}` | account behind OIDC roles | (SPEC-00; never literal in workflows) |
| `{{DOMAIN}}` | root DNS zone | (SPEC-00) |
| `{{ARGOCD_CONFIG_REPO}}` | GitOps config repo the deploy pipeline PRs into | `{{VCS_ORG}}/argocd` |
| `{{PLATFORM_WORKFLOWS_REPO}}` | shared reusable-workflow repo | `{{VCS_ORG}}/platform-workflows` |
| `{{ARGOCD_SERVER}}` | ArgoCD API host (smoke/wait action) | `argocd.{{DOMAIN}}` |
| `{{CI_BOT_NAME}}` / `{{CI_BOT_EMAIL}}` | git committer for auto-commits/PRs | `platform-ci[bot]` / `ci@{{DOMAIN}}` |
| `{{CI_FEATURE_BRANCH}}` | long-lived migration branch also gated | `feature/**` |

**GitHub Actions variables (`vars.*`) — OIDC role ARNs & endpoints (never hardcode):**
`TERRAFORM_PLAN_ROLE_ARN`, `TERRAFORM_APPLY_ROLE_ARN`, `POLICY_CHECK_ROLE_ARN`, `AWS_ROLE_ARN`,
`ECR_PUSH_ROLE_ARN`, `AWS_CI_ROLE_ARN`, `AWS_ACCOUNT_ID`, `AWS_REGION`, `GCP_WIF_PROVIDER`,
`GCP_CI_SERVICE_ACCOUNT`, `ML_IMAGE_REPO`, `AIRFLOW_BASE_URL`, `MLFLOW_TRACKING_URI`,
`AIRFLOW_BAREMETAL_BASE_URL`, `MLFLOW_BAREMETAL_TRACKING_URI`, `MLFLOW_S3_ENDPOINT_URL`.

**Secrets (`secrets.*`):** `INFRACOST_API_KEY`, `SLACK_WEBHOOK_URL`, `ARGOCD_BOT_TOKEN`,
`AIRFLOW_API_TOKEN`, `AIRFLOW_BAREMETAL_API_TOKEN`, `MLFLOW_S3_ACCESS_KEY_ID`,
`MLFLOW_S3_SECRET_ACCESS_KEY`, `GITHUB_TOKEN` (built-in).

### 5.2 Sizing / policy knobs

| Knob | Default here | Guidance to resize |
|---|---|---|
| Infracost `WARN_THRESHOLD` / `BLOCK_THRESHOLD` | `$100` / `$500`/mo | Set block to a real per-PR risk budget; keep the `cost-approved` label escape hatch |
| Drift cron | `0 6 * * *` (before EU workday) | Match the team's timezone; keep `cancel-in-progress: false` |
| Terratest cron | `0 2 * * *` nightly | Off-hours; integration matrix = the modules you can afford to create nightly |
| Kubernetes schema target | `1.32.0` | Track the cluster's control-plane minor |
| Trivy severity gate | `CRITICAL,HIGH` | Add `MEDIUM` once the backlog is clean |
| gosec excludes | `G104,G114,G306` | Narrow as findings are fixed |
| `terragrunt-apply` parallelism | `max-parallel: 1` | Keep serial for shared state; per-env roles allow more |
| Access-Analyzer `ADVISORY` | `true` | Flip to `false` to make SCP/RCP checks blocking (`ADR-0017` step 6) |
| Soft-fail scanners (`tfsec`, `checkov`, `zizmor`, CodeQL) | soft today | Flip `soft_fail:false` / `fail_on_error:true` per gate once clean |
| ML eval-debate poll | `40 × 30s` (20 min) | Size to the real DAG runtime + margin |

---

## 6. Best practices distilled

1. **Never store long-lived cloud keys in CI.** Every cloud call uses OIDC/WIF to assume a
   short-lived, per-run role. *Why:* nothing to leak, nothing to rotate, and plan-vs-apply roles
   enforce least privilege at the credential layer, not just in code.
2. **Split read (plan) and write (apply) roles, and make apply unreachable from a PR.** Plan runs on
   PRs with a read-only role; apply runs only on `push → main` with a write role, serialized, behind
   GitHub Environment approvals for staging/prod. *Why:* a malicious PR can never mutate infra.
3. **Degrade OIDC steps gracefully** with `if: vars.<ROLE> != ''` + `continue-on-error`. *Why:* the
   repo stays CI-green from an empty account / a fork / a mock, so onboarding isn't blocked on IAM.
4. **Turn a fan-out matrix into one required check** via an `if: always()` summary job that `exit 1`s
   on any child failure. *Why:* branch protection needs a stable check name even when the matrix is
   dynamic (`fromJson(detect-changes.outputs.modules)`).
5. **Detect changes and scope every IaC gate to changed units.** *Why:* PR feedback in minutes, and
   cost/plan calls are bounded to what actually changed.
6. **Unit-test your policies, not just your infra.** `opa test tests/opa/*_test.rego` runs
   unconditionally (no cloud creds) so a broken `deny` rule fails before it can wave a bad plan
   through. *Why:* policy-as-code is code; ship it tested.
7. **Scan before you push; sign the digest after.** Build+load locally → Trivy → SBOM, then push,
   then cosign **keyless** sign the immutable `@sha256:` digest and attest the SBOM. *Why:* you never
   publish an unscanned image, and the signature binds to content, not a movable tag.
8. **`harden-runner` is the first step of every build job** in `audit` mode. *Why:* it baselines the
   runner's egress so you can later flip to `block` with an allowlist and catch exfiltration.
9. **SHA-pin security-sensitive third-party actions with a version comment**, and let Renovate bump
   them. *Why:* tag pins are mutable; SHA pins are not, and the comment keeps them readable/bumpable.
10. **Stage gates advisory-first, then flip to blocking.** New scanners (`tfsec`, `checkov`,
    `zizmor`, CodeQL, Access-Analyzer) land as soft-fail + SARIF, and become blocking once the finding
    backlog is remediated. *Why:* you get visibility immediately without wedging the merge queue.
11. **Cost is a gate, not a report.** Infracost warns at one threshold and *blocks* at another, with a
    labelled human override. *Why:* a comment nobody reads is not a control.
12. **Drift is proven daily and surfaced as an issue, not auto-fixed.** *Why:* a human decides
    apply-vs-`terraform import`; auto-remediation on a scheduled job is how you amplify a mistake.
13. **Factor the pipeline into reusable `workflow_call` workflows + composite actions.** The platform
    team owns the hardened path; app repos pass `with:` inputs and inherit signing/scanning for free.
    *Why:* DRY across dozens of service repos and one place to raise the security bar.
14. **Keep ML CI as a control plane.** CI triggers the training DAG, polls a quantitative
    **eval-debate** gate, registers to MLflow, and promotes via Kargo — it does not train on the
    runner. *Why:* GPU training belongs on the cluster; CI's job is orchestration and gating.
15. **One source of truth for versions** (`versions.hcl` → `.tool-versions` mirror), consumed by
    `root.hcl`, CI matrices, and asdf/mise. *Why:* the local loop and CI run byte-identical tool
    versions, so "works on my machine" and "passes in CI" converge.

---

## 7. Known pitfalls

1. **OIDC-less repos silently skip the deep gates.** When `TERRAFORM_PLAN_ROLE_ARN` is unset, the
   plan/conftest/access-analyzer steps become advisory no-ops and the PR still goes green. Great for
   forks; **dangerous if production believes those gates ran.** Assert the role vars are set on the
   real repo (see §8) and treat "skipped" ≠ "passed".
2. **As-built divergence:** soft-fail scanners give a false sense of coverage. Advisory gates
   (`tfsec`, `well-architected`/Checkov, `zizmor`, CodeQL) are **pending the hard-gate flip per the
   in-repo roadmap** — a CRITICAL finding does **not** block today. Track that backlog explicitly or
   it never happens.
3. **As-built divergence:** `terraform-compliance` BDD is decorative until wired to fail. It runs
   with `--no-failure` *and* `|| true`; only the native `terraform test` job actually gates. Don't
   mistake a green compliance job for enforced compliance.
4. **As-built divergence:** region inconsistency. IaC workflows hardcode `{{PRIMARY_REGION}}`
   (`eu-west-1`) while Terratest uses `us-east-1`. Parameterize both or integration tests hit the
   wrong partition.
5. **As-built divergence:** two overlapping Terraform versions in CI — `1.14.8` (validate/plan) vs
   `~1.11` / `1.11.0` (compliance/terratest). Converge them or a module that passes `validate` can
   fail `terraform test` on a version-gated feature.
6. **Auto-commit workflows push straight to `main`.** `generate-diagrams` and `generate-inventory`
   commit with `[skip ci]` / `contents: write`. If branch protection ever requires a PR for `main`,
   these break — carve out the bot or convert them to PRs.
7. **cosign signatures without admission enforcement are theater.** Signing images is only a control
   if the cluster *verifies* the signature at admission (Kyverno/VAP, `ADR-0020`). Ship both.
8. **Infracost is an estimate, and the `cost-approved` label is an honor system.** A mislabeled PR
   bypasses the block. Restrict who can add the label.
9. **Access-Analyzer gating must read the JSON `result`, not the CLI exit code** — the AWS CLI can
   exit `0` on a `FAIL` result (`ADR-0017`). `policy-access-check.sh` handles this; a hand-rolled
   reimplementation will silently pass failing policies.
10. **ML pipelines depend on live external endpoints** (Airflow, MLflow, MinIO). The eval gate is a
    bounded poll (40 × 30s = 20 min); a slow DAG times out and fails the release even when training
    would have succeeded. Size the poll to the real DAG runtime.
11. **Dependabot ≠ CVE gate.** Dependabot only opens version-bump PRs; the blocking CVE check is
    `reusable-dep-scan`. Enabling one is not enabling the other.
12. **As-built divergence:** `workflow_call` reusables live locally here as mocks. In production they
    belong in `{{PLATFORM_WORKFLOWS_REPO}}`
    (`uses: {{PLATFORM_WORKFLOWS_REPO}}/.github/workflows/<wf>.yml@<ref>`). Don't ship the local
    copies to every service repo — centralize them.

---

## 8. Acceptance checklist

A rebuild passes when:

- [ ] From a clean checkout, `terragrunt hcl format --check` and `terraform fmt -check -recursive`
      are clean; `tflint --recursive` reports no error-severity findings.
- [ ] A PR touching one Terragrunt unit triggers **only** that unit's plan (dynamic matrix works),
      and `plan-status` is a single required check.
- [ ] With OIDC roles configured, `terragrunt-plan`, `conftest-opa`, and `policy-access-check`
      actually assume a role and run against real plan JSON (job logs show `Assumed role`, not
      "skipped").
- [ ] `opa test tests/opa/` passes and runs on a PR **with no cloud credentials**.
- [ ] A PR that adds a public S3 bucket / `0.0.0.0/0` SG ingress / an untagged resource is **blocked**
      by `conftest-opa`.
- [ ] A PR whose estimated monthly cost delta exceeds `$500` is **blocked** by `infracost`, and adding
      the `cost-approved` label unblocks it.
- [ ] A committed secret is caught by `secret-scan` (gitleaks) and the PR is blocked.
- [ ] `container-build` on a non-`main` PR **builds + scans but does not push**; a `push → main`
      builds, pushes to ECR, and **cosign-signs the digest** (verify with `cosign verify`).
- [ ] `reusable-build-and-push` fails the build on a seeded CRITICAL CVE (`exit-code: 1`).
- [ ] `terragrunt apply` **cannot** be triggered from a feature branch or a PR; staging/prod applies
      require a GitHub Environment reviewer.
- [ ] The daily drift job opens a `drift,automated` issue on injected drift and closes it once the
      drift is reconciled.
- [ ] Branch protection lists every §2.2 hard gate as a required status check; advisory gates are not
      required.
- [ ] `helm-validate` / `k8s-validate` block a PR that renders a schema-invalid manifest.
- [ ] `versions.hcl` and `.tool-versions` agree, and CI uses those exact versions.

---

## 9. Dependencies on other specs

- **SPEC-00 — Overview:** global placeholders (`{{VCS_ORG}}`, `{{PRIMARY_REGION}}`,
  `{{PROD_ACCOUNT_ID}}`, `{{DOMAIN}}`) and the estate map.
- **SPEC-01 — Foundation / IaC:** the modules, `root.hcl`, remote state backend (`ADR-0002`), and
  `versions.hcl` these gates inspect; the local verification loop this spec wires into CI.
- **SPEC-04 — GitOps Delivery:** ArgoCD (`ADR-0006`), Kargo promotion (`ADR-0021`), the
  `{{ARGOCD_CONFIG_REPO}}` that `reusable-deploy-via-argocd` PRs into, and Argo Rollouts canary
  (`ADR-0014`) that consumes signed images.
- **SPEC-05 — Security (identity, org-guardrails, cluster policy, supply chain):** the OIDC provider
  + IAM roles behind every `vars.*_ROLE_ARN` and the SCP/RCP modules (`ADR-0017`) that
  `policy-access-check` guards; the runtime Kyverno/VAP admission layer (`ADR-0020`) that must
  *verify* the cosign signatures this pipeline produces and the tag/label taxonomy (`ADR-0028`) the
  OPA policies enforce; and the deeper supply-chain hardening — `ADR-0016` (tier-1) and `ADR-0022`
  (runtime: harden-runner, zizmor, SHA-pinning).
- **SPEC-10 — ML Platform:** Airflow/MLflow/Kargo topology and the eval-debate gate (`ADR-0037`,
  `ADR-0038`, `ADR-0048`) that `ml-pipeline*` orchestrates.
- **Cost — no dedicated spec.** The Infracost PR gate (§4.7) is the canonical cost-control home in
  this estate; it complements runtime OpenCost/CUR (`ADR-0027`), which lives with the cluster
  platform, not in a standalone cost spec.
