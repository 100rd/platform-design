# SOC2 Control-to-Evidence Matrix — Bare-Metal (Talos) Estate

> **Status:** Design-target (WS-E of the **Bare-Metal ML Platform** plan,
> `docs/baremetal-ml-platform/IMPLEMENTATION_PLAN.md`). This is the bare-metal/Talos
> companion to [`soc2-control-matrix.md`](soc2-control-matrix.md) (AWS + GCP). It maps
> the SOC2 **Trust Services Criteria (2017 / CC-series)** to the controls on the
> **owned UK-DC Talos estate** — specifically the **immutable-OS posture** the cloud
> estates cannot offer.
>
> **ADRs:** [ADR-0040](../adrs/0040-soc-posture-and-oncall.md) (SOC posture + on-call,
> reused as decision of record), [ADR-0049](../adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
> (Talos foundation / multi-DC), [ADR-0050](../adrs/0050-talos-gpu-driver-system-extensions.md)
> (immutable-OS rationale), [ADR-0028](../adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md)
> (taxonomy). **plan/validate-only — apply-gated.**
>
> Nothing here is applied to real hardware (MOCK repo). The matrix describes the
> **intended control surface**; the **Talos posture controls are evidenced as concrete
> Terraform assertions** in [`terraform/modules/baremetal-org-policy`](../../terraform/modules/baremetal-org-policy/)
> (`output.posture_compliant` / `output.posture_violations`), which is the WS-E
> acceptance criterion: "the matrix references concrete Talos-config assertions."

## How to read this

- **Plane** — `Talos` (immutable-OS posture, asserted in `baremetal-org-policy`),
  `K8s` (ArgoCD/Helm/Kyverno admission plane), `Storage` (Rook-Ceph/MinIO/ESO-Vault),
  or `CI` (GitHub Actions supply chain, reused).
- **Status** — `evidenced` (control exists in-repo and produces an auditable signal),
  `partial`, `gap`, or `reused` (the AWS/GCP-estate control already covers it).
- **Evidence** — a repo artifact + the runtime signal it produces (a posture
  assertion result, an admission deny, a PolicyReport, a fired alert, a signed
  attestation).
- Every control carries the [ADR-0028](../adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md)
  `platform.system` taxonomy so evidence is attributable on the Grafana `$system` axis,
  cross-estate.

---

## CC1 — Control Environment

| Criterion | Control (repo artifact) | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC1.1 Org structure / accountability | ADR-0049/0050 ratification trail; ADR-0028 `platform.owner` on every Talos/K8s resource | — | ADR status footer; owner label per resource | evidenced |
| CC1.3 Authority & responsibility | `platform.owner=team-sec` on the posture/policy bundle; ML co-owned with `team-ml-platform` | Talos+K8s | owner label; on-call rotation | evidenced (WS-E) |
| CC1.4 Competence / on-call readiness | [oncall-rotation-escalation.md](../runbooks/oncall-rotation-escalation.md) + [bare-metal ML-incident runbook](../runbooks/ml-incident-runbook-baremetal.md) + [DC-failover runbook](../runbooks/uk-dc-failover.md) | — | PagerDuty schedule; tabletop record | evidenced (WS-E) |

## CC5 — Control Activities (policy enforcement)

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC5.1 Control selection (admission) | Kyverno tenant-isolation bundle (`apps/infra/baremetal-org-policy` + `terraform/modules/baremetal-org-policy`) — require `tenant={id}`, deny cross-ns SA | K8s | PolicyReport / admission deny | evidenced (WS-E) |
| CC5.2 Technology controls | Reuse `apps/infra/kyverno` + `apps/infra/gatekeeper` + `apps/infra/tetragon` on the Talos cluster | K8s | admission webhook + runtime events | partial (delivery apply-gated) |
| CC5.3 Policy-as-code deployment | Bundle delivered via GitOps (ArgoCD, manual-sync) + Terraform `kubectl_manifest` (apply-gated) | K8s | ArgoCD app sync status; plan diff | evidenced (WS-E) |

## CC6 — Logical & Physical Access

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC6.1 Access security / least privilege | **Talos no-SSH + mTLS machine API** posture assertion (`assert_no_ssh`, `assert_mtls_machine_api`); tenant-label policy | Talos+K8s | `posture_compliant` assertion; admission deny | evidenced (WS-E) |
| CC6.2 Credential issuance | mTLS client certs for `talosctl` (no static creds); ESO/Vault for app secrets | Talos+Storage | cert-gated API; ESO ExternalSecret | reused + evidenced |
| CC6.3 Least-privilege roles | `bm-deny-cross-ns-sa` policy; namespace-per-tenant | K8s | admission deny | evidenced (WS-E) |
| CC6.6 Boundary protection / attack surface | **Talos minimal OS** — no shell, no sshd, no package manager (`assert_no_ssh`, `assert_no_package_manager`) | Talos | posture assertion result | evidenced (WS-E) |
| CC6.7 Transmission protection | machine API mTLS-only (`assert_mtls_machine_api`); Cilium mTLS/WireGuard (ADR-0051) | Talos+K8s | posture assertion; CiliumNetworkPolicy | evidenced (WS-E) |
| CC6.8 Unauthorized-software prevention | **No package manager / writable `/usr`** (`assert_no_package_manager`); GPU driver as a **signed Talos system extension** (ADR-0050) | Talos | posture assertion; image-factory manifest | evidenced (WS-E) |

## CC7 — System Operations

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC7.2 Monitoring for anomalies | Reuse Prometheus/Thanos/Grafana + `talos-log-shipper`→Loki; DCGM/NCCL/BGP alerts (WS-D) | K8s | fired alert | reused |
| CC7.3 Incident evaluation | [bare-metal ML-incident runbook](../runbooks/ml-incident-runbook-baremetal.md) (drift storm, training-queue starvation) | — | PagerDuty incident + runbook | evidenced (WS-E) |
| CC7.4 Incident response | On-call rotation + escalation; [DC-failover runbook](../runbooks/uk-dc-failover.md) (`failover-controller`/`dns-monitor`) | — | failover event; tabletop record | evidenced (WS-E) |
| CC7.5 Recovery / availability | **KubePrism** in-cluster API HA (`assert_kubeprism_enabled`); standby DC; etcd snapshots | Talos | posture assertion; snapshot verify | evidenced (WS-E) |

## CC8 — Change Management

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| CC8.1 Change authorization & atomicity | **Talos A/B-partition immutable install + auto-rollback** (`assert_immutable_install`); apply-gated PRs; etcd snapshot before control-plane change | Talos+CI | posture assertion; PR + plan; snapshot | evidenced (WS-E) |

## A1 — Availability

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| A1.1 Capacity | Fixed GPU pools + workload scale-to-zero + Volcano queues (ADR-0054); risk R1 | K8s | KEDA/HPA + queue metrics | reused |
| A1.2 Backup & recovery | etcd snapshots; Rook-Ceph replicated pools + MinIO site-replication; CloudNativePG streaming; Velero | Talos+Storage | snapshot/restore; DR drill | partial |
| A1.3 Recovery testing | Quarterly DR drill per [uk-dc-failover.md](../runbooks/uk-dc-failover.md) + tabletop (the UK doc states the drill runs per SOC2 CC-series) | — | drill record | evidenced (WS-E) |

## C1 — Confidentiality

| Criterion | Control | Plane | Evidence signal | Status |
|---|---|---|---|---|
| C1.1 Confidential-data identification & residency | UK-resident data stays in-DC (ADR-0049 fully-isolated ML control plane); only metrics/log aggregates cross to AWS | Storage | data-flow boundary; ESO/Vault scope | evidenced (WS-E) |
| C1.2 Confidential-data disposal | Rook-Ceph pool deletion + Velero retention; Vault KV rotation | Storage | retention policy | partial |

---

## Coverage summary — what bare-metal WS-E changes

The cloud matrix had strong AWS/GCP-plane controls but **no immutable-OS posture
plane** — managed K8s hides the node OS. Bare-metal WS-E adds it:

| SOC2 area | Bare-metal gap closed | New artifact |
|---|---|---|
| CC6.1 / CC6.6 / CC6.8 | No OS-level attack-surface control (cloud nodes are mutable) | **Talos posture assertions** in `terraform/modules/baremetal-org-policy` (no-SSH, no-pkg-mgr, mTLS API) |
| CC5.1 / CC6.3 | No bare-metal tenant-isolation admission bundle | `apps/infra/baremetal-org-policy` (Kyverno tenant-label + cross-ns-SA deny) |
| CC8.1 | No atomic/immutable change-management control | Talos A/B-partition immutable-install assertion |
| CC7.5 / A1.2 | Self-operated control-plane HA + etcd backup not previously owned | KubePrism assertion + etcd-snapshot gate (plan §6) |
| CC1.4 / CC7.3 / CC7.4 | No bare-metal ML-incident / DC-failover on-call posture | [ml-incident-runbook-baremetal.md](../runbooks/ml-incident-runbook-baremetal.md) + reused [uk-dc-failover.md](../runbooks/uk-dc-failover.md) |
| ADR-0028 enforcement | AWS-shaped OPA rego did not gate `talos_*`/manifest resources | [`tests/opa/platform_tags_baremetal.rego`](../../tests/opa/platform_tags_baremetal.rego) (+ `_test.rego`) |
| (all) | No bare-metal auditor-facing control map | **this matrix** |

### Still-gap (tracked, not closed by WS-E)

- **CC4.1** — no continuous Talos-posture drift-detection daemon yet; posture is
  asserted at plan time, not continuously re-evaluated in-cluster (a follow-up;
  Tetragon covers runtime, not config drift).
- **A1.2 / C1.2** — Rook-Ceph + MinIO site-replication and Velero exist by design but
  a tested cross-DC restore + confidential-data-disposal procedure is partial.
- **CC5.2** — the Kyverno/Gatekeeper bundle delivery is apply-gated (manual sync), so
  in-cluster enforcement is design-target until applied.

> **Evidence-collection approach (ADR-0040 D3, reused):** evidence is pull-based and
> repo-anchored. An auditor request resolves to: (1) the ADR, (2) the Terraform module
> / ArgoCD app / OPA policy implementing it, (3) the `*.tftest.hcl` / `opa test` /
> `helm template` proving it behaves, and (4) the runtime signal (posture assertion
> result, admission deny, PolicyReport, fired alert). The Talos posture plane's
> distinctive evidence is the **`posture_compliant` boolean + `posture_violations`
> list** from `baremetal-org-policy`, citable per SOC2 family via `posture_soc2_map`.
