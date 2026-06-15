# Bare-Metal Model API Contract Addendum

**Version:** 1.0.0
**Status:** Ratified -- supplement to `docs/contracts/model-api-contract.md` for bare-metal deployments.
**Scope:** UK DC bare-metal Talos GPU cluster (ADR-0049..0054).
**Owners:** ML Engineering (spec author), Backend (consumer), Platform/SRE (infra alignment).

This document is a **supplement** to `docs/contracts/model-api-contract.md`. It
does not change the base model request/response schema or the versioning policy.
It adds bare-metal-specific fields, constraints, and operational notes that apply
to models deployed on the UK DC bare-metal cluster.

All four personas must sign off on a bare-metal model's contract instance before
staging promotion, and this addendum must be referenced in the instance YAML (ss5).

---

## 1. Changes to the base contract

### 1.1 Artifact store endpoint

On GCP/AWS paths, artifact URIs use GCS (`gs://`) or external S3. On the
bare-metal path, artifact URIs use the **in-DC MinIO or Ceph-RGW S3 endpoint**
(`s3://`). External AWS S3 is NOT permitted for UK-resident training artifacts
(ADR-0052, UK data residency).

```yaml
# In the model contract instance YAML:
artifactStore:
  scheme: "s3"
  # In-DC endpoint only. Value must match the ESO ExternalSecret for the tenant.
  endpoint: "<in-DC MinIO or Ceph-RGW endpoint>"
  bucket: "ml-artifacts-<tenant-id>"
  # Credentials from Vault/ESO -- never hardcoded in the contract instance.
  credentialsRef: "minio-creds-<tenant-id>"
```

### 1.2 GPU queue field (new, bare-metal only)

Every model requiring GPU training or inference must declare the target Volcano
queue from the UK DC taxonomy (`06-uk-datacenters.md`, ADR-0054).

```yaml
# In the model contract instance YAML:
volcanoQueue:
  training: "training-default"    # or training-bootstrap | training-urgent
  inference: "serving-vllm"       # or eval-judge | engine-build | batch-rescore
```

Valid values:

| Queue | Pool | Weight | Cap | Use case |
|-------|------|--------|-----|----------|
| `training-default` | H100 | 100 | - | Regular tenant retrains |
| `training-bootstrap` | H100 | 30 | - | New-tenant initial fine-tunes |
| `training-urgent` | H100 | 200 | 2 jobs | Drift-triggered or incident-response |
| `serving-vllm` | H200 | 150 | - | vLLM multi-LoRA for internal/batch |
| `eval-judge` | H200 | 200 | - | LLM-as-judge debate |
| `engine-build` | H200 | 80 | - | TRT-LLM compilation jobs |
| `batch-rescore` | H200 | 50 | - | Reprocessing historical data |

**Constraint:** H100 queues are for training only; H200 queues are for inference only.
Enforced by Volcano scheduling and Talos node labels (ADR-0049/0050).

### 1.3 IB fabric requirements (new, bare-metal only)

Models using multi-node all-reduce (NCCL) must declare their InfiniBand bandwidth
floor. Used as the NCCL pre-flight acceptance gate (`ai-sre/knowledge/nccl-troubleshooting.md`).

```yaml
# In the model contract instance YAML:
gpuFabric:
  # Minimum NCCL all-reduce bandwidth (GB/s) acceptable for this model.
  # H100 NVSwitch + 400 Gbps IB target >= 300 GB/s; floor 200 GB/s.
  nccAllReduceMinBandwidthGbs: 200
  # Primary: infiniband. Fallback: roce. Baseline: tcp.
  fabricType: "infiniband"
```

### 1.4 Tenant KMS key requirement (new, bare-metal only)

All UK-resident artifacts encrypted at rest must reference the per-tenant Vault
KMS key (ADR-0040). The contract instance must confirm:

```yaml
# In the model contract instance YAML:
dataResidency:
  jurisdiction: "UK"
  kmsKeyRef: "tenants/<tenant-id>/kms"   # Vault path (provisioned by bm-new-tenant)
  externalS3Permitted: false             # training data must not leave the DC
```

---

## 2. SLO additions (bare-metal specific)

| SLO | Target | Rationale |
|-----|--------|-----------|
| **NCCL all-reduce bandwidth floor** | >= 200 GB/s (hard gate) | IB fabric health; training must not start below this floor |
| **GPU health auto-taint response** | < 5 min | DCGM XID burst triggers auto-taint; model must handle rescheduling gracefully |

These SLOs are monitored by `apps/infra/ml-monitoring/` (WS-C) and `baremetal-gpu-dcgm` (WS-A).

---

## 3. Observability alignment

Bare-metal WS-C drift metrics carry an additional label:
```
cluster_substrate="baremetal-uk"
```
PromQL queries for bare-metal models must include this label:

```promql
ml_model_accuracy{model_name="fraud-uk", cluster_substrate="baremetal-uk"} < 0.85
```

Grafana dashboards from the `bm-new-model-service` golden path pre-filter by
`cluster_substrate="baremetal-uk"`.

---

## 4. Drift monitoring alignment

```yaml
# In the model contract instance YAML:
driftMonitoring:
  # S3-compatible reference dataset path (in-DC -- NOT gs:// or external S3).
  referenceBucketUri: "s3://ml-artifacts-<tenant-id>/<model-name>/<tenant-id>/<domain>/reference.parquet"
  s3Endpoint: "<in-DC MinIO/Ceph-RGW endpoint>"
  s3CredentialsRef: "minio-creds-<tenant-id>"
```

---

## 5. Contract instance additions

When authoring a contract instance for a bare-metal model, add a top-level
`baremetal:` section alongside the base contract fields:

```yaml
# docs/contracts/<your-model>-bm-contract.yaml
# ... base contract fields (model_name, tenant, domain, etc.) ...
baremetal:
  addendumVersion: "1.0.0"
  artifactStore:
    scheme: "s3"
    endpoint: "<in-DC MinIO or Ceph-RGW endpoint>"
    bucket: "ml-artifacts-<tenant-id>"
    credentialsRef: "minio-creds-<tenant-id>"
  volcanoQueue:
    training: "training-default"
    inference: "serving-vllm"
  gpuFabric:
    nccAllReduceMinBandwidthGbs: 200
    fabricType: "infiniband"
  dataResidency:
    jurisdiction: "UK"
    kmsKeyRef: "tenants/<tenant-id>/kms"
    externalS3Permitted: false
  driftMonitoring:
    referenceBucketUri: "s3://ml-artifacts-<tenant-id>/<model-name>/<tenant-id>/<domain>/reference.parquet"
    s3Endpoint: "<in-DC MinIO/Ceph-RGW endpoint>"
    s3CredentialsRef: "minio-creds-<tenant-id>"
```

---

## 6. Sign-off requirements

All four personas sign off before bare-metal staging promotion:
- Data Engineering: reference dataset at `driftMonitoring.referenceBucketUri` is verified
- ML Engineering: `volcanoQueue.training` matches the model's GPU pool requirement
- Backend/Frontend: SLO targets (p50/p99/error rate + NCCL floor) are acceptable
- Platform/SRE: Vault KMS key at `dataResidency.kmsKeyRef` exists and is accessible

See `docs/golden-paths/bm-RACI-and-handoffs.md` Handoff H5 for the gate.

---

## 7. References

- `docs/contracts/model-api-contract.md` (base contract spec -- this is its BM addendum)
- `docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md` (WS-A)
- `docs/adrs/0052-baremetal-storage-rook-ceph.md` (artifact store substrate)
- `docs/adrs/0053-baremetal-gpu-fabric-roce-infiniband.md` (IB fabric SLO)
- `docs/adrs/0054-baremetal-elasticity-node-lifecycle.md` (Volcano queue discipline)
- `docs/adrs/0040-soc-posture-and-oncall.md` (Vault KMS, UK data residency)
- `docs/adrs/0041-golden-paths-collaboration.md` (WS-F)
- `docs/transaction-analytics/06-uk-datacenters.md` (UK DC queue taxonomy)
- `ai-sre/knowledge/nccl-troubleshooting.md` (NCCL all-reduce acceptance gate)
- `docs/golden-paths/bm-RACI-and-handoffs.md` (RACI and handoff protocol)
- `templates/golden-paths/bm-new-model-service/` (model service golden path)
