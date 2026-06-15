# Golden Path: New Tenant (Bare-Metal / Talos)

**Substrate:** Owned bare-metal GPU cluster on Talos Linux, two UK DCs.
See `docs/transaction-analytics/06-uk-datacenters.md`.

**ADRs cited:**
- ADR-0049 -- Talos foundation, immutability, multi-DC (namespace-per-tenant model)
- ADR-0052 -- Rook-Ceph / MinIO (per-tenant S3 bucket + scoped credential)
- ADR-0041 -- Golden paths and collaboration (this document)
- ADR-0028 -- Platform taxonomy labels (mandatory on every resource)
- ADR-0040 -- SOC posture: Gatekeeper tenant constraints, Vault per-tenant KMS key

**This golden path is unique to the bare-metal platform.** No GCP or AWS
equivalent exists because the full bare-metal tenant bundle (Vault KMS key, MinIO
bucket, Gatekeeper constraints, Kafka ACLs) requires explicit provisioning in the
UK DC model.

---

## What this golden path provisions

A single PR via this golden path triggers `charts/tenant-bootstrap/` to create
the full tenant bundle described in `06-uk-datacenters.md`:

| Resource | Provisioned by |
|----------|---------------|
| Kubernetes namespace `tenant-{{TENANT_ID}}` | `charts/tenant-bootstrap/` |
| `NetworkPolicy` default-deny + explicit allows | `charts/tenant-bootstrap/` |
| `ResourceQuota` + `LimitRange` per contract tier | `charts/tenant-bootstrap/` |
| Gatekeeper constraints (reject pods without `tenant={{TENANT_ID}}`) | `charts/tenant-bootstrap/` |
| Kafka ACLs scoped to `tenant-{{TENANT_ID}}.*` topics | `charts/tenant-bootstrap/` |
| QuestDB database with dedicated role | `charts/tenant-bootstrap/` |
| Iceberg namespace `tenant_{{TENANT_ID}}.*` + REST catalog perms | `charts/tenant-bootstrap/` |
| Qdrant collection with scoped API key | `charts/tenant-bootstrap/` |
| Postgres schema `tenant_{{TENANT_ID}}.*` with dedicated role | `charts/tenant-bootstrap/` |
| Argilla workspace with tenant-scoped membership | `charts/tenant-bootstrap/` |
| **Vault per-tenant KMS key** (UK-resident data, ADR-0040) | `charts/tenant-bootstrap/` |
| MinIO bucket `ml-artifacts-{{TENANT_ID}}` + S3 credential (ESO) | `terraform/modules/baremetal-ml-artifact-store` (WS-B) |
| Service-account OIDC issuer claim | `charts/tenant-bootstrap/` |
| ADR-0028 labels on all resources | `charts/tenant-bootstrap/` + this template |

After this golden path completes, all other BM golden paths
(`bm-new-model-service`, `bm-new-ml-pipeline`, `bm-new-dashboard`) can be used
for this tenant.

---

## Prerequisites

- [ ] `charts/tenant-bootstrap/` exists in the repo
- [ ] Vault (in-DC) is running and reachable from the bare-metal cluster
- [ ] You have the `platform-admin` ClusterRole to install Helm charts
- [ ] Tenant metadata (contract tier, Kafka topics, Iceberg prefixes) is in the
  platform Postgres tenant registry

---

## Step 1 -- Substitute placeholders

```bash
export TENANT_ID="acme"                # short identifier (namespace: tenant-acme)
export TENANT="tenant-acme"           # full Kubernetes namespace
export TENANT_DISPLAY_NAME="Acme Corp" # human-readable
export TEAM_OWNER="team-acme"         # ADR-0028 platform.owner
export PLATFORM_ENV="production"       # production | staging | dev | sandbox
# Contract tier controls ResourceQuota/LimitRange.
# Values: starter (dev/small) | standard (prod default) | gpu (GPU workload)
export CONTRACT_TIER="standard"
# GPU queue access (comma-separated; empty for CPU-only tenants).
# Must match UK DC Volcano queue taxonomy (06-uk-datacenters.md).
export GPU_QUEUES="training-default,training-bootstrap"
export MINIO_BUCKET="ml-artifacts-${TENANT_ID}"

mkdir -p out
for f in argocd-application.yaml helm-values.yaml; do
  envsubst < "$f" > "out/${f}"
done

# Verify no raw {{}} remain
grep -r '{{' out/ && echo "UNSUBSTITUTED PLACEHOLDERS FOUND" || echo "OK"
```

---

## Step 2 -- Install charts/tenant-bootstrap/

**CRITICAL DECISION** (per `.claude/rules/critical-decisions.md`): this step
creates a Vault KMS key, Kafka ACLs, and a production Kubernetes namespace.
It MUST be approved by a platform lead before execution.

```bash
# First install (manual, apply-gated -- human approval required):
helm upgrade --install "tenant-${TENANT_ID}" charts/tenant-bootstrap/ \
  --namespace argocd \
  --values out/helm-values.yaml \
  --atomic --timeout 10m

# Verify namespace exists with ADR-0028 labels:
kubectl get namespace "${TENANT}" -o jsonpath='{.metadata.labels}' | jq .
# Verify Gatekeeper constraints are active:
kubectl get constraints -o wide | grep "${TENANT_ID}"
```

---

## Step 3 -- Commit the ArgoCD Application (for GitOps updates)

After the first install, commit `out/argocd-application.yaml` at:
```
apps/infra/tenants/{{TENANT_ID}}/argocd-application.yaml
```

Future changes (quota adjustments, queue permission changes) are made via PR to
`helm-values.yaml` and picked up by ArgoCD.

---

## Step 4 -- Verify ADR-0028 labels

All resources provisioned by `charts/tenant-bootstrap/` must carry the platform
taxonomy labels. The BM OPA profile (`tests/opa/platform_tags_baremetal.rego`)
checks `kubernetes_manifest` resources at plan time:

```yaml
metadata:
  labels:
    platform.system: "tenant-bootstrap"
    platform.component: "namespace"
    platform.env: "{{PLATFORM_ENV}}"
    platform.owner: "{{TEAM_OWNER}}"
    platform.managed-by: "helm"
    tenant: "{{TENANT_ID}}"
```

---

## Step 5 -- Smoke tests

```bash
# Namespace exists with correct labels:
kubectl get namespace "${TENANT}" -o jsonpath='{.metadata.labels}' | jq .

# NetworkPolicy default-deny is in place:
kubectl get networkpolicy -n "${TENANT}" | grep default-deny

# Gatekeeper rejects pods without tenant label:
kubectl run test-pod --image=busybox -n "${TENANT}" --restart=Never
# Expected: admission webhook denied (missing tenant={{TENANT_ID}} label)

# Vault KMS key accessible from the tenant namespace via ESO:
kubectl get externalsecret -n "${TENANT}" | grep kms
```

---

## Volcano queue access

If `GPU_QUEUES` is set, `charts/tenant-bootstrap/` creates a Volcano `Queue`
object and a `ClusterRole` allowing the tenant to submit `VolcanoJob` objects
to those queues.

UK DC queue taxonomy (`06-uk-datacenters.md`, ADR-0054):

| Queue | Pool | Weight | Cap | Use case |
|-------|------|--------|-----|----------|
| `training-default` | H100 | 100 | - | Regular tenant retrains |
| `training-bootstrap` | H100 | 30 | - | New-tenant initial fine-tunes |
| `training-urgent` | H100 | 200 | 2 jobs | Drift/incident response |
| `serving-vllm` | H200 | 150 | - | vLLM multi-LoRA batch |
| `eval-judge` | H200 | 200 | - | LLM-as-judge debate |
| `engine-build` | H200 | 80 | - | TRT-LLM compilation |
| `batch-rescore` | H200 | 50 | - | Historical reprocessing |

---

## References

- `docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md` (namespace-per-tenant)
- `docs/adrs/0052-baremetal-storage-rook-ceph.md` (MinIO per-tenant bucket)
- `docs/adrs/0040-soc-posture-and-oncall.md` (Vault KMS, Gatekeeper)
- `docs/adrs/0041-golden-paths-collaboration.md` (WS-F)
- `docs/transaction-analytics/06-uk-datacenters.md` (tenant-bootstrap design fiction)
- `charts/tenant-bootstrap/` (Helm chart provisioning the tenant bundle)
- `terraform/modules/baremetal-ml-artifact-store` (WS-B -- MinIO bucket + ESO)
- `docs/golden-paths/bm-RACI-and-handoffs.md` (RACI and handoff protocol)
- `.claude/rules/critical-decisions.md` (approval gates)
