# Runbook: ML-Platform Incident Response — Bare-Metal (Talos UK DC)

> **Scope (WS-E):** ML-specific incidents on the **owned bare-metal Talos GPU cluster**
> in the UK DCs — model drift, **training-queue starvation** (Volcano fair-share),
> GPU/NCCL fabric degradation, and the control-plane-owned failure modes the managed-K8s
> ML runbook never had (etcd quorum, KubePrism). This **extends** the cloud
> [ML-incident runbook](ml-incident-runbook.md) and
> [on-call rotation & escalation](oncall-rotation-escalation.md); follow those for
> generic triage, PagerDuty ACK, and comms. Here we cover only the bare-metal ML
> decision trees.
>
> **System / owner (ADR-0028):** `platform.system = ml-monitoring` / `ml-pipeline`;
> `platform.owner = team-ml-platform`, co-owned with `team-sec` for the posture plane.
> All alerts carry `platform_system` and route on the Grafana `$system` axis.
>
> **Substrate references (not re-authored here):**
> [`ai-sre/knowledge/gpu-driver-updates.md`](../../ai-sre/knowledge/gpu-driver-updates.md),
> [`nccl-troubleshooting.md`](../../ai-sre/knowledge/nccl-troubleshooting.md),
> [`cilium-bgp-issues.md`](../../ai-sre/knowledge/cilium-bgp-issues.md), and the
> [DC-failover runbook](uk-dc-failover-baremetal.md). SOC2 evidence: CC7.3 / CC7.4 in
> the [bare-metal SOC2 matrix](../compliance/soc2-control-matrix-baremetal.md).
>
> **ADRs:** ADR-0040 (on-call, reused), ADR-0049 (foundation), ADR-0050 (immutable-OS),
> ADR-0053 (GPU fabric), ADR-0054 (elasticity / fixed pools).

## Severity definitions (bare-metal ML)

| Severity | Definition | PagerDuty | ACK SLA |
|---|---|---|---|
| **SEV1** | Production serving down on the DC; or GPU fabric collapse halting all training; or etcd quorum loss | Page ML + platform on-call immediately | 5 min |
| **SEV2** | Drift/accuracy breach on a prod model; or `training-default` queue starved > 1 h blocking a scheduled retrain | Page ML on-call | 15 min |
| **SEV3** | Drift warning trend; single GPU XID-tainted with capacity headroom; BGP session flap with VIP still reachable | Notify Slack `#ml-incidents` | 1 h |

---

## Scenario 1 — Model drift / accuracy regression

Identical decision tree to the [cloud runbook Scenario 1](ml-incident-runbook.md)
(Evidently/whylogs, ADR-0038, reused unchanged) **except the retrain trigger lands on
the in-DC Airflow**, not a cloud-hosted one (ADR-0049 isolation). The retrain webhook
posts to the **in-DC Airflow REST** `POST /api/v1/dags/train_domain_adapter/dagRuns`.

**Bare-metal-specific check:** confirm the retrain job can actually be *scheduled* —
on fixed GPU pools a retrain competes for the same H100s as production training. Check
the Volcano queue before assuming the retrain is stuck on data (see Scenario 2).

---

## Scenario 2 — Training-queue starvation (Volcano fair-share)

**Symptoms / alerts:** `VolcanoQueuePending`, `MLTrainJobStarved`, a scheduled retrain
DAG run stuck in `Pending`; `training-default` jobs not admitted.

> This failure mode **does not exist on a cloud autoscaler** — there, a pending job
> triggers a node scale-up. On bare metal capacity is **fixed** (ADR-0054), so a
> starved queue is a *fair-share* / *prioritization* problem, not a capacity-add one.

### Triage

1. **Acknowledge** in PagerDuty.
2. **Inspect the Volcano queues** (taxonomy from `06-uk-datacenters.md`):
   ```bash
   # Which queue is starved, and who holds the GPUs?
   kubectl get queues.scheduling.volcano.sh -o wide
   kubectl get podgroups -A \
     -l platform.system=ml-pipeline \
     -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,QUEUE:.spec.queue
   ```
3. **Find the GPU holder** — a long-running `training-bootstrap` or a runaway
   `eval-judge` job can monopolize the H100 pool.

### Decision tree

| Finding | Action |
|---|---|
| A **bootstrap/eval job overran** its expected runtime | Confirm with the owning team; if abandoned, `kubectl delete podgroup` to free GPUs. Record in postmortem; consider a Volcano `maxAllocated` cap on that queue. |
| Genuine **contention** — all GPUs busy with legitimate prod training | Escalate to capacity decision: (a) let the retrain wait, (b) preempt a lower-priority `batch-rescore` job (Volcano preemption), or (c) pin the retrain to the standby DC's headroom (~40%, UK doc). **Never** migrate a gang-scheduled in-flight job (ADR-0054 — re-queue, don't relocate). |
| **`training-urgent` needed** for an incident retrain | Submit to `training-urgent` (cap 2 — reserved for incidents); it preempts. Document the preemption. |
| Queue weights themselves are wrong | Tune the queue `weight` in `baremetal-gpu-scheduling` via PR (apply-gated); do not hand-edit live queues without a change record (SOC2 CC8.1). |

### Free a starved queue safely

```bash
# Preempt a reclaimable batch job to admit an urgent retrain (Volcano honours
# queue weights + reclaimable=true). Confirm the batch job is checkpoint-safe first.
kubectl label podgroup -n batch <pg-name> volcano.sh/preemptable=true --overwrite
```

---

## Scenario 3 — GPU / NCCL fabric degradation

**Symptoms / alerts:** `DCGMXidError`, `NCCLAllReduceBelowFloor`, `NVLinkError`,
training throughput collapse, collectives silently falling back to TCP.

### Triage

1. **Acknowledge**; classify single-GPU vs fabric-wide.
2. **DCGM first** (the auto-taint CronJob from `baremetal-gpu-dcgm` may have already
   tainted a node on an XID burst):
   ```bash
   kubectl get nodes -l nvidia.com/gpu.present=true \
     -o custom-columns=NODE:.metadata.name,TAINTS:.spec.taints
   ```
3. **NCCL / fabric** — follow
   [`nccl-troubleshooting.md`](../../ai-sre/knowledge/nccl-troubleshooting.md): check
   the all-reduce bandwidth test (the ADR-0053 acceptance gate), jumbo-frame MTU 9000,
   and RoCE/IB topology.

### Decision tree

| Finding | Action |
|---|---|
| Single GPU **XID-tainted**, pool has headroom | Let the auto-taint hold; jobs reschedule onto healthy GPUs. Open a hardware ticket; follow `gpu-driver-updates.md` if driver-related. |
| **Fabric-wide** NCCL collapse (all-reduce below floor) | SEV1. Likely RoCE/IB misconfig or a ToR/subnet-manager fault. Pause new training admissions (Volcano), engage network on-call, run the NCCL pre-flight. Do **not** let jobs limp on a TCP fallback — fail fast. |
| Driver/extension skew after a Talos upgrade (risk R2) | Roll back the Talos A/B partition (auto-rollback should have fired); stage the fix on the **standby DC first**. The driver is a **system extension** — there is no `apt` rollback; it is an image revert (ADR-0050). |
| **Cilium BGP flap** dropping a serving VIP | Follow [`cilium-bgp-issues.md`](../../ai-sre/knowledge/cilium-bgp-issues.md) (hold-timer 180 s, ToR max-prefix); MetalLB L2 is the documented fallback (ADR-0051). |

---

## Scenario 4 — Control-plane / etcd (self-operated — new vs managed K8s)

**Symptoms / alerts:** `EtcdQuorumLost`, `KubeAPIUnreachable`, control-plane node
NotReady. **Managed K8s hid this; on bare metal we own it (ADR-0049, risk R3).**

### Triage & decision tree

| Finding | Action |
|---|---|
| One control-plane node down, **quorum intact** | KubePrism keeps the in-cluster API serving (`assert_kubeprism_enabled`). Re-image the node via Cluster-API/Sidero (ADR-0054); do not panic-drain. |
| **Quorum lost** (≥2 of 3 CP nodes down) | SEV1. Restore from the **verified etcd snapshot** (taken before every CP change per plan §6). Follow the etcd restore procedure; if unrecoverable in-DC, fail over to the standby DC ([DC-failover runbook](uk-dc-failover-baremetal.md)). |
| About to change a control-plane `MachineConfig` | **Take + verify an etcd snapshot first** (plan §6 gate); check quorum before draining a CP node. This is the CC8.1 evidence. |

---

## Cross-references

- Drift mechanics + retrain-storm suppression: [cloud ML runbook](ml-incident-runbook.md)
  (reused — Evidently/whylogs are cluster-agnostic).
- On-call rotation / escalation / tabletop: [oncall-rotation-escalation.md](oncall-rotation-escalation.md).
- DC-level failover (lose the whole primary DC): [uk-dc-failover-baremetal.md](uk-dc-failover-baremetal.md)
  and the existing [uk-dc-failover.md](uk-dc-failover.md).
- SOC2 evidence anchor: CC7.3 / CC7.4 in
  [soc2-control-matrix-baremetal.md](../compliance/soc2-control-matrix-baremetal.md).
