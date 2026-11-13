# Challenge 2 — Prove It's the Cluster We Declared

> Leadership asks: "Can we be **100% sure** every Kubernetes cluster we deploy meets our
> requirements?" Answer them honestly, then build the closest thing to yes.

## Situation

The fleet (see [`platform-design.excalidraw`](../../architecture/platform-design.excalidraw)):

| Cluster family | Count | Built by | Notes |
|---|---|---|---|
| EKS workload clusters | 2 regions × dev/staging/prod/dr | Terragrunt stacks ([SPEC-03](../../../specs/SPEC-03-compute-clusters.md)) | Cilium-only CNI, Bottlerocket, Karpenter, Pod Identity |
| EKS GPU inference | 2 regions | Terragrunt + GitOps | up to 5 000 nodes, DRA, Volcano |
| Bare-metal (UK edge) | 2 DCs | Talos ([ADR-0049](../../adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md)) | Cilium BGP, Rook-Ceph |
| GKE ML | 2 regions | Terraform ([ADR-0036](../../adrs/0036-gke-ml-infra-parity-multiregion.md)) | GPU node pools |

Requirements are spread across ADRs and specs. A sample of eight:

| ID | Requirement | Source |
|---|---|---|
| R1 | API endpoint is private in staging/prod; public allow-list never `0.0.0.0/0` | [ADR-0010](../../adrs/0010-eks-public-endpoint-cidr-allowlist.md) |
| R2 | Cilium is the only CNI; `vpc-cni` absent | [ADR-0003](../../adrs/0003-cilium-over-aws-vpc-cni.md) |
| R3 | Node-to-node traffic is encrypted (WireGuard) | SPEC-03 §2.2 |
| R4 | Nodes run an immutable OS | [ADR-0030](../../adrs/0030-bottlerocket-node-os.md) |
| R5 | Default-deny network policy exists and DNS + apiserver still work | SPEC-03 §8 |
| R6 | Only signed images from trusted CI run | [ADR-0016](../../adrs/0016-tier1-supply-chain-hardening.md), [ADR-0020](../../adrs/0020-kyverno-and-vap-policy-engine.md) |
| R7 | Workloads get AWS identity via Pod Identity; no SA has both IRSA and Pod Identity | [ADR-0018](../../adrs/0018-eks-pod-identity-as-default-workload-identity.md) |
| R8 | Cluster-creator admin is removed after bootstrap; humans come in via SSO access entries | SPEC-03 §8 |

How it's checked today: `terragrunt stack plan` must be clean (with `mock_outputs` for
unresolved dependencies), policy scans run on the IaC, and SPEC-03 §8 has a manual
**acceptance checklist** of `kubectl get …` and `cilium status` lines run once after a rebuild.

### Facts and numbers you may use

| Fact | Value |
|---|---|
| Clusters in the fleet | ~20 (8 EKS workload, 2 EKS GPU, 2 bare-metal, 2 GKE, plus sandboxes) |
| Nodes | ~300 per EKS workload cluster; up to 5 000 per GPU cluster; ~120 per bare-metal DC |
| Node churn | Karpenter replaces ~8% of nodes per day (consolidation, Spot, `expireAfter`) |
| AMI selection | `EC2NodeClass` uses an alias that follows the latest Bottlerocket release |
| Helm releases per workload cluster | ~60 platform charts, synced by Argo CD |
| Break-glass use | 3 times last quarter; entries were added from the AWS console |
| Policy engines installed | Kyverno, Gatekeeper and ValidatingAdmissionPolicy (all three) |
| How SPEC-03 §8 is run today | Once, by hand, after a rebuild; output pasted into the PR |
| Who may run checks | Anything you design; but nothing may have cluster-admin in prod except break-glass |

## Your task

1. **Answer leadership.** What can and can't be known with certainty about a running cluster?
   Rewrite "100% sure" into a promise you'd sign.
2. **Design the verification system** that carries that promise, from declaration to retirement:
   - what a "requirement" is as data (not prose);
   - where each requirement is checked — before apply, at apply, right after, continuously;
   - what evidence is produced, who produces it, where it lives, how long it stays valid;
   - what happens when a cluster stops meeting a requirement.
3. **Fill the evidence matrix** for R1–R8: `requirement → strongest evidence you can get →
   how that evidence could be wrong → how you'd detect that`.

## Deliverable

- The promise to leadership, in three sentences.
- A diagram or list of the verification pipeline.
- The R1–R8 evidence matrix.
- A response matrix: for each requirement, what happens at 03:00 when a **prod** cluster fails
  it (page / block deploys / auto-remediate / ticket / nothing) — and why it differs.

## Things worth thinking about

- What does a clean `plan` with mock outputs actually prove?
- Is "the config says WireGuard is on" the same claim as "traffic is encrypted"?
- Your checks pass on every cluster for six months straight. Good news or bad news?
- Who verifies a cluster — and could a cluster lie to its own verifier?
