# ADR-0030: Bottlerocket as the EKS node operating system

- Status: **Accepted** — research-backed + doc-verified; the
  `karpenter-nodepools` Terraform module already defaults to `Bottlerocket`,
  so this ADR ratifies and documents the in-source decision and extends it to
  the standalone Karpenter `EC2NodeClass` manifests/templates.
- platform-design status: **synced (module) / pending (manifests)** —
  `terraform/modules/karpenter-nodepools` defaults `ami_family = "Bottlerocket"`
  and renders `bottlerocket@latest`; the example `kubernetes/karpenter/*.yaml`
  manifests and `*.tpl` templates are updated by this change to match.
- Date: 2026-06-08
- Authors: platform-team, security
- Related issues: epic #252; netkit/kernel prereq #272 (ADR-0019)
- Supersedes: (none)
- Superseded by: (none)
- Provenance: **doc-verified** — Bottlerocket EKS variant/kernel matrix verified
  against the Bottlerocket project documentation and the same authoritative
  sources cited by ADR-0019 (kernel-floor verification against
  `awslabs/amazon-eks-ami` and the Bottlerocket variant docs); Karpenter
  `EC2NodeClass` `amiSelectorTerms` alias semantics verified against the
  Karpenter `karpenter.k8s.aws/v1` API. The Bottlerocket userData TOML
  (`[settings.kubernetes]`) and two-volume layout encoded here match the
  already-authored, doc-verified `karpenter-nodepools` module.

## Context

The platform runs **EKS** with the **Cilium 1.19** data plane (ADR-0003,
kube-proxy-replacement, WireGuard, Hubble) and provisions all node capacity via
**Karpenter** `NodePool` / `EC2NodeClass` CRDs (ADR-0007). Node capacity is
shaped almost entirely from spot, Graviton-first instance families.

The node **operating system** has so far been left at the EKS default
(Amazon Linux 2023, AL2023). A general-purpose Linux distribution carries a
large host attack surface that the platform does not use: a package manager, an
SSH daemon, a shell, a writable root filesystem, and the full set of system
services. Each of those is host attack surface and patch-management burden that
sits *below* the container and is therefore invisible to in-cluster controls
(Kyverno/VAP — ADR-0020, Tetragon — ADR-0019). For a security-forward platform
whose threat model emphasises **host attack-surface reduction**, the node OS is
the missing layer.

Two further constraints make this timely:

1. **netkit prerequisite (ADR-0019 / #272).** ADR-0019 adopts Cilium **netkit
   device mode** as a pilot. netkit requires **kernel ≥ 6.8**. Bottlerocket EKS
   variants `aws-k8s-1.33`/`1.34`/`1.35` ship **kernel 6.12**, and `aws-k8s-1.36`
   ships **kernel 6.18** — all comfortably above the 6.8 floor. Choosing
   Bottlerocket therefore also **unblocks netkit** (and keeps us above the floor
   on the same LTS-kernel track as the AL2023 standard AMI, which also ships
   6.12).
2. **Compliance and GPU lanes.** Some workloads have **FIPS 140-3** requirements,
   and future inference/template-mining work may need **NVIDIA GPUs**.
   Bottlerocket ships **dedicated FIPS and NVIDIA variants**, so both lanes are
   addressable with the same node-OS strategy rather than a bespoke AMI.

Options for the node OS:

1. **Amazon Linux 2023 (AL2023)** — the EKS default; general-purpose, mutable,
   package-managed.
2. **Bottlerocket** — a minimal, **immutable**, container-purpose Linux built by
   AWS: **read-only root**, **SELinux-enforcing** by default, no SSH/shell, API-
   and TOML-driven configuration, atomic image-based updates, and a deliberate
   **two-volume layout** (a small OS volume + a separate data volume for
   container storage).
3. **Custom hardened AL2023 AMI** — bake a CIS-hardened AL2023 image ourselves.

## Decision

Adopt **Bottlerocket as the EKS node operating system** for radical host
attack-surface reduction. Concretely:

1. **Default `ami_family = "Bottlerocket"`** in the `karpenter-nodepools`
   Terraform module (already the case) and set
   `amiSelectorTerms: [{ alias: bottlerocket@latest }]` on the standalone
   `EC2NodeClass` manifests/templates, with the **AL2023 alias kept as a
   commented fallback** for the VPC-CNI escape hatch.
2. Use Bottlerocket's **two-volume block device layout** on every Bottlerocket
   `EC2NodeClass`: a small **OS** volume at `/dev/xvda` and a separate
   **data** volume at `/dev/xvdb` for container images/ephemeral storage, both
   `gp3` and **encrypted**.
3. Configure nodes through Bottlerocket **userData TOML**
   (`[settings.kubernetes] cluster-name = …`, plus `node-labels` /
   `node-taints`) rather than a bash bootstrap — the module already emits this.
4. Rely on Bottlerocket's **security posture defaults**: **SELinux-enforcing**,
   **read-only root filesystem**, no SSH daemon, no shell, no package manager.
   Administrative access is via the API/control container only, kept disabled in
   normal operation.
5. **FIPS variant** for workloads/node pools with FIPS 140-3 requirements;
   **NVIDIA variant** for any GPU node pool. Both are selected via the variant in
   the `bottlerocket@latest` alias / `amiSelectorTerms` for those pools.

A reviewer can check conformance by confirming that Karpenter `EC2NodeClass`
resources select `bottlerocket@latest` (not `al2023@latest`), carry the
two-volume `blockDeviceMappings`, and configure nodes via `settings.kubernetes`
TOML userData.

## Alternatives considered

### Alternative A: Amazon Linux 2023 (status quo default)
The EKS-default general-purpose distribution. It is well-understood and ships
kernel 6.12 (so it would *also* satisfy the netkit floor).
Rejected as the **default** because: it carries a large, mutable host attack
surface (shell, SSH, package manager, writable root) that the platform never
uses; it is not SELinux-enforcing out of the box; and patching is package-based
rather than atomic/image-based. It is retained as a **commented fallback** for
the narrow VPC-CNI escape hatch.

### Alternative B: Custom hardened AL2023 AMI
Bake a CIS-hardened, minimised AL2023 image in-house.
Rejected because: it recreates — at our own cost and patch cadence — much of what
Bottlerocket already provides (immutability, SELinux-enforcing, minimal surface),
adds an AMI-pipeline maintenance burden, and still ships a mutable root and a
shell. Worse security posture for more work.

### Alternative C: Status quo (no explicit node-OS decision)
Leave the node OS implicit/defaulted and undocumented.
Rejected because: the node OS is a first-class part of the host threat model and
a hard prerequisite for netkit (#272); leaving it implicit means the
attack-surface-reduction and FIPS/GPU lanes are never deliberately chosen, and
the `bottlerocket@latest` default already in source goes undocumented.

## Consequences

### Positive
- **Radical host attack-surface reduction:** no SSH, no shell, no package
  manager, **read-only root**, **SELinux-enforcing** — the bulk of host-level
  attack surface is removed by construction.
- **Unblocks netkit (ADR-0019 / #272):** Bottlerocket `aws-k8s-1.33+` ships
  **kernel 6.12** (`aws-k8s-1.36` ships 6.18), above the netkit **≥ 6.8** floor.
- **Atomic, image-based updates** with rollback, instead of per-package drift —
  a better fit for immutable, Karpenter-churned, mostly-spot fleets.
- **Faster, leaner boots** from a minimal image; good fit for Cilium (native
  support) and bursty spot capacity.
- **Compliance & GPU lanes covered:** **FIPS** variant for FIPS 140-3 workloads,
  **NVIDIA** variant for GPU node pools — same node-OS strategy, no bespoke AMI.
- **Declarative, API/TOML configuration** (`settings.kubernetes`) — no bash
  bootstrap scripts to drift or audit.

### Negative
- **Operational model change:** no SSH/shell debugging; operators must use the
  Bottlerocket **control/admin container** (kept disabled by default) or
  node/kubectl-level tooling. Some host-level troubleshooting habits change.
- **Two-volume layout** (`/dev/xvda` OS + `/dev/xvdb` data) must be modelled on
  every `EC2NodeClass`; getting it wrong starves container storage.
- **DaemonSet/agent compatibility:** node agents that assume a writable root,
  host package manager, or specific host paths may need Bottlerocket-aware
  configuration (e.g. host-path differences).
- **Variant management:** FIPS and NVIDIA are separate variants — node pools must
  pin the correct variant rather than a single universal image.

### Risks
- **Read-only root / SELinux-enforcing** can break privileged or host-mutating
  workloads. Mitigated by validating Tetragon/Cilium/observability DaemonSets on
  Bottlerocket before fleet-wide rollout, and by piloting on a fresh node group.
- **Variant/kernel drift:** `bottlerocket@latest` tracks the latest variant.
  Mitigated by Karpenter `disruption` budgets and the ability to pin a specific
  variant alias if a regression appears.
- **netkit coupling:** netkit has no in-place veth→netkit migration (ADR-0019);
  it must be piloted on a **fresh** Bottlerocket node group, not an in-place flip.

## Rollout notes

- The `karpenter-nodepools` module already defaults `ami_family = "Bottlerocket"`
  and emits `bottlerocket@latest`, the two-volume `blockDeviceMappings`, and the
  `settings.kubernetes` TOML userData — this ADR ratifies that and aligns the
  standalone example manifests/templates.
- **Pilot on a fresh node group** (consistent with the netkit pilot in
  ADR-0019); do not attempt an in-place AL2023→Bottlerocket conversion of an
  existing node.
- Keep the **AL2023 alias as a commented fallback** in the `EC2NodeClass`
  manifests for the VPC-CNI escape hatch.
- Select the **FIPS** variant for FIPS-scoped pools and the **NVIDIA** variant
  for GPU pools when those pools are introduced.

## References

- Bottlerocket OS (variants, kernel, security posture):
  <https://bottlerocket.dev/> and
  <https://github.com/bottlerocket-os/bottlerocket>
- Bottlerocket settings (`settings.kubernetes`):
  <https://bottlerocket.dev/en/os/latest/#/api/settings/>
- Karpenter `EC2NodeClass` (`amiFamily` / `amiSelectorTerms` alias
  `bottlerocket@latest`):
  <https://karpenter.sh/docs/concepts/nodeclasses/>
- ADR-0003 (Cilium over AWS VPC CNI), ADR-0007 (Karpenter),
  ADR-0019 (Cilium/eBPF harvest — netkit kernel floor, #272),
  ADR-0020 (Kyverno/VAP).
