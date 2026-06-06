# ADR-0019: Harvest unused Cilium / eBPF capabilities (OBI tracing, Hubble UI, Tetragon, ClusterMesh)

- Status: **Proposed** — research-backed; decision to ratify, not yet
  implemented.
- platform-design status: **pending** — Cilium 1.19 is deployed but none of the
  capabilities below are turned on in this repo.
- Date: 2026-06-06
- Authors: platform-team, security
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)

## Context

The platform runs **Cilium 1.19** with kube-proxy-replacement, WireGuard
transit encryption, Hubble (flow visibility), Gateway API (ADR-0009), but several
of the eBPF capabilities the same data plane already ships are **left unused**. We
are paying for the eBPF data plane without harvesting its observability and
runtime-security yield, and Tempo is **deployed but currently unfed** (no trace
producer wired to it). This ADR decides which capabilities to turn on now, which to
pilot, and which to defer.

## Decision

1. **OBI/Beyla eBPF auto-instrumentation — ADOPT.** Deploy Grafana Beyla / OBI as a
   **DaemonSet** that auto-instruments HTTP/gRPC at the kernel and exports **OTLP**
   to the **already-deployed-but-unfed Tempo** — **zero application changes**. This
   gives the platform distributed traces (and RED metrics via Tempo's
   metrics-generator) without touching service code.
2. **Hubble UI — ADOPT.** Flip `enable_hubble_ui = false` → `true`. Hubble flow
   data is already collected; the UI is the missing operator surface for
   network-flow and policy debugging.
3. **Tetragon (runtime security) — ADOPT (observe-mode first).** Deploy Tetragon as
   a **standalone DaemonSet**, starting in **observe mode** (process/file/network
   events), promoting to **enforce** once policies are tuned. Chosen over Falco
   because Tetragon rides the **same eBPF stack** as Cilium and can **enforce**
   (kill/block), not just alert.
4. **Cilium ClusterMesh — PILOT.** ClusterMesh is **scaffolded but
   `enable_clustermesh = false`**. Pilot it **once a second cluster exists**, with a
   **distinct cluster id/name**, a **shared CA**, and **non-overlapping PodCIDRs**
   routed over the existing Transit Gateway (ADR-0005).

**Deferred** (explicitly not now):
- **netkit** — needs **kernel ≥ 6.8**; nodes are **AL2023 (kernel 6.1)**. Revisit
  on a kernel bump.
- **SPIFFE mutual auth** — **WireGuard already covers transit encryption**, so the
  marginal benefit does not justify the operational cost today.

A reviewer can check conformance by confirming the Beyla/OBI DaemonSet exports OTLP
to Tempo, `enable_hubble_ui = true`, a Tetragon DaemonSet runs in observe mode, and
ClusterMesh stays off until a second cluster is provisioned.

## Alternatives considered

### Alternative A: Leave the capabilities off (status quo)
Keep running Cilium with these features dark.
Rejected because: Tempo sits unfed, network debugging has no UI, and we have no
runtime-security signal — all available from the data plane we already operate.

### Alternative B: Falco instead of Tetragon for runtime security
Use Falco for syscall-level detection.
Rejected as default because: Falco alerts but does not enforce, and adds a second
eBPF/driver stack alongside Cilium. Tetragon reuses Cilium's stack and can enforce
— fewer moving parts, stronger control.

### Alternative C: App-SDK instrumentation instead of OBI/Beyla
Instrument each service with an OpenTelemetry SDK.
Rejected as the starting point because: it requires per-service code changes across
many languages. eBPF auto-instrumentation feeds Tempo immediately with zero app
changes; SDK instrumentation can layer on later where deeper spans are needed.

## Consequences

### Positive
- Tempo finally gets fed (traces + RED metrics) with zero app changes — and that
  RED-metrics stream is the analysis signal ADR-0021's Kargo gates consume.
- Operators get the Hubble UI for flow/policy debugging.
- Runtime-security signal (observe) with a path to enforcement, on the existing
  eBPF stack.
- ClusterMesh readiness validated before it is load-bearing.

### Negative
- Three new DaemonSets to operate (Beyla/OBI, Tetragon) plus the Hubble UI surface.
- eBPF instrumentation adds per-node overhead; must be sized.

### Risks
- Tetragon in enforce mode could kill legitimate processes. Mitigated by
  **observe-first** and per-policy promotion.
- Beyla/OBI cardinality/overhead on busy nodes. Mitigated by sampling and scoping
  instrumented namespaces.
- ClusterMesh with overlapping PodCIDRs would break routing. Mitigated by the
  explicit non-overlapping-CIDR + shared-CA + distinct-id pilot checklist.

## Implementation notes

- **OBI/Beyla:** DaemonSet → OTLP exporter → Tempo endpoint; enable Tempo's
  metrics-generator to produce RED metrics (consumed by ADR-0021).
- **Hubble UI:** Helm value `enable_hubble_ui = true`.
- **Tetragon:** standalone DaemonSet; ship TracingPolicies in **observe** first,
  flip to **enforce** per policy after tuning.
- **ClusterMesh:** keep `enable_clustermesh = false` until cluster #2; then distinct
  cluster id/name, shared CA, non-overlapping PodCIDRs over TGW.
- **Deferred:** netkit (kernel ≥ 6.8 vs AL2023 6.1); SPIFFE mutual auth (WireGuard
  already encrypts transit).

Effort: **L–M**.

## References

- Grafana Beyla / OpenTelemetry eBPF (OBI):
  <https://grafana.com/docs/beyla/latest/>
- Tetragon: <https://tetragon.io/>
- Cilium ClusterMesh:
  <https://docs.cilium.io/en/stable/network/clustermesh/clustermesh/>
- Related: ADR-0003 (Cilium CNI), ADR-0005 (Transit Gateway), ADR-0009 (Cilium
  Gateway API), ADR-0021 (Kargo — consumes the Tempo RED metrics)

---
*Research-backed — 2026 platform modernization; grounded in infra@572b54d /
argocd@c364c6c. Proposed: decision to ratify, not yet implemented in
platform-design.*
