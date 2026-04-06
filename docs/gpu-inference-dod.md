# GPU Inference Cluster — Definition of Done

Acceptance criteria for the `gpu-inference` cluster. All criteria must pass before the cluster is
considered production-ready. Automated validation is run weekly by the `gpu-inference-validation`
CronJob; results are available in the `gpu-inference-validation` namespace.

---

## 1. Network

| Criterion | Threshold | Test |
|-----------|-----------|------|
| Host-to-host UDP latency (p99, within placement group) | < 50 μs | `network-latency-test.yaml` — sockperf ping-pong |
| TCP throughput between GPU nodes (placement group) | > 100 Gbps | `network-latency-test.yaml` — iperf3 -P 8 |
| WireGuard encryption overhead vs plaintext baseline | < 10 μs additional latency | `security-audit.yaml` + manual comparison |
| Cilium WireGuard (`cilium_wg0`) interface on every GPU node | Present on 100% of nodes | `security-audit.yaml` |
| No unencrypted node-to-node traffic | 0 plaintext flows | `security-audit.yaml` — Cilium status |

**Rationale**: NCCL collective operations are latency-sensitive. Host-to-host latency above 50 μs
degrades all-reduce bandwidth and stalls GPU pipelines. WireGuard overhead must remain below 10 μs
to justify transparent encryption at this scale.

---

## 2. GPU Performance (NCCL)

| Criterion | Threshold | Test |
|-----------|-----------|------|
| GPU utilization during NCCL all-reduce (avg over run) | > 85% | `nccl-benchmark.yaml` — nvidia-smi dmon |
| NCCL inter-node algorithmic bandwidth (p5.48xlarge NVSwitch) | > 400 GB/s | `nccl-benchmark.yaml` — all_reduce_perf |
| All-reduce latency for 1 GB message | < 50 ms | `nccl-benchmark.yaml` — timing output |
| NCCL correctness check | 0 errors | `nccl-benchmark.yaml` — `--check 1` |

**Rationale**: p5.48xlarge nodes expose 8x H100 SXM5 GPUs connected via NVSwitch (3.2 TB/s
aggregate). 400 GB/s inter-node sets a conservative floor for multi-node all-reduce at 8-GPU
granularity. GPU utilization below 85% indicates memory bottlenecks or driver/NCCL misconfiguration.

---

## 3. Scheduling

### 3a. Volcano Gang Scheduling

| Criterion | Threshold | Test |
|-----------|-----------|------|
| Gang recovery time after single pod failure | < 30 seconds | `gang-recovery-test.yaml` |
| Initial gang scheduling time (8 replicas → Running) | < 60 seconds | `gang-recovery-test.yaml` |
| Volcano respects `minAvailable` (gang semantics) | All-or-nothing placement | `gang-recovery-test.yaml` — policy: RestartJob |

### 3b. DRA (Dynamic Resource Allocation)

| Criterion | Threshold | Test |
|-----------|-----------|------|
| Time to schedule 100 DRA-backed pods | < 5 seconds | `dra-scheduling-test.yaml` |
| ResourceClaim allocation success rate | 100% of requested claims | `dra-scheduling-test.yaml` |
| DRA scheduling failures | 0 | `dra-scheduling-test.yaml` |

### 3c. Kubernetes API

| Criterion | Threshold | Notes |
|-----------|-----------|-------|
| API server response time at 100k pods | < 200 ms (p99) | Measured by monitoring — not automated test |
| kube-scheduler throughput | > 100 pods/s | kube-scheduler metrics via VictoriaMetrics |

**Rationale**: Gang scheduling is mandatory for distributed inference — partial pod placement wastes
GPUs and blocks other jobs. DRA enables fine-grained GPU device sharing for MIG and time-slicing;
5-second scheduling for 100 pods ensures new inference replicas come online within one autoscale cycle.

---

## 4. Inference Performance (vLLM)

| Criterion | Threshold | Test |
|-----------|-----------|------|
| Throughput per GPU | > 1000 tokens/sec/GPU | `vllm-inference-benchmark.yaml` |
| Time To First Token (TTFT) — p50 | < 100 ms | `vllm-inference-benchmark.yaml` |
| End-to-end latency for 512-token output — p99 | < 500 ms | `vllm-inference-benchmark.yaml` |
| GPU HBM memory utilization during inference | < 90% | `vllm-inference-benchmark.yaml` + DCGM |
| Server error rate during benchmark | < 0.1% | `vllm-inference-benchmark.yaml` |

**Test configuration**: Llama-3-8B-Instruct, 32 concurrent requests, 512 input / 512 output tokens,
200 prompts, OpenAI-compatible chat endpoint.

**Rationale**: 1000 tokens/sec/GPU at 100 ms TTFT meets interactive inference SLAs for chat and
code-generation use cases. p99 < 500 ms keeps tail latency acceptable under 32-way concurrency.

---

## 5. Observability

| Criterion | Threshold | Test |
|-----------|-----------|------|
| VictoriaMetrics health endpoint reachable | HTTP 200 | `observability-check.yaml` |
| DCGM GPU metrics present for all GPU nodes | All 7 DCGM metric families, 0 gaps | `observability-check.yaml` |
| `DCGM_FI_DEV_GPU_UTIL` time series count | = number of GPU nodes × 8 | `observability-check.yaml` |
| `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` present | Yes | `observability-check.yaml` |
| Kubernetes cluster metrics present (kube-state-metrics) | `kube_node_status_condition` > 0 series | `observability-check.yaml` |
| Volcano queue metrics present | `volcano_queue_allocated_gpu` > 0 series | `observability-check.yaml` |
| ClickHouse log table receiving rows | > 0 rows in last 5 minutes | `observability-check.yaml` |
| vmalert alert rules loaded | > 0 rules | `observability-check.yaml` |
| Alerting: GPU utilization > 95% alert fires | Alert present in rules | Manual verification |
| Alerting: NCCL bandwidth drop > 20% alert fires | Alert present in rules | Manual verification |

**Rationale**: Observability gaps in GPU clusters are dangerous — a silent DCGM exporter failure
masks GPU health issues that cause silent training divergence. ClickHouse structured logs enable
post-mortem analysis of scheduling and inference events.

---

## 6. Security

| Criterion | Threshold | Test |
|-----------|-----------|------|
| WireGuard transparent encryption active on all nodes | 100% of Cilium agents report WireGuard enabled | `security-audit.yaml` |
| `cilium_wg0` WireGuard interface present on all nodes | 100% of nodes | `security-audit.yaml` |
| Privileged containers outside approved namespaces | 0 | `security-audit.yaml` |
| `hostNetwork: true` pods outside approved namespaces | 0 | `security-audit.yaml` |
| NetworkPolicy or CiliumNetworkPolicy baseline | ≥ 1 policy in cluster | `security-audit.yaml` |
| `allowPrivilegeEscalation: true` in user namespaces | 0 (warn only for GPU operator) | `security-audit.yaml` |
| No hardcoded secrets in manifests | 0 (enforced by gitleaks pre-commit hook) | CI/CD gate |
| IRSA enabled — no static AWS credentials on nodes | Verified via EKS configuration | Terraform plan output |

**Approved namespaces for privileged containers**: `kube-system`, `monitoring`, `falco`, `gpu-operator`

**Rationale**: WireGuard transparent encryption is mandatory for GDPR/SOC2 data-in-transit
compliance. The 10 μs overhead budget preserves NCCL performance while ensuring all inter-node
traffic is encrypted, including model weight transfers and RDMA-like collective operations.

---

## 7. Validation Automation

The validation suite is managed by:

- **Terraform module**: `terraform/modules/gpu-inference-validation/`
- **Catalog unit**: `catalog/units/gpu-inference-validation/terragrunt.hcl`
- **Stack entry**: `terragrunt/prod/eu-west-1/gpu-inference/terragrunt.stack.hcl`
- **CronJob schedule**: `0 2 * * 0` (Sunday 02:00 UTC)
- **Namespace**: `gpu-inference-validation`

### Running the suite manually

```bash
# Trigger an immediate run
kubectl create job --from=cronjob/gpu-inference-validation-suite \
  gpu-inference-validation-manual-$(date +%s) \
  -n gpu-inference-validation

# Watch progress
kubectl logs -n gpu-inference-validation \
  -l app.kubernetes.io/name=gpu-inference-validation-suite \
  --follow

# Check last run result
kubectl get jobs -n gpu-inference-validation \
  -l app.kubernetes.io/name=gpu-inference-validation-suite \
  --sort-by=.metadata.creationTimestamp
```

### Running individual tests

```bash
# Run only the vLLM benchmark
kubectl apply -f tests/gpu-inference/vllm-inference-benchmark.yaml

# Run only the security audit
kubectl apply -f tests/gpu-inference/security-audit.yaml

# Watch job
kubectl logs -n gpu-inference-validation \
  -l app.kubernetes.io/name=vllm-inference-benchmark \
  --follow
```

---

## 8. Pass/Fail Summary Matrix

| Area | Test File | Auto | Critical |
|------|-----------|------|---------|
| Network latency & bandwidth | `network-latency-test.yaml` | Yes | Yes |
| NCCL all-reduce bandwidth & GPU util | `nccl-benchmark.yaml` | Yes | Yes |
| Gang scheduling recovery | `gang-recovery-test.yaml` | Yes | Yes |
| DRA scheduling latency | `dra-scheduling-test.yaml` | Yes | Yes |
| Observability completeness | `observability-check.yaml` | Yes | Yes |
| Security & encryption | `security-audit.yaml` | Yes | Yes |
| vLLM inference performance | `vllm-inference-benchmark.yaml` | Yes | Yes |
| API server latency at 100k pods | VictoriaMetrics dashboard | No | Yes |
| Alert rule coverage | Manual review | No | Yes |

All **Critical** criteria must pass before a release is promoted from staging to production.
