# UK data centres

Two owned bare-metal data centres in England — **primary** and **standby**. Talos Linux for the k8s layer, Cluster API for lifecycle, Ansible for everything below Talos's declarative surface. All post-analysis, template mining, training, and LLM-as-judge evaluation run here.

---

## Why bare metal at all

See [01-architecture.md](01-architecture.md#why-this-shape) for the economics summary. In short: at our utilisation pattern (continuous, high duty cycle, GPU-heavy), owned hardware in a UK colocation is 2-4× cheaper than equivalent cloud compute over a 3-year horizon, and gives us physical-layer knobs (NIC tuning, NUMA pinning, thermal profiles) that affect our workload but are not exposed on cloud instance types.

---

## Physical inventory (per DC, steady state)

| Pool | Nodes | Hardware | Role |
|------|-------|----------|------|
| **H100 training** | 4-8× DGX H100 equivalents | 8× H100 SXM5 per node, 900 GB/s NVSwitch, 400 Gbps InfiniBand to pod | SFT + LoRA training, synthetic-label generation |
| **H200 inference** | 2-4× H200 nodes | 8× H200 per node, 141 GB HBM each, NVSwitch, 400 Gbps IB | vLLM multi-LoRA batch serving, LLM-as-judge debate, TRT-LLM engine build farm |
| **CPU / mixed** | 8-16× dense CPU nodes | 2× 96-core AMD or Intel, 2-4 TB RAM, 2× 100 GbE, 16× NVMe | Airflow workers, Trino workers, Kafka brokers, QuestDB nodes, MinIO nodes, Postgres (CloudNativePG), OTel collectors, Qdrant, Argilla |
| **Storage** | 4-8× JBOD chassis | High-density NVMe + HDD tiered, 8× 100 GbE | MinIO pools for Iceberg cold; QuestDB tiered storage offload |

Primary is sized for 100% of steady-state load. Standby runs at ~40% of primary's capacity during normal operations — enough to absorb failover, not enough to do useful co-work.

---

## Talos + Cluster API

### Why Talos over alternatives

- Immutable, minimal Linux built specifically for Kubernetes. No shell, no systemd in the traditional sense, API-driven configuration.
- Everything is declarative — machine configuration, k8s version, network settings, disk layout. The same shape as our Terragrunt AWS stacks, so the team's mental model transfers.
- Security posture: no SSH, machine API with mTLS + strict auth. Each upgrade is a config apply + reboot, atomic.
- Upgrade story is clean: A/B installation of system partition, auto-rollback on boot failure.
- Active community, real production users at comparable scale.

Alternatives considered: Rancher RKE2 (more flexible but larger attack surface and heavier operational cost), k3s (better for edge than DC, not suited to 10+ node GPU workloads), stock Ubuntu + kubeadm (standard but we would reimplement what Talos gives us for free).

### Cluster API providers

- `cluster-api-provider-metal3` (or `cluster-api-provider-sidero` — specifically designed for Talos) for lifecycle management of bare-metal nodes
- `cluster-api-bootstrap-provider-talos`
- `cluster-api-control-plane-provider-talos`

Cluster lifecycle is Git-driven: the cluster definition lives in `terragrunt/uk/{primary,standby}/platform/`, ArgoCD (running on AWS or bootstrapped locally on UK) applies it, Cluster API provisions or updates nodes accordingly.

---

## Ansible for the rest

Talos covers everything at and above the k8s layer. Below Talos there are still decisions to make per host and per NIC, which Ansible handles on day-1 and on any hardware change. Ansible roles:

| Role | What it does |
|------|--------------|
| `bare-metal-firmware` | BIOS/UEFI settings (PCIe bifurcation, Above-4G decoding, IOMMU, SR-IOV enablement), BMC configuration, firmware versions |
| `nic-tuning` | MTU 9000 on 100 GbE links, RSS queues, ring buffer sizes, coalescing parameters, IRQ affinity pinned to cores on the same NUMA node as the NIC |
| `kernel-rt` | For the Kafka-broker nodes and QuestDB nodes: PREEMPT_RT kernel, CPU isolation (`isolcpus`), no HZ, mlock for the Kafka JVM |
| `numa-pinning` | Per-node topology-aware scheduler configuration, CPU / HugePages layout for the workloads pinned on each node |
| `gpu-nodes` | NVIDIA driver installation, CUDA toolkit, DCGM, NCCL-tests pre-flight, topology verification (NVSwitch, NVLink mesh, IB connectivity) |
| `storage-pools` | JBOD chassis configuration, multipath setup, ZFS or XFS mount options, NVMe over Fabrics if used |
| `network-fabric` | Top-of-rack switch ports on the InfiniBand fabric, VLAN configuration on the Ethernet side, BGP peerings |

Ansible runs out-of-band (over BMC on initial setup, over a dedicated management network afterwards). It is never in the critical path of a running workload.

Everything Ansible does is idempotent and version-controlled in `ansible/` at the repo root. Playbooks are CI-linted (ansible-lint) on every PR touching `ansible/`.

---

## Logical layout: namespace-per-tenant

Multi-tenancy model picked in design discussion: **option (a) — namespace-per-tenant with NetworkPolicy + encryption-at-rest per tenant.** This balances isolation against operational cost. Cluster-per-tenant (option b) was rejected as too expensive at target tenant count.

### What a tenant gets, automatically

Provisioning a new tenant is a single Helm chart install (`charts/tenant-bootstrap/`) that creates:

- Kubernetes namespace `tenant-{id}`
- `NetworkPolicy` default-deny + explicit allows to:
  - The tenant's own Kafka topic listener endpoints (identified by broker SNI)
  - Shared infra namespaces on required ports only (e.g., metrics scraping from observability namespace)
  - DNS
- `ResourceQuota` and `LimitRange` sized per the tenant's contract tier
- `Gatekeeper` constraints: reject pods without the `tenant={id}` label, reject pods referencing service accounts from other namespaces
- Kafka ACLs scoped to `tenant-{id}.*` topics only
- QuestDB database with a unique login and GRANT on that database only
- Iceberg namespace `tenant_{id}.*`, permissions via the REST catalog
- Qdrant collection with scoped API key
- Postgres schema `tenant_{id}.*` with a dedicated role
- Argilla workspace with tenant-scoped membership
- **Tenant-scoped KMS key** (Vault for UK-resident data, AWS KMS for AWS-resident metadata) — every data-at-rest encryption for this tenant goes through this key
- Service-account OIDC issuer claim for downstream auth

This is driven end-to-end by `charts/tenant-bootstrap/`. There is no manual step required beyond running the chart install and populating the tenant metadata row in Postgres.

### Why namespace-per-tenant is enough for our threat model

- We are not running untrusted code from tenants. Every workload is our own software, our own containers.
- The attack we are defending against is **operational confusion** (wrong tenant's data retrieved in a query, wrong tenant's topic consumed) and **insider mistakes** in engineering code. Namespace + RBAC + NetworkPolicy + per-tenant credentials defeats both.
- True adversarial sandboxing (untrusted container from tenant X running in same cluster as tenant Y) is not our shape. If a tenant ever asks to run their own code in our cluster, we would revisit and likely move that tenant to cluster-per-tenant.

See [07-compliance-security.md](07-compliance-security.md) for the full threat model and control mapping.

---

## Primary ↔ standby replication

**Mode**: primary-active + standby-hot-standby (per [PLAN.md](../../PLAN.md) phase 7).

### What replicates

| Data | Mechanism | Lag target |
|------|-----------|------------|
| Kafka topics | MirrorMaker 2, bidirectional topology with asymmetric weights (primary-to-standby at full rate, reverse only for offset-sync topic under normal ops) | <10 s |
| QuestDB tables | Via Kafka — QuestDB on standby subscribes to the same ingest topic through MM2, re-materialises locally. Partition exports to Iceberg happen independently on each side. | Matches Kafka lag |
| Iceberg warehouse | MinIO site replication (async), bucket-level | <60 s |
| Postgres | Native streaming replication with synchronous_commit=remote_write for critical schemas (tenant metadata, model registry), async for label store | <5 s for sync schemas, <30 s for async |
| Qdrant | Snapshot shipping every 5 min + delta reconciliation | <5 min |

### DR drill procedure

Runs quarterly per SOC2 CC-series. Abbreviated:

1. **Pre-drill**: freeze all Airflow DAGs; capture Iceberg snapshot version + Postgres LSN across both DCs
2. **Cordon primary**: ArgoCD marks primary cluster unreachable from AWS side; simulated network partition
3. **Promote standby**: `failover-controller/uk-dc/` state machine:
   - Stop MirrorMaker 2 consumers on standby
   - Flush Kafka logs, advance consumer groups to the highest observed offset
   - Flip Postgres replication role (promote standby to primary)
   - Flip MinIO site role
   - Update internal DNS (edge Kafka bootstrap servers → new primary's listener)
   - Restart Airflow with the new broker config
4. **Validate**: smoke-test suite runs (synthetic transaction → ingest → QuestDB → Iceberg → template mine → eval → promote → Kargo release → rollback), measured end-to-end
5. **Restore**: reverse the promotion, re-sync original primary
6. **Record**: measured RPO, RTO, any data loss, any test failures → incident-report template

Target: RPO < 60 s, RTO < 15 min for planned drills; unplanned budget is <30 min RTO.

---

## GPU queue discipline

H100 pool (training) and H200 pool (inference) are separately managed by Volcano queues. Hard separation — training never runs on H200, inference never runs on H100, so a runaway training job cannot starve edge-feedback-critical eval.

Queue layout:

```
Volcano queues (H100 pool):
  training-default     (weight 100)   — regular tenant retrains
  training-bootstrap   (weight 30)    — new-tenant initial fine-tunes
  training-urgent      (weight 200, capability limit: 2 jobs) — drift-triggered or incident-response

Volcano queues (H200 pool):
  serving-vllm         (weight 150)   — vLLM multi-LoRA for internal and batch
  eval-judge           (weight 200, priority class: high) — LLM-as-judge debate
  engine-build         (weight 80)    — TRT-LLM compilation jobs
  batch-rescore        (weight 50)    — reprocessing historical data on schema changes
```

DRA (Dynamic Resource Allocation) is used to request fractional GPU / specific-GPU-within-node for the small jobs (engine builds, some eval tasks), preserving the big GPUs for training and batch inference.

---

## Observability of the UK DCs

- Prometheus scrape of everything: node_exporter, DCGM exporter, Kafka JMX, QuestDB internal metrics, MinIO metrics, Postgres exporter, Qdrant metrics, Airflow metrics
- Loki collects logs from all pods (Talos nodes log via `talos-log-shipper`)
- Tempo receives traces from any service that emits them (Airflow tasks, vLLM server, DAG operators)
- Forwarded aggregates push to AWS-side observability stack for the cross-tier SRE view
- Dedicated dashboards for: training run health, GPU utilisation by queue, Kafka replication lag, MinIO site-replication lag, Postgres replication lag, tenant resource consumption

Alerts mirror the `gpu-inference-dod.md` bar; see that doc for the critical list.

---

## AWS ↔ UK connectivity

Phase 1 decision (still pending per [PLAN.md](../../PLAN.md) Phase 1 open question):

- **Cloudflare Tunnel**: zero-trust overlay, no firewall changes on the UK side, easy to stand up, adds ~3-8 ms of latency
- **Site-to-site IPsec over public internet**: standard, cheap, operationally familiar to our team, adds ~2-4 ms
- **Direct Connect-equivalent via UK carrier to AWS `eu-west-2`**: lowest latency (<2 ms) and highest throughput, most expensive, longest to provision

Likely decision: start with Cloudflare Tunnel (fast to stand up, good zero-trust posture), migrate to carrier direct-connect when traffic or latency demands it. IPsec stays as an emergency fallback configuration.

Bandwidth requirement is not large — most of the traffic between UK and AWS is observability aggregates and ArgoCD pulls, not bulk data. Bulk data (training snapshots, Iceberg replication) stays within the UK inter-DC link.

---

## Inter-DC link (primary ↔ standby)

- Dark fibre between the two UK sites — ideally <30 km apart to keep latency at or below 1 ms and make synchronous Postgres replication viable for critical schemas
- 100 Gbps minimum, 400 Gbps preferred — sized for Kafka replication under peak plus MinIO site replication under backlog scenarios

Exact site selection and carrier is outside this doc (network engineering / procurement); requirement specified here.

---

## Hardware procurement note

The repo does not own hardware procurement. What this doc drives:

- What hardware types we expect at each tier (GPU models, NIC speeds, memory floors)
- What the Ansible roles assume in terms of BIOS capabilities and network topology
- What the Talos machine configurations target

Actual orders, vendor selection, rack + stack, power, cooling — all live in a separate operational workstream, but must match the assumptions here.
