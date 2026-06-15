# Golden Path: AWS ML -- New Team Dashboard

> **Platform:** AWS EKS GPU ML cluster (ADR-0044 / ADR-0048)
> **ADR gates:** ADR-0041 (template approach)
> **GCP etalon:** `templates/golden-paths/new-dashboard/` (GCP/GKE variant)
>
> WS-D (grafana-self-serve) is **cluster-agnostic** -- the chart, values
> structure, and ArgoCD wave are identical to the GCP etalon. The only
> AWS-specific addition is the ADR-0028 annotation documenting the Pod
> Identity roles in use and the references pointing to ADR-0048.

This template onboards a new team into the WS-D (ADR-0039) self-serve
observability layer: one Grafana folder + starter dashboard + PrometheusRule
alert groups, delivered in a single PR.

Backstage scaffolder mapping: `spec.type: team-dashboard`
(see "Backstage future mapping" below; ADR-0034 remains deferred).

Chart: `apps/infra/grafana-self-serve/`
Chart versions verified against WS-D chart as of 2026-06-15.

---

## When to use this template

Use this golden path when:

- A team is new to the **AWS ML platform** and needs a scoped Grafana folder
- The team is non-ML (no drift monitoring needed) -- for ML + drift panels use
  `aws-ml-new-model-service` (`templates/golden-paths/aws-ml-new-model-service/`)
- You want to start from the standard RED + saturation + alerts dashboard on EKS

For teams with ML models already deployed, enable `ml.enabled: true` and fill in
`ml.modelName` + `ml.tenant` in the values file.

---

## Prerequisites

- [ ] Namespace `{{TEAM_NAMESPACE}}` exists on the `aws-eks-gpu-*` ML cluster
- [ ] Grafana service account `grafana-sa-{{TEAM_SLUG}}` exists in Grafana
  (create via Grafana UI or API before ArgoCD sync)
- [ ] CI service account `{{TEAM_SLUG}}-ci` exists in namespace `{{TEAM_NAMESPACE}}`
  (for PrometheusRule RBAC; omit `ciServiceAccount` if not needed)

---

## Step 1 -- Substitute placeholders

```bash
# Team identity
export TEAM_NAME="Checkout"           # human-readable
export TEAM_SLUG="team-checkout"      # lower-kebab
export TEAM_NAMESPACE="checkout"      # Kubernetes namespace on the EKS ML cluster
export TEAM_SYSTEM="checkout"         # ADR-0028 platform:system value
export TEAM_OWNER="team-checkout"     # ADR-0028 platform:owner value
export PLATFORM_ENV="production"      # production | staging | dev | sandbox

# AWS-specific (for the ArgoCD annotation documenting Pod Identity roles)
export AWS_ACCOUNT_ID="123456789012"

mkdir -p out
for f in values.yaml argocd-application.yaml; do
  envsubst < "$f" > "out/${f}"
done

# Verify no raw {{}} remain
grep -r '{{' out/ && echo "UNSUBSTITUTED PLACEHOLDERS FOUND" || echo "OK"
```

---

## Step 2 -- Commit the files

Place the substituted files in the PR at:

```
apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/values.yaml
apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/argocd-application.yaml
```

---

## Step 3 -- Validate

```bash
yamllint -c .yamllint.yml out/values.yaml out/argocd-application.yaml

helm template apps/infra/grafana-self-serve \
  -f apps/infra/grafana-self-serve/values.yaml \
  -f out/values.yaml
```

The render should produce:

- A ConfigMap with `grafana_dashboard: "1"` label (Grafana folder provisioning)
- A ConfigMap with `grafana_folder` annotation (starter dashboard)
- A PrometheusRule with availability and saturation alert groups
- A Role + RoleBinding for CI service account PrometheusRule management

---

## Step 4 -- Open the PR

PR checklist:

- [ ] All `{{PLACEHOLDER}}` substituted; no raw template strings remain
- [ ] `yamllint -c .yamllint.yml` passes
- [ ] `helm template` renders without error
- [ ] ADR-0028 labels present: `platform:system`, `platform:owner`, `platform:env`,
      `platform:component`, `platform:managed-by`
- [ ] Grafana SA `grafana-sa-{{TEAM_SLUG}}` created before the PR is merged
- [ ] Platform review obtained (see `docs/golden-paths/aws-ml-RACI-and-handoffs.md`)

---

## What you get after merge

- Grafana folder `team-{{TEAM_SLUG}}` visible only to your team service account
- A starter dashboard with RED panels, resource saturation, and an alerts table
- PrometheusRule alert groups in namespace `{{TEAM_NAMESPACE}}`
- RBAC Role + RoleBinding for CI PrometheusRule management

For ML panels, set `ml.enabled: true` and fill in `ml.modelName` + `ml.tenant`
(see `apps/infra/grafana-self-serve/values.yaml` for all ML options, and
`templates/golden-paths/aws-ml-new-model-service/` for the full ML onboarding path).

---

## AWS note: PromQL selectors

The Grafana dashboards use PromQL selectors based on Kubernetes labels and job/pod
metadata -- not cloud-provider-specific labels. The RED metrics, saturation queries,
and ML drift/accuracy queries are **identical** to the GCP etalon. No dashboard
changes are needed when moving from GCP to AWS.

---

## Platform support

- ADR-0039 (WS-D): grafana-self-serve architecture
- ADR-0041 (WS-F): this template (golden-path structure)
- ADR-0028: platform taxonomy tags and labels

---

## Backstage future mapping

```yaml
# catalog-info.yaml (future -- do not deploy before ADR-0034 revisit)
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: aws-ml-new-dashboard
spec:
  type: team-dashboard
  parameters:
    - title: Team identity
      properties:
        teamName:    # -> {{TEAM_NAME}}
        teamSlug:    # -> {{TEAM_SLUG}}
        namespace:   # -> {{TEAM_NAMESPACE}}
        system:      # -> {{TEAM_SYSTEM}}
        teamOwner:   # -> {{TEAM_OWNER}}
        platformEnv: # -> {{PLATFORM_ENV}}
    - title: AWS identity
      properties:
        awsAccountId:  # -> {{AWS_ACCOUNT_ID}}
  steps:
    - id: fetch-template
      action: fetch:template
      input:
        url: ./templates/golden-paths/aws-ml-new-dashboard
    - id: publish
      action: publish:github:pull-request
    - id: register
      action: catalog:register
```
