# baremetal-gpu-scheduling

**Volcano gang-scheduler + the UK queue taxonomy + DRA device classes** for the Talos GPU
cluster. Part of **WS-A** of the Bare-Metal ML Platform. System: `ml-infra`.

**ADRs:** [ADR-0049](../../../docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
(foundation; Volcano secondary scheduler). Folds the `gpu-inference-dra` shape. ADR-0028 labels.

## The UK queue taxonomy (verbatim from the design)

The default `volcano_queues` reproduce the **exact** taxonomy in
`docs/transaction-analytics/06-uk-datacenters.md`:

| Pool | Queue | Weight | Notes |
|------|-------|--------|-------|
| H100 | `training-default` | 100 | regular tenant retrains |
| H100 | `training-bootstrap` | 30 | new-tenant initial fine-tunes |
| H100 | `training-urgent` | 200 | **cap 2 jobs**, drift/incident response |
| H200 | `serving-vllm` | 150 | vLLM multi-LoRA |
| H200 | `eval-judge` | 200 | LLM-as-judge debate |
| H200 | `engine-build` | 80 | TRT-LLM compilation |
| H200 | `batch-rescore` | 50 | historical reprocessing |

## DRA device classes

`DeviceClass` + `ResourceClaimTemplate` for **H100 / H200 / L40S + fractional** GPU, so
Volcano schedules GPU as a DRA claim. Composes with the GPU-compute claim and (in
`baremetal-gpu-fabric`) the NIC claim — the one-DRA-model principle.

## What it creates (when `enabled = true`)

| Resource | Purpose |
|----------|---------|
| `kubernetes_namespace.scheduling` | Namespace, ADR-0028 labels |
| `helm_release.volcano` | Volcano controller + scheduler |
| `kubernetes_manifest.volcano_queue` (per queue) | The UK queue taxonomy |
| `kubernetes_manifest.dra_device_class` (per model) | DRA device classes |
| `kubernetes_manifest.dra_claim_template` (per model) | DRA claim templates |

## Apply-gated

`var.enabled` defaults **false**. Providers mocked at plan time — no live cluster, no Helm
install. No `terraform apply` in this repo.

## ADR-0028 labeling

Dotted keys: `platform.system = ml-infra`, `platform.component = scheduler`,
`platform.managed-by = terragrunt`, plus `platform_labels` overrides — on every queue/DRA
object (queues also carry `gpu.platform/pool`).

## Testing

```bash
terraform init -backend=false
terraform test
```
