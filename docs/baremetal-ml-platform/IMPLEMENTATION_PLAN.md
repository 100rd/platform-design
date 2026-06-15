# Bare-Metal ML Platform (Talos Linux) — Implementation Plan

> **Status:** PLAN (not executed). Planning-only — no `terraform apply`, no
> `talosctl apply-config`, no Cluster API reconcile, and no cluster/hardware
> mutation is implied by this document. Nothing here is ever deployed to real
> hardware: this is a MOCK/emulation repo, plan/validate-only, apply-gated.
> Execution happens later, per-workstream, via `/infra-team` under the project's
> ADR-first, PR-based, apply-gated workflow.
>
> **Grounding:** state mapped 2026-06-15 from the platform-design repo scan +
> the existing bare-metal product fiction. This plan is the **greenfield
> bare-metal mirror** of the GCP ML-platform plan
> (`docs/gcp-ml-platform/IMPLEMENTATION_PLAN.md`), section-for-section. The
> **etalon is the GCP GPU-on-GKE design** (ADR-0036 + ADR-0042 + WS-A..F as
> ADR-0037..0041); this plan re-derives the same six-workstream spine for an
> **owned, bare-metal, GPU Kubernetes cluster on Talos Linux** (immutable,
> API-driven), honouring and formalizing the Talos/Cluster-API/InfiniBand fiction
> already written in `docs/transaction-analytics/06-uk-datacenters.md` and
> `docs/runbooks/uk-dc-failover.md`.
>
> **ADR numbers:** this plan opens ADRs **0049–0054** (0043 is the highest
> existing; 0044–0048 are reserved for the AWS track). The GCP etalon ADRs
> 0036/0042/0037–0041 are the per-workstream references mirrored below.
>
> **The user explicitly chose Talos immutable.** The repo's
> `terraform/modules/hetzner-nodes` + `terraform/user_data/hetzner-kubeadm.sh`
> (a Hetzner-Cloud, cloud-init, **kubeadm** path) are **reference only and are
> NOT reused** — they are a mutable-host join model and the opposite of the
> immutable, declarative, no-SSH Talos posture this plan commits to.

---

## 1. Current state (what already exists)

Unlike the GCP etalon — where GPU-on-GKE was already running and the ML layer was
the gap — the bare-metal GPU **cluster does not exist as code**. What exists is
**detailed design-ahead fiction** (Talos chosen, topology specified, replication
specified) plus a **cloud-adjacent reference node module** that this plan
deliberately does not reuse. The greenfield build is therefore larger at the
foundation (WS-A) than the GCP mirror, and identical in the cluster-agnostic ML
layers (WS-B/C/D) once a cluster exists.

| Layer | Exists today | Where | Reuse stance |
|-------|--------------|-------|--------------|
| **Bare-metal DC design** | Two owned UK DCs (primary + standby); **Talos Linux** k8s layer; **Cluster API** lifecycle (`cluster-api-provider-metal3` / `-sidero` + Talos bootstrap/control-plane providers); Ansible below Talos; H100 training + H200 inference + CPU + storage pools; **InfiniBand 400 Gbps** + NVSwitch; **Volcano** queues; **MinIO** object pools; CloudNativePG; namespace-per-tenant | `docs/transaction-analytics/06-uk-datacenters.md` | **HONOR + formalize as IaC** (this is the etalon for WS-A) |
| **DC failover design** | primary-active + standby-hot-standby; `failover-controller` (Go, raft, anti-split-brain) + `dns-monitor`; RPO < 60 s / RTO < 15 min (planned) / < 30 min (unplanned); MirrorMaker2 / MinIO site-replication / CloudNativePG streaming | `docs/runbooks/uk-dc-failover.md`, `failover-controller/`, `dns-monitor/`, `dns-sync/` | **HONOR + reuse** (same failover machinery, no new one) |
| **GPU runtime knowledge** | GPU-driver-update checklist, NCCL troubleshooting (NVLink/NVSwitch/IB), Cilium BGP session diagnosis | `ai-sre/knowledge/{gpu-driver-updates,nccl-troubleshooting,cilium-bgp-issues}.md` | **HONOR** (runbook substrate for WS-A/E) |
| **Edge product** | Client-operated single-agent (Kafka-mediated, Cosign-signed OCI/raw, TRT-LLM, **no SSH from us**) — distinct from our cluster | `docs/transaction-analytics/05-edge-deployment.md` | **PRESERVE unchanged** (out of scope; not a cluster) |
| **Reference node module (NOT reused)** | `hetzner-nodes`: `hcloud` server + cloud-init + **kubeadm join** of an EKS cluster; mutable Ubuntu host, SSH keys | `terraform/modules/hetzner-nodes`, `terraform/user_data/hetzner-kubeadm.sh` | **REFERENCE ONLY — explicitly NOT reused** (mutable/kubeadm/SSH; antithetical to Talos immutable) |
| **GPU K8s day-2 patterns (other clouds)** | NVIDIA GPU Operator, DCGM exporter + auto-taint, DRA device classes, Volcano gang/queues, KEDA, vLLM, Cilium, Kata-CC — proven on EKS and mirrored to GKE | `terraform/modules/gpu-*`, `terraform/modules/gke-gpu-*`, `apps/infra/*` | **REUSE the shape** (Helm releases/queues/DRA semantics port to bare metal; the *substrate* differs) |
| **ML CI/CD + registry (other clouds)** | Airflow (`apps/infra/airflow`), MLflow (`apps/infra/mlflow`) + `ml-artifact-store`, `.github/workflows`, cosign/syft composites, Kargo promotion | `apps/infra/{airflow,mlflow}`, `catalog/units/ml-artifact-store`, `.github/actions/*`, `kargo/` | **REUSE cluster-agnostically** (re-point artifact store at MinIO/Ceph-RGW) |
| **ML observability (other clouds)** | `apps/infra/ml-monitoring` (Evidently/whylogs design), drift→Alertmanager→PagerDuty→Airflow-REST | `apps/infra/ml-monitoring`, ADR-0038 | **REUSE unchanged** (Prometheus-native; cluster-agnostic) |
| **System observability** | Prometheus 3.x/Thanos, Grafana, Loki, Tempo, Alertmanager→PagerDuty, OTel; VictoriaMetrics/DCGM for GPU; the UK doc already specifies `talos-log-shipper` → Loki and forwarded aggregates to AWS | `apps/infra/observability/*`, `docs/transaction-analytics/06-uk-datacenters.md` | **REUSE** (add Talos/node + IB/BGP + Ceph scrapes) |
| **Self-serve / golden paths** | Templated Grafana (`grafana-self-serve`), golden-path templates, Backstage **deferred** (ADR-0034) | `apps/infra/grafana-self-serve`, `templates/golden-paths/`, ADR-0034 | **REUSE** (same templates; bare-metal targets) |
| **Security posture** | Kyverno + VAP, Gatekeeper, Tetragon, cosign/syft, ESO, secret-rotation; the UK doc already specifies Gatekeeper tenant constraints + Vault KMS + per-venue mTLS | `terraform/modules/*`, `apps/infra/{kyverno,gatekeeper,tetragon}`, `docs/transaction-analytics/06-uk-datacenters.md` | **REUSE** (add Talos OS-level posture: immutable, no-SSH, mTLS API, KubePrism) |
| **Platform taxonomy** | Unified `platform:system` / `platform.system` taxonomy + ABAC + OPA enforcement | ADR-0028, `tests/opa/platform_tags.rego` | **MANDATORY** on every new resource |

**Headline:** the bare-metal *cluster foundation* (WS-A) is the **biggest
net-new build** here — the inverse of the GCP plan, where the foundation was
done and the ML layer was the gap. But the **ML-platform layers (WS-B CI/CD +
registry, WS-C drift, WS-D self-serve) are cluster-agnostic and reuse the
existing Airflow/MLflow/Evidently/Grafana artifacts almost verbatim**, with the
only substitution being the storage substrate (MinIO/Ceph-RGW for S3 instead of
GCS/S3). The hard, distinctive work is **immutable-OS GPU enablement** (driver as
a Talos system extension, not a host install), **bare-metal LB/fabric** (Cilium
BGP / MetalLB + RoCE/InfiniBand), **bare-metal storage** (Rook-Ceph/Mayastor),
and **node lifecycle without a cloud autoscaler** (Cluster-API/Metal³ vs static
pools).

## 2. Gap map (job-description scope → status)

| # | Responsibility | Status | Gap to close |
|---|----------------|--------|--------------|
| 1 | **Infra mgmt — elastic bare-metal + K8s for ML** | 🔴 design-only | Talos cluster is **fiction, not code**: no `talos-machineconfig`, no Cluster-API/Metal³ unit, no Cilium-LB/BGP, no GPU Operator via system extension, no DCGM/DRA/Volcano units, no Rook-Ceph. Elasticity story differs fundamentally — **no cloud autoscaler exists on bare metal** (fixed pools + provider-API node provisioning + scale-to-zero of *workloads*, not nodes) |
| 2 | **CI/CD for ML** (train/test/deploy) | 🔴 design-only | Same as GCP: no deployed orchestrator wired to *this* cluster, **no model registry on this cluster**, no train→eval→gate→register→deploy GH Actions targeting bare metal. Reuse cosign/syft + Airflow/MLflow; **re-point artifact store at MinIO/Ceph-RGW** |
| 3 | **Model monitoring** (drift/accuracy/latency/degradation) | 🔴 gap | No Evidently/whylogs running on this cluster; the Kargo edge already does score-distribution KL-divergence drift guarding (`05-edge-deployment.md`) but in-cluster ML drift monitoring is absent. Reuse ADR-0038 design unchanged |
| 4 | **Collaboration** (data/ML/backend/frontend) | 🟡 partial | Same as GCP: dashboards exist as templates; golden paths + shared contracts + IDP missing for bare-metal targets |
| 5 | **ML observability** (system + ML metrics, self-serve) | 🟡 split | System health design 🟢 strong (the UK doc already specifies the full scrape set + `talos-log-shipper`); **ML metrics (drift/accuracy/distribution) 🔴 absent**; per-team self-serve 🟡 partial (templates yes) |
| 6 | **SOC compliance + on-call** | 🟡 partial | On-call + DC-failover runbook 🟢 strong (`uk-dc-failover.md`, quarterly DR drill per SOC2 CC-series); **no SOC2 control-to-evidence matrix**; **Talos-specific posture not formalized** (immutable OS, no-SSH, mTLS machine API, KubePrism as controls); ML-incident runbooks thin |

**Headline:** bare metal inverts the GCP plan's weighting — **the foundation
(WS-A) is the real build**, the ML layer (WS-B/C) is a cluster-agnostic reuse,
and a thin **Talos-posture + SOC-evidence + self-serve** layer (WS-D/E/F) rounds
it out.

## 3. Constraints & conventions (apply to every workstream)

- **Plan/validate-only, apply-gated.** No `terraform apply`, no
  `talosctl apply-config` / `talosctl upgrade`, no Cluster-API reconcile, no Helm
  install without explicit human go + blast-radius review. `/infra-team` runs in
  plan mode; apply runs from CI on `main` after merge. **Nothing is ever applied
  to real hardware in this repo.**
- **ADR-first.** Each workstream opens with an ADR (decision + alternatives)
  before code — matches `docs/adrs/NNNN-*.md`. **This plan uses 0049–0054**
  (0043 is highest existing; 0044–0048 reserved for AWS).
- **ADR-0028 platform taxonomy (MANDATORY).** Every new resource (Terraform,
  Talos machine config, Helm, ArgoCD app) carries `platform:system` /
  `platform:component` / `platform:owner` / `platform:env` / `platform:managed-by`
  — the **AWS-tag form** is not applicable on bare metal, so the Terraform plane
  uses the underscore label keys (`platform_system`, …) on every taggable resource
  and Talos `machine.nodeLabels` / K8s labels carry the dotted form
  (`platform.system`, …). OPA `tests/opa/platform_tags.rego` enforces this at
  plan time — **NOTE:** that policy's `_exempt_types` and tag key are AWS-shaped,
  so WS-A's ADR-0049 calls out that the policy needs a bare-metal/`talos_*`
  profile. **Owner: WS-E** (security-expert) ships
  `tests/opa/platform_tags_baremetal.rego` as a named deliverable; tracked as §7
  decision #10 (a follow-up, not a blocker).
- **No managed control plane.** Unlike GKE/EKS, **we operate the Kubernetes
  control plane ourselves** (Talos control-plane nodes, etcd on the control
  plane, KubePrism for in-cluster API HA). This adds etcd backup/restore,
  control-plane upgrade, and quorum/blast-radius concerns that managed K8s hid.
- **No cloud autoscaler.** There is **no Karpenter / Cluster-Autoscaler / GKE
  node autoscaling** on owned hardware. Elasticity = **(a)** fixed-capacity GPU
  pools sized to steady state + standby headroom, **(b)** workload scale-to-zero
  (KEDA/HPA scale *pods*, Volcano queues gate *jobs*), and **(c)** node lifecycle
  via Cluster-API/Metal³ or provider-API re-imaging — provisioning a node is a
  re-image, minutes-to-hours, **not** seconds. This is the load-bearing
  difference from the etalon and is the subject of ADR-0054.
- **Immutable OS implications.** Talos has **no shell, no SSH, no package
  manager**; configuration is a declarative `MachineConfig` applied via the mTLS
  `talosctl`/machine API; changes are an A/B partition apply + reboot with
  auto-rollback. This **changes three stories vs managed K8s**: (1) the **GPU
  driver** is delivered as a **Talos system extension** baked into the boot image
  (`nonfree-kmod-nvidia` + `nvidia-container-toolkit`), never `apt install` on a
  running host (ADR-0050); (2) **storage** cannot assume host packages — CSI must
  be self-contained (Rook-Ceph/Mayastor run as pods; ADR-0052); (3) **node
  lifecycle** is image-based re-provisioning, not in-place mutation (ADR-0054).
- **Repo idioms:** Terragrunt **catalog units** (`catalog/units/*`) composed into
  **stacks** (`catalog/stacks/*`); in-cluster delivery via **ArgoCD apps**
  (`apps/infra/*`); reusable Terraform modules (`terraform/modules/*`) each with a
  `*.tftest.hcl` (impl phase). Live tree mirrors the existing
  `terragrunt/gcp-staging/<region>/<stack>` shape with a new
  **`terragrunt/uk/{primary,standby}/platform/`** tree (the UK doc already names
  this path).
- **Provider/version conventions (match the repo):** Terraform `~> 1.11`
  (per `gcp-gke-gpu-nodepools/versions.tf`; repo pins `1.14.8`). Bare-metal/Talos
  providers to name (DESIGN ONLY): **`siderolabs/talos`** (Talos machine config +
  client config), Cluster-API CRDs via a kubectl/kubernetes provider
  (`gavinbunney/kubectl` or `alekc/kubectl`) for Metal³/Sidero objects, optionally
  **`bpg/proxmox`** if a hypervisor substrate is used for the mock, and
  `hetznercloud/hcloud` *only if* the OPEN-DECISION provider is Hetzner robot.
  No new abstractions beyond these.
- **Reuse, don't reinvent:** container build/sign (cosign/syft composites),
  observability stack (Prometheus/Grafana/Alertmanager/OTel), CI
  (terragrunt-plan/apply two-step), the **`failover-controller` + `dns-monitor`**
  for DC failover, **Airflow/MLflow/Evidently** for the ML layer. No secrets in
  code (Vault for UK-resident data per the existing fiction + ESO; never commit
  `.tfvars` with secrets or Talos secrets bundles).
- **Repo uses Terraform, not OpenTofu.** Do not emit OpenTofu-only features.
- **Preserve product fiction** (transaction-analytics domain, the
  client-operated edge agent, ai-sre) as design-ahead; this plan **formalizes the
  UK-DC bare-metal slice** into IaC and adds the ML-platform layer on top of it.

## 4. Workstreams

Each is independently shippable, ADR-gated, and maps to one `/infra-team` run.

### WS-A — Bare-metal GPU cluster foundation & elasticity  *(the biggest net-new; mirrors ADR-0036 + ADR-0042)*

- **Objective:** stand up an owned, **Talos Linux** GPU Kubernetes cluster (control
  plane + GPU workers) as **declarative IaC**, with Cilium CNI, bare-metal LB,
  GPU enablement via **Talos system extension**, DCGM, DRA, Volcano, a
  high-performance GPU **fabric** (RoCE/InfiniBand), and an elasticity story that
  works **without a cloud autoscaler** — across **≥2 UK datacenters** (primary +
  standby) with the existing health-checked failover.
- **Net-new build (modules):**
  - `terraform/modules/talos-machineconfig` — renders Talos `MachineConfig` for
    **control-plane** and **GPU-worker** machine classes via the
    `siderolabs/talos` provider (`talos_machine_secrets`,
    `talos_machine_configuration`, `talos_client_configuration`): immutable
    install disk, k8s version pin, **system-extension list** (incl. the NVIDIA
    driver extension, ADR-0050), **`machine.kernel.modules` (incl. `rbd` + `ceph`
    for Rook-Ceph RBD, ADR-0052; `nvidia*` for the GPU driver, ADR-0050) + the Rook
    kubelet extra-mounts / sysctls / open-file limits**, `machine.nodeLabels`
    carrying ADR-0028 keys, KubePrism enabled, no-SSH/mTLS-API posture. **No host
    bootstrap script** — this is the explicit replacement for `hetzner-kubeadm.sh`.
    (This module is the single place storage and GPU kernel prerequisites are
    declared — they **cannot** be installed on a running immutable host.)
  - `terraform/modules/talos-cluster` — control-plane bootstrap + etcd
    (`talos_machine_bootstrap`, `talos_cluster_kubeconfig`), control-plane VIP /
    KubePrism, and the etcd snapshot schedule wiring.
  - `terraform/modules/talos-gpu-nodepool` — a *logical* GPU node pool over a set
    of bare-metal machines (fixed capacity; the bare-metal analogue of
    `gcp-gke-gpu-nodepools` **minus the autoscaler**): binds machines to the
    GPU-worker machine class, taints/labels (`nvidia.com/gpu.present=true` +
    ADR-0028), and — per ADR-0054 — optionally drives **Cluster-API/Metal³**
    `Machine`/`MetalMachine` objects for re-image-based lifecycle.
  - `terraform/modules/baremetal-cilium-lb` — Cilium CNI in **kube-proxy-less**
    mode + **LB-IPAM** + **BGP control-plane** peering to ToR switches (ADR-0051);
    address pools for service VIPs; honours the `cilium-bgp-issues.md` runbook
    (hold-timer, max-prefix). Reuses the existing `cilium` module shape.
  - `terraform/modules/baremetal-gpu-operator` — NVIDIA **GPU Operator** in
    **driver-less mode** (`driver.enabled=false`) because the driver ships in the
    Talos image as a system extension (ADR-0050); Operator runs GFD/NFD/CDI +
    device-plugin + **NVIDIA DRA driver** only; `dcgmExporter.enabled=false`
    (owned by `baremetal-gpu-dcgm`) — same split as the EKS/GKE modules.
  - `terraform/modules/baremetal-gpu-dcgm` — DCGM Exporter DaemonSet +
    ServiceMonitor + XID/temp/ECC/NVLink alert rules + **GPU-health auto-taint
    CronJob** (ports `gpu-inference-dcgm`); honours `gpu-driver-updates.md`
    post-update checklist.
  - `terraform/modules/baremetal-gpu-scheduling` — **Volcano** secondary
    scheduler + the **exact queue taxonomy already specified** in
    `06-uk-datacenters.md` (H100 pool: `training-default`/`training-bootstrap`/
    `training-urgent`; H200 pool: `serving-vllm`/`eval-judge`/`engine-build`/
    `batch-rescore`) + DRA `DeviceClass`/`ResourceClaimTemplate` for
    H100/H200/L40S and fractional-GPU (folds `gpu-inference-dra`).
  - `terraform/modules/baremetal-gpu-fabric` — **high-performance GPU fabric**
    (ADR-0053): **SR-IOV / RDMA device plugin as the day-0 primary**, with **Cilium
    `netdev` DRA (mirror of DRANET) as the gated target** once DRA-`netdev` is GA on
    our Talos/k8s + a `dranet` release is validated on our NIC/kernel/image + it
    matches the SR-IOV NCCL baseline (the ADR-0053 D3 maturity gate), for
    **GPUDirect RDMA** over **RoCEv2 / InfiniBand** (the doc specifies 400 Gbps IB +
    NVSwitch); jumbo frames (MTU 9000 per `nic-tuning`); composes with the
    GPU-compute DRA claim so Volcano schedules GPU + NIC as one unit (same
    one-DRA-model principle as ADR-0042 D3). An **NCCL all-reduce bandwidth test is
    the acceptance gate** (per `nccl-troubleshooting.md`).
  - `terraform/modules/baremetal-rook-ceph` — **Rook-Ceph** cluster (block + FS +
    **RGW S3** object) as the default storage substrate (ADR-0052), self-contained
    as pods (no host packages — required by immutable Talos); the **Ceph-RGW S3
    endpoint** is the optional S3-compatible artifact-store backend for WS-B.
    **HARD prerequisite (ADR-0052):** RBD PVCs will not mount until
    `talos-machineconfig` declares the **`rbd`** + **`ceph`** kernel modules
    (+ Rook kubelet extra-mounts / sysctls / open-file limits); without them
    `csi-rbdplugin` crash-loops. Sequenced after `talos-machineconfig`/`talos-cluster`.
  - `terraform/modules/baremetal-ingress-waf` — on-prem WAF/rate-limit at the
    serving edge (ADR-0053 serving axis): **Cilium Gateway** *or* **Envoy
    Gateway** (reuse `apps/infra/envoy-gateway`) with Cilium L7 rate-limit /
    Envoy ratelimit — the on-prem mirror of Cloud Armor (no cloud LB).
- **Net-new build (in-cluster, ArgoCD apps):** `apps/infra/talos-system-extensions`
  (extension catalog/version pins as a GitOps doc), `apps/infra/baremetal-gpu-fabric`
  (SR-IOV/DRA CRs), `apps/infra/rook-ceph` (CephCluster/CephBlockPool/
  CephObjectStore CRs), `apps/infra/baremetal-inference-gateway` (Gateway /
  InferencePool / InferenceObjective (v1 GA renamed `InferenceModel`→`InferenceObjective`;
  `InferencePool`/`HTTPRoute` unchanged) — mirror of `gke-inference-gateway` on Cilium/
  Envoy Gateway, **not** a cloud LB).
- **Net-new build (catalog units, one per module):** `talos-machineconfig`,
  `talos-cluster`, `talos-gpu-nodepool`, `baremetal-cilium-lb`,
  `baremetal-gpu-operator`, `baremetal-gpu-dcgm`, `baremetal-gpu-scheduling`,
  `baremetal-gpu-fabric`, `baremetal-rook-ceph`, `baremetal-ingress-waf` — under
  `catalog/units/*`, wired into the new stack below.
- **Net-new build (stack):** `catalog/stacks/baremetal-gpu-analysis/terragrunt.stack.hcl`
  — the bare-metal analogue of `gcp-gpu-analysis`, composing the units **per DC**
  (primary + standby), placed under the live tree at
  `terragrunt/uk/{primary,standby}/platform/` (the path the UK doc already names).
  Wiring order: `talos-machineconfig → talos-cluster → talos-gpu-nodepool →
  baremetal-cilium-lb → baremetal-rook-ceph → baremetal-gpu-operator →
  baremetal-gpu-dcgm → baremetal-gpu-scheduling → baremetal-gpu-fabric →
  baremetal-ingress-waf`, cross-wired via `dependency` blocks with `mock_outputs`
  (kubeconfig/endpoint/CA from `talos-cluster`).
- **Reuse:** `cilium`, `gpu-operator`/`gpu-inference-dcgm`/`gpu-inference-volcano`/
  `gpu-inference-dra` (shape ported), `keda`/`hpa-defaults`, `envoy-gateway`,
  `failover-controller` + `dns-monitor` (DC failover), the existing Volcano queue
  taxonomy + DRA semantics, and the Ansible-below-Talos roles named in
  `06-uk-datacenters.md` (`bare-metal-firmware`/`nic-tuning`/`gpu-nodes`/
  `network-fabric`) which sit **outside** Terraform and are referenced, not
  rebuilt, here.
- **Elasticity story (no cloud autoscaler) — explicit (ADR-0054):**
  - **GPU capacity is fixed per DC.** Primary sized for 100% steady state;
    standby ~40% (per the UK doc) — sized to absorb failover serving, not to
    co-work. There is no "scale the GPU fleet up on demand"; there is "re-image a
    spare bare-metal box into the GPU-worker class," which is minutes-to-hours.
  - **Scale *workloads*, not nodes.** KEDA/HPA scale serving **pods** to zero/up
    within fixed capacity; Volcano queues + DRA gate **jobs** to the fixed GPU
    inventory (the queue weights in `06-uk-datacenters.md` are the fair-share
    mechanism). Idle GPUs are reclaimed by scaling pods to zero, not by
    deprovisioning hardware.
  - **Node lifecycle** = Cluster-API/Metal³ (or Sidero) re-image, **or** static
    pre-provisioned pools, **or** provider robot-API (Hetzner) — the choice is
    ADR-0054 + an OPEN DECISION. Cluster-API is preferred for Git-driven node
    lifecycle (the UK doc already names `cluster-api-provider-metal3`/`-sidero`).
  - **Cross-DC failover** is the elasticity-of-last-resort: lose primary →
    `failover-controller` promotes standby (serving); **batch/training is
    DC-pinned and re-queued, not migrated** (gang-scheduled GPU jobs are not
    safely relocatable — same rule as ADR-0036 D5).
- **Deliverables:** the 10 modules + 10 catalog units + 4 ArgoCD apps + the
  `baremetal-gpu-analysis` stack above; one `*.tftest.hcl` per module (impl
  phase); all carry ADR-0028 labels; ADR-0049 (+ ADR-0050/0051/0052/0053/0054).
- **Acceptance:**
  - A Talos control plane + GPU worker come up **from machine config alone** (no
    SSH, no host bootstrap script); `talosctl` is the only access path; KubePrism
    serves the in-cluster API.
  - The **NVIDIA driver is present via the system extension** (`nvidia-smi` works
    in a GPU pod) with **no mutable host install**; GPU Operator runs driver-less.
  - A GPU pod schedules on the fixed pool; **DCGM metrics flow** to
    VictoriaMetrics/Prometheus; the GPU-health auto-taint fires on a simulated XID
    burst.
  - A **service VIP is advertised via Cilium BGP** (or MetalLB) and reachable from
    outside the cluster (no cloud LB).
  - An **NCCL all-reduce bandwidth test** over the RoCE/IB fabric hits the
    expected GB/s floor (per `nccl-troubleshooting.md`).
  - **Rook-Ceph** provides a PVC (block) and an **S3 bucket via RGW**; a workload
    binds both — specifically, with `rbd`+`ceph` declared in `talos-machineconfig`,
    **an RBD PVC actually mounts on a Talos node** (`csi-rbdplugin` healthy, not
    crash-looping) — the load-bearing ADR-0052 gate.
  - **Scale-to-zero of a serving Deployment** reclaims its GPU without touching
    node count; re-scaling re-schedules onto the fixed pool.
  - Every resource carries `platform.system` / `platform_system` labels.

### WS-B — ML CI/CD pipelines (train → test → deploy) + model registry  *(cluster-agnostic reuse; mirrors ADR-0037)*

- **Objective:** run the documented training pipeline as an automated system **on
  the bare-metal cluster**, reusing the existing Airflow/MLflow/cosign artifacts
  with the **only substitution being the object-store substrate**.
- **Decision (locked, §7):** orchestrator = **self-hosted Airflow** (the UK doc
  already runs Airflow workers on the CPU pool and DAGs
  `train_domain_adapter → eval_adapter_debate → mine_templates → promote_to_edge`
  per `04-training-pipeline.md`); registry = **MLflow** (PostgreSQL via
  **CloudNativePG**, already in the UK inventory; artifact store = **MinIO** or
  **Ceph-RGW** — both already in the UK inventory — surfaced as an OPEN DECISION,
  default MinIO since the UK doc already lists MinIO pools).
- **Build:** deploy Airflow + MLflow as ArgoCD apps on bare metal (reuse
  `apps/infra/airflow`, `apps/infra/mlflow`); **re-point the artifact store** from
  GCS/S3 to the MinIO/Ceph-RGW S3 endpoint (S3-compatible API — MLflow + the GH
  Actions are endpoint-agnostic); implement the design's four DAGs on the Volcano
  `training-*` queues; a **GitHub Actions** ML pipeline runs
  train→eval→**quality-gate**→register→deploy, signing artifacts with the existing
  cosign/syft composites; promote via the two-step rollout + **Kargo** (already
  extended to the edge fleet in `05-edge-deployment.md` — extend to in-cluster
  serving).
- **Deliverables:** `apps/infra/airflow` + `apps/infra/mlflow` re-targeted at
  bare metal; **`terraform/modules/baremetal-ml-artifact-store`** (the bare-metal
  analogue of `ml-artifact-store`: a Ceph-RGW/MinIO **bucket + scoped S3
  credential via Vault/ESO**, not a GCS bucket + GSA) + its catalog unit;
  `.github/workflows/ml-pipeline-baremetal.yml`; ADR-0037 is reused as the
  decision of record (no new ADR needed — the orchestrator/registry choices are
  identical; the substrate delta is captured in **ADR-0052**).
- **Acceptance:** a commit to a model/adapter triggers
  train→eval→gate→register→staged deploy with a **signed** artifact and a rollback
  path; the ArgoCD app + the S3 credential carry ADR-0028 labels; MLflow stores
  artifacts in the **MinIO/Ceph-RGW** bucket; Helm values set
  `ciliumNetworkPolicy.enabled: true` with matching `platform.system`.

### WS-C — Model & ML observability (drift / accuracy / distribution)  *(cluster-agnostic reuse; mirrors ADR-0038)*

- **Objective:** continuous monitoring of model accuracy + data/concept drift in
  production on the bare-metal cluster — identical to the GCP design, reusing
  `apps/infra/ml-monitoring`.
- **Decision (locked, §7):** **Evidently / whylogs** (OSS, Prometheus-native →
  reuses the UK DCs' existing Prometheus/Thanos/Grafana/Alertmanager stack named
  in `06-uk-datacenters.md`).
- **Build:** deploy the `ml-monitoring` service (`platform.system = ml-monitoring`)
  computing feature drift, distribution shift, accuracy, degradation; export as
  Prometheus metrics into the existing stack; wire **drift → Alertmanager →
  PagerDuty**; **retrain trigger:** Alertmanager webhook → **Airflow REST**
  `POST /api/v1/dags/train_domain_adapter/dagRuns` (K8s-Job fallback). Track
  serving latency via OTel/Tempo. Multi-tenant isolation = **namespace-per-tenant**
  (already the chosen tenancy model in `06-uk-datacenters.md`) +
  `platform.system` label filtering — this is a **stronger** isolation story than
  the GCP plan because the tenancy model is already namespace-scoped here. Note
  the edge already does score-distribution KL-divergence drift guarding in Kargo
  (`05-edge-deployment.md`); WS-C is the **in-cluster, training-side** complement.
- **Deliverables:** `apps/infra/ml-monitoring` (reused), drift/accuracy Grafana
  dashboards (under `monitoring/dashboards/transaction-analytics/`), Alertmanager
  routes + webhook receiver; ADR-0038 reused as decision of record.
- **Acceptance:** an injected distribution shift raises a drift metric, fires an
  alert, opens a retrain trigger against Airflow; an accuracy dashboard is live
  per model/tenant.

### WS-D — System & self-serve observability + team enablement  *(reuse; mirrors ADR-0039)*

- **Objective:** let teams monitor their own workloads (ML and non-ML) without
  platform-team tickets, on the bare-metal cluster.
- **Build:** templated per-team Grafana folders/dashboards + alert-rules-as-code
  (reuse `apps/infra/grafana-self-serve`, `platform.system = observability`);
  **add bare-metal-specific starter panels** the cloud plan didn't need — **Talos
  node health** (`talos-log-shipper` is already specified), **IB/RoCE fabric**
  (NCCL/NVLink counters), **Cilium BGP session** state (per
  `cilium-bgp-issues.md`), **Ceph** cluster health, and **etcd/control-plane**
  health (the managed-K8s plan never owned these). **Backstage stays deferred**
  (ADR-0034).
- **Reuse:** existing Prometheus/Grafana/Loki/Tempo + Alertmanager (the UK doc
  already specifies the scrape set + forwarded aggregates to AWS).
- **Acceptance:** a new team gets a scoped dashboard + alert namespace from a
  template PR; bare-metal-specific (node/fabric/Ceph/etcd/BGP) panels are live
  alongside ML.

### WS-E — Security posture & SOC compliance + on-call  *(mirrors ADR-0040)*

- **Objective:** make compliance (SOC2-style) demonstrable and complete the
  on-call posture for the bare-metal estate, formalizing the **Talos security
  model** as controls.
- **Build:**
  - **Talos OS posture as controls:** immutable, minimal OS (no shell, no SSH, no
    package manager → drastically reduced attack surface), **mTLS machine API**
    with strict auth (no plaintext), **KubePrism** for in-cluster API HA,
    A/B-partition atomic upgrades with auto-rollback — each mapped to a SOC2
    control family and to a Talos-config assertion (e.g. `machine.features.kubePrism`
    enabled; no SSH/extra-kernel-args opening a shell path).
  - **Policy parity:** reuse **Kyverno + VAP** and **Gatekeeper** (the UK doc
    already specifies Gatekeeper tenant constraints — reject pods without
    `tenant={id}`, reject cross-namespace SA refs) on this cluster.
  - **SOC2 control-to-evidence matrix:** which existing controls (Kyverno/
    Tetragon/Gatekeeper/cosign-syft/secret-rotation/audit logging/**Talos
    immutability + no-SSH + mTLS API**/Vault per-tenant KMS) satisfy which control
    families, + a posture report. The UK doc already states the **quarterly DR
    drill runs per SOC2 CC-series** — this folds in as evidence.
  - **On-call + runbooks:** formalize the rotation + escalation (PagerDuty already
    present) and add **ML-incident** runbooks (drift storm, training-queue
    starvation) and reference the **existing `uk-dc-failover.md`** DC-failover
    runbook + the `ai-sre/knowledge/*` GPU/NCCL/BGP runbooks.
- **Deliverables:** **`terraform/modules/baremetal-org-policy`** (the bare-metal
  analogue of `gcp-org-policy`: Talos `machine` posture assertions + Kyverno/
  Gatekeeper policy bundle as code) + catalog unit; **`tests/opa/platform_tags_baremetal.rego`**
  — the bare-metal/`talos_*` OPA profile (a `talos_*`/`kubernetes_manifest`-aware
  re-key of `platform_tags.rego`, whose `_exempt_types` + `tags["platform:system"]`
  lookup are AWS-shaped today), so ADR-0028 tag enforcement holds at plan time on
  this estate; a control-to-evidence matrix doc; ML + DC-failover on-call runbooks;
  ADR-0040 reused + a Talos-posture delta captured in **ADR-0050** (the immutable-OS
  security rationale).
- **Acceptance:** a control-to-evidence matrix exists and references concrete
  Talos-config assertions; bare-metal workloads are policy-gated; **the
  `platform_tags_baremetal.rego` OPA profile flags a `talos_*`/`kubernetes_manifest`
  resource missing the ADR-0028 keys at plan time** (the AWS-shaped policy does
  not); on-call rotation + ML runbooks documented and exercised in a tabletop; a DR
  drill is runnable per `uk-dc-failover.md`.

### WS-F — Collaboration / golden paths  *(cross-cutting, light; mirrors ADR-0041)*

- **Objective:** bridge data / ML / backend / frontend for smooth production
  operation on the bare-metal estate.
- **Build:** golden-path templates (new model service, new pipeline, new
  dashboard, **new tenant** — the UK doc already specifies the single
  `charts/tenant-bootstrap/` install; formalize it as a golden path), shared
  API/data contracts, a RACI + handoff doc, riding the WS-B/C/D artifacts.
  Largely process + templates (reuse `templates/golden-paths/`, ADR-0041).
- **Acceptance:** a new model service / pipeline / dashboard / tenant is created
  from a template PR; the tenant-bootstrap golden path provisions the
  namespace-per-tenant bundle end-to-end.

## 5. Sequencing

```
Phase 0  ADRs 0049–0054 for WS-A + decisions in §7 resolved
Phase 1  WS-A  bare-metal Talos GPU foundation (cluster + LB + GPU + fabric + storage)  ─┐ (the foundation; biggest build)
Phase 2  WS-B  ML CI/CD + MLflow registry (re-point artifact store at MinIO/Ceph-RGW)    ├─ B and C in parallel
         WS-C  ML observability / drift                                                  ─┘   once A lands
Phase 3  WS-D  self-serve observability + bare-metal panels + enablement
         WS-E  Talos/SOC posture + on-call + DC-failover runbook
Phase 4  WS-F  golden paths (consumes B/C/D outputs)
```

**Dependency graph:**
```
WS-A ──→ WS-B   (deploys onto the bare-metal cluster; needs Ceph-RGW/MinIO for artifacts)
WS-A ──→ WS-C   (deploys onto the bare-metal cluster)
WS-A ──→ WS-E   (Talos posture IS a WS-A property; SOC evidence cites it)
WS-B ←─→ WS-C   (bidirectional: drift → retrain trigger)
WS-B ──→ WS-D   (dashboards consume pipeline metrics)
WS-B ──→ WS-F   (golden paths need the pipeline template)
WS-C ──→ WS-D   (drift dashboards feed self-serve)
WS-D ──→ WS-F   (self-serve surfaces feed golden paths)
```
Within WS-A the **internal order is load-bearing** (unlike the GCP plan where the
cluster pre-existed): `talos-machineconfig → talos-cluster` (control plane + etcd)
**gates everything**; then `baremetal-cilium-lb` (CNI must exist before
workloads), `baremetal-rook-ceph` (storage before stateful ML), then the GPU
stack (operator → dcgm → scheduling → fabric), then `baremetal-ingress-waf`. WS-A
is the gate for B/C/E. B and C are mutually reinforcing and parallelizable. D/E/F
follow their dependencies.

## 6. Execution model & global acceptance

- One **ADR + one `/infra-team` run per workstream**, in plan/validate-only mode.
- Each run: ADR → catalog unit/module + ArgoCD app → `terraform`/`terragrunt`
  plan + `*.tftest.hcl` → **`talosctl … --dry-run` / config validate (no apply)**
  → security gate → **draft PR** with plan output → CI green → human review →
  merge → **apply gated** behind explicit go.
- **No live apply of any kind** (no `terraform apply`, no `talosctl apply-config`/
  `upgrade`, no Cluster-API reconcile, no Helm install, no machine reboot) without
  explicit human approval + blast-radius review. **Nothing is ever applied to real
  hardware** — this is a mock/emulation repo.
- **Control-plane-specific gates** the managed-K8s plan didn't need: an **etcd
  snapshot** is taken and verified before any control-plane `MachineConfig` change
  or Talos upgrade; quorum is checked before draining a control-plane node.
- **Global acceptance (the plan is "done designing" when):** (a) ADRs 0049–0054
  are Proposed and indexed; (b) every WS lists concrete module + catalog-unit +
  ArgoCD-app names with a `*.tftest.hcl` planned per module; (c) the
  `baremetal-gpu-analysis` stack composes the WS-A units per DC under
  `terragrunt/uk/{primary,standby}/platform/`; (d) every named resource carries
  ADR-0028 labels and the OPA policy's bare-metal profile gap is recorded; (e) the
  GCP→bare-metal traceability table (§10) maps every etalon artifact to its mirror;
  (f) the existing UK-DC/edge/ai-sre fiction is honoured (cited inline), not
  contradicted; (g) all OPEN DECISIONS (§7) have a recommended default + a
  decision-of-record ADR.

## 7. OPEN DECISIONS

These are the calls that must be resolved (most have a recommended default) before
WS-A implementation. They are the bare-metal-specific analogue of the GCP plan's
§7 — but where the GCP plan could lock most decisions, bare metal genuinely
branches on hardware/provider, so more remain open.

1. **Bare-metal provider / substrate.** *Options:* **Hetzner robot** (dedicated
   bare-metal, robot API — closest to the existing `hetzner-nodes` fiction and the
   repo's `hcloud` familiarity) vs **Equinix Metal** (first-class bare-metal API,
   strong Cluster-API/Tinkerbell story) vs **owned colo** (the
   `06-uk-datacenters.md` premise: we own the racks, ToR, dark fibre). *Recommend:*
   model the design **provider-agnostic at the Talos/Cluster-API layer** and treat
   the provider as the Metal³/Sidero/robot driver beneath it; **default to the
   owned-colo premise** the UK doc already commits to (it's the source of the IB
   fabric + dark-fibre + 2-DC topology), with Hetzner-robot as the cheap
   emulation substrate for mock/plan. *Decision of record:* **ADR-0054.**
2. **Talos node provisioning / lifecycle.** *Options:* **Cluster-API + Metal³**
   (Ironic/PXE, Git-driven, the UK doc's named choice) vs **Cluster-API + Sidero**
   (Talos-native, also named) vs **manual PXE / ISO** (simplest, least elastic) vs
   **provider robot-API** (Hetzner). *Recommend:* **Cluster-API + Sidero** (Talos-
   native, least impedance with the immutable model) as primary, **manual PXE** as
   the bootstrap fallback for the very first control-plane node. *Decision of
   record:* **ADR-0054.**
3. **Storage backend.** *Options:* **Rook-Ceph** (block + FS + **RGW S3** in one,
   the UK doc already runs MinIO + tiered NVMe so Ceph is a natural fit) vs
   **Mayastor/OpenEBS** (NVMe-oF, lowest-latency block, **no S3**) vs
   **local-path** (simplest, no replication — unacceptable for stateful ML state).
   *Recommend:* **Rook-Ceph** as the default (gives S3 via RGW for the artifact
   store **and** replicated block/FS for Postgres/MLflow), with **Mayastor as an
   optional fast-block tier** for latency-sensitive DBs. *Decision of record:*
   **ADR-0052.**
4. **S3-compatible artifact store.** *Options:* **MinIO** (already in the UK
   inventory; the UK doc lists MinIO pools + MinIO site-replication for DR) vs
   **Ceph-RGW** (comes free with the ADR-0052 Rook-Ceph choice; one fewer system)
   vs **external S3** (AWS — but breaks UK data-residency for training data).
   *Recommend:* **MinIO** to honour the existing fiction (and its proven
   site-replication path for cross-DC DR), **OR Ceph-RGW** if ADR-0052 lands
   Rook-Ceph and we want one fewer object system — explicitly a sub-decision of
   ADR-0052. **Not external S3** for UK-resident training data. *Decision of
   record:* **ADR-0052.**
5. **Load balancer.** *Options:* **Cilium LB-IPAM + BGP control-plane** (no extra
   component — Cilium is already the CNI; the `cilium-bgp-issues.md` runbook
   already exists, implying BGP is the intended path) vs **MetalLB** (mature,
   simpler L2/BGP, but a second networking component alongside Cilium). *Recommend:*
   **Cilium LB-IPAM + BGP** (one networking stack, eBPF datapath, runbook already
   written). *Decision of record:* **ADR-0051.**
6. **High-performance GPU fabric.** *Options:* **RoCEv2** (Ethernet, the GCP-side
   RoCE/DRANET analogue, ToR-switch-friendly) vs **InfiniBand** (the UK doc's
   stated 400 Gbps IB + NVSwitch — highest performance, dedicated fabric, needs a
   subnet manager) vs **TCP-only first** (no GPUDirect; correctness baseline,
   slowest). *Recommend:* **InfiniBand** as the steady-state target (it's what the
   hardware fiction already specifies and what NCCL/NVSwitch assume), with **RoCEv2
   as the Ethernet alternative** where IB isn't available, and **TCP-only as the
   day-0 correctness fallback** before the fabric is validated by the NCCL
   all-reduce gate. *Decision of record:* **ADR-0053.**
7. **GPU driver delivery.** *Options (constrained by the user's Talos choice):*
   **Talos system extension** (`nonfree-kmod-nvidia` + `nvidia-container-toolkit`
   baked into the boot image) vs **mutable host install** (impossible on Talos —
   no package manager) vs **GPU-Operator-managed driver container** (the
   `driver.enabled=true` path). *Recommend / effectively decided:* **Talos system
   extension** (the only immutable-compatible path; GPU Operator then runs
   driver-less). Open sub-question: **pin the extension version to the Talos
   release** vs **Operator driver-container for faster driver bumps** — recommend
   system extension pinned to Talos, accept the coupled-upgrade cost. *Decision of
   record:* **ADR-0050.**
8. **Multi-DC topology + cross-DC failover.** *Options:* **independent per-DC
   clusters + DNS/health failover** (the UK doc's primary-active + standby-hot-
   standby + `failover-controller`; matches ADR-0036 D5's independent-regional
   pattern) vs **stretched/ClusterMesh across DCs** (cross-DC scheduling — pays
   inter-DC latency, deepens blast radius). *Recommend:* **independent per-DC
   clusters + the existing `failover-controller`/`dns-monitor`** (serving fails
   over, batch/training is DC-pinned and re-queued) — **reuse, don't build new**.
   The <30 km dark-fibre + synchronous-Postgres premise in the UK doc is the
   enabler. *Decision of record:* **ADR-0049 (foundation/multi-DC) + ADR-0054
   (lifecycle).**
9. **Share the AWS/GCP ML control plane, or run fully isolated?** *Options:*
   **fully isolated** (the UK doc's premise — UK-resident data, Vault KMS, all
   training/eval/mining runs in-DC; only observability aggregates + ArgoCD pulls
   cross to AWS) vs **shared ML control plane** (one MLflow/Airflow across clouds —
   simpler ops, but moves UK-resident training metadata off-prem). *Recommend:*
   **fully isolated ML control plane in-DC** (own Airflow/MLflow/MinIO) to honour
   UK data-residency, with **only metrics/log aggregates + GitOps pulls** crossing
   to AWS over the existing Cloudflare-Tunnel/IPsec/Direct-Connect link
   (`06-uk-datacenters.md` AWS↔UK section). The cross-cloud WIF federation from
   ADR-0040 still applies for the *control/observability* plane, not the data
   plane. *Decision of record:* **ADR-0049 (scope) + ADR-0040 (federation, reused).**
10. **OPA tag-enforcement on bare metal (owner assigned, not open-ended).** The
    in-repo `tests/opa/platform_tags.rego` is **AWS-shaped** — its `_exempt_types`
    and `tags["platform:system"]` lookup assume `aws_*` resources, so it will not
    enforce ADR-0028 on `talos_*` / `kubernetes_manifest` / Helm resources.
    *Resolution (not deferred):* **WS-E owns** a bare-metal profile
    **`tests/opa/platform_tags_baremetal.rego`** (re-keyed to the `platform_*` label
    form + a `talos_*`/manifest-aware exempt set) as a named deliverable, gating
    bare-metal plans the way the AWS rego gates cloud plans. *Decision of record:*
    **WS-E (security-expert); ADR-0049 D6 records the gap.**

## 8. Out of scope / preserve

- The **client-operated edge agent** (`05-edge-deployment.md`) — a Kafka-mediated,
  no-SSH-from-us, single-agent product on **client** hardware — stays unchanged;
  it is **not** our K8s cluster and is not a target of this plan.
- The **AWS/EKS and GCP/GKE GPU estates** stay as-is; this plan adds the **owned
  bare-metal** ML platform and the UK-DC IaC. It does not migrate either cloud
  control plane.
- The **transaction-analytics product domain** and **ai-sre agents** stay as
  design-ahead; this plan formalizes the **UK-DC infrastructure slice** and adds
  the ML-platform layer on top of it.
- The repo's **`hetzner-nodes` module + `hetzner-kubeadm.sh`** remain as reference
  fiction; they are **not** reused, modified, or extended by this plan.

## 9. Risk register

| # | Risk | Impact | Likelihood | Mitigation |
|---|------|--------|------------|------------|
| R1 | **Bare-metal capacity is fixed** — a demand spike cannot be met by autoscaling | Missed SLAs under burst | High | Size primary for 100% steady state + standby headroom (UK doc); workload scale-to-zero frees GPUs fast; Volcano `training-urgent` queue (cap 2) reserves burst for incidents; node re-image (Cluster-API) for slow capacity adds |
| R2 | **Talos GPU system-extension ↔ Talos release ↔ NVIDIA driver ↔ NCCL skew** (the immutable-OS analogue of the GKE driver-coupling risk) | A bad driver bump bricks GPU nodes cluster-wide | Medium | Pin extension to Talos release; A/B partition + auto-rollback on boot failure; stage on standby DC first; `gpu-driver-updates.md` post-update checklist as the gate |
| R3 | **We operate the control plane** — etcd/quorum loss or a bad control-plane `MachineConfig` | Cluster-wide outage (no managed control plane to fall back on) | Medium | etcd snapshot + verify before every control-plane change; quorum check before drain; KubePrism for API HA; standby DC for catastrophic loss |
| R4 | **RoCE/IB fabric misconfig** silently degrades NCCL to TCP or fails collectives | Training throughput collapse | Medium | NCCL all-reduce bandwidth test as a hard acceptance gate (`nccl-troubleshooting.md`); jumbo-frame + topology pre-flight (`gpu-nodes` Ansible role); DCGM NVLink counters alerting |
| R5 | **Ceph/MinIO is the storage SPOF** for ML state + artifacts | WS-B pipeline + MLflow blocked | Medium | Rook-Ceph replicated pools (≥3 replicas) + MinIO site-replication for cross-DC (UK doc); CloudNativePG streaming replication for MLflow's Postgres; DR drill exercises restore |
| R6 | **Cilium BGP session flap** (per `cilium-bgp-issues.md`) drops service VIP reachability | Serving ingress intermittent | Medium | Hold-timer 180 s under CPU pressure; ToR max-prefix sized; BGP session-state alerting in WS-D; MetalLB L2 as the documented fallback (ADR-0051) |
| R7 | **No cloud-managed anything** widens the on-call + upgrade surface vs the GCP mirror | Operational toil, upgrade risk | High | Talos atomic A/B upgrades + auto-rollback; Cluster-API Git-driven lifecycle; reuse the existing observability + `failover-controller`; SOC/on-call runbooks (WS-E) |

## 10. Relationship to the GCP etalon (traceability)

| GCP etalon artifact | Bare-metal mirror in this plan | Key substitution |
|---|---|---|
| ADR-0036 (GKE parity + multi-region + budget) | **ADR-0049** (Talos foundation + immutability + multi-DC) | managed GKE → self-operated Talos control plane; multi-region → multi-DC; billing-budget → owned-capacity FinOps (no per-call cloud spend) |
| `gcp-gke-gpu-nodepools` (autoscaled) | `talos-gpu-nodepool` (fixed) + **ADR-0054** | cloud autoscaler → fixed pools + Cluster-API re-image + workload scale-to-zero |
| `gke-gpu-operator` (managed/Operator driver) | `baremetal-gpu-operator` (driver-less) + **ADR-0050** | GKE/Operator driver → **Talos system extension** driver |
| `gke-gpu-dcgm` | `baremetal-gpu-dcgm` | none (ported) |
| `gke-gpu-scheduling` (Volcano + DRA) | `baremetal-gpu-scheduling` (Volcano + DRA, UK queue taxonomy) | none (ported; queues already specified in `06-uk-datacenters.md`) |
| ADR-0042 D1–D3 (jumbo + TCPX/TCPXO + DRANET/RoCE) | **ADR-0053** + `baremetal-gpu-fabric` | GCP per-family GPUDirect → **RoCEv2 / InfiniBand + SR-IOV (day-0) / Cilium-netdev-DRANET (gated target)** |
| ADR-0042 D4 (GKE Inference Gateway) | `apps/infra/baremetal-inference-gateway` (Cilium/Envoy Gateway + InferencePool/InferenceObjective) | cloud LB → **on-prem Gateway API** (no cloud LB) |
| ADR-0042 D5 (Cloud Armor) | `baremetal-ingress-waf` (Cilium/Envoy WAF + rate-limit) | Cloud Armor → **on-prem WAF/rate-limit** |
| `gcp-gpu-vpc` (GCP VPC, MTU) | Cilium CNI + `baremetal-cilium-lb` (BGP/LB-IPAM) + **ADR-0051** | cloud VPC + cloud LB → **Cilium eBPF + BGP/MetalLB**, MTU 9000 via `nic-tuning` |
| `gke-inference-gateway` GCS / `ml-artifact-store` (GCS) | `baremetal-ml-artifact-store` (MinIO/Ceph-RGW) + **ADR-0052** | GCS → **MinIO / Ceph-RGW S3** |
| ADR-0037 (Airflow + MLflow) | WS-B (reused) | object store substrate only |
| ADR-0038 (Evidently drift + retrain) | WS-C (reused) | none |
| ADR-0039 (self-serve Grafana) | WS-D (reused + bare-metal panels) | adds node/fabric/Ceph/etcd/BGP panels |
| ADR-0040 (SOC + WIF + on-call) | WS-E (reused) + **ADR-0050** Talos-posture delta | adds immutable-OS / no-SSH / mTLS-API controls; reuses `uk-dc-failover.md` |
| ADR-0041 (golden paths) | WS-F (reused) | adds the `tenant-bootstrap` golden path |
| `failover-controller` + multi-region DNS failover | **reused unchanged** | the same machinery already covers UK-DC failover (`uk-dc-failover.md`) |

---
*Planning-only document. No `terraform apply`, no `talosctl apply-config`, no
Cluster-API reconcile, no Helm install, no hardware mutation is implied. This is a
mock/emulation repo — nothing is ever deployed to real hardware. Greenfield
bare-metal mirror of the GCP ML-platform plan; opens ADRs 0049–0054;
implementation apply-gated. Drafted 2026-06-15 by the platform-design
solution-architect.*
