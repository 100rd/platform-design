# SPEC-03 — Compute Clusters (EKS + Karpenter + Cilium + KEDA)

> Portable reverse-engineering of the platform's Kubernetes compute layer. A competent
> platform team can rebuild this compute plane for a new client from this document alone.
> Placeholders (`{{...}}`) follow `SPEC-00-overview.md`; spec-local ones are registered in
> §5. All values are sanitized per `CONVENTIONS.md` (no real account IDs, ARNs, IPs, hosts).

---

## 1. Scope & non-goals

This spec covers the **Kubernetes compute plane**: the EKS control plane, node lifecycle
(Karpenter-driven, Bottlerocket-based), the CNI/dataplane (Cilium — eBPF, ENI mode), the
in-cluster autoscaling stack (Karpenter for nodes; KEDA + HPA + optional Watermark
PodAutoscaler for pods), the cluster-critical add-on baseline, workload identity (EKS Pod
Identity), and the **multi-cluster boundary** decisions (which workloads get a dedicated
cluster and why). It defines cluster sizing/parameterization, the upgrade strategy, and the
deployment ordering that lets a Cilium-on-EKS bring-up succeed on the first apply.

**Non-goals** (owned by sibling specs): the AWS Organization/account/OU landing zone,
Terragrunt skeleton, remote state, and version-pin machinery (SPEC-01 Foundation);
VPC/subnet/Transit-Gateway/ClusterMesh L3 fabric and inter-VPC security (SPEC-02
Network & DNS); SCP/RCP/GuardDuty/SecurityHub contents, SSO permission-set *definitions*,
and secrets management (ESO/KMS) (SPEC-05 Security — this spec consumes them); GitOps
delivery (ArgoCD app-of-apps, the ApplicationSet `cluster_role` label scheme, Kargo, Argo
Rollouts, concrete KEDA `ScaledObject`s) (SPEC-04 Delivery); observability backends
(Prometheus/Thanos/Loki/Hubble-UI wiring) (SPEC-07 Observability); and the GPU/ML and
bare-metal compute planes, which **reuse** this plane's EKS+Karpenter+Cilium patterns but are
specified separately (SPEC-10 ML workloads). This spec references those boundaries where the
compute plane depends on them.

---

## 2. Architecture

### 2.1 Component overview

```
                         ┌─────────────────────────────────────────────┐
                         │  EKS control plane (managed)                │
                         │  • private API endpoint (public = fail-closed)│
                         │  • KMS envelope encryption for secrets       │
                         │  • 5 control-plane log types → CloudWatch    │
                         │  • authentication_mode = API_AND_CONFIG_MAP  │
                         │  • EKS Access Entries ← SSO permission sets  │
                         └───────────────┬─────────────────────────────┘
                    OIDC (IRSA, bootstrap) │ + EKS Pod Identity (workloads)
        ┌────────────────────────────────┼────────────────────────────────┐
   ┌────▼─────┐  system managed NG    ┌───▼───────┐  Karpenter NodePools     │
   │ system   │  (Bottlerocket,       │ workload  │  (Bottlerocket)          │
   │ NodeGroup│  tainted until CNI)   │ nodes     │  x86 / arm64 / c-series /│
   └────┬─────┘                       └───┬───────┘  spot-flexible / cde …    │
        │ CoreDNS, Cilium agents,         │ application workloads            │
        │ Karpenter ctrl, KEDA, ESO       │                                  │
        └───────────────┬─────────────────┘                                  │
                        │                                                    │
     ┌──────────────────▼───────────────────────────────────────────────┐   │
     │ Cilium CNI (kube-system) — replaces AWS VPC CNI                   │   │
     │  • IPAM=eni (VPC-routable pod IPs), routingMode=native (no overlay)│   │
     │  • kube-proxy replacement (eBPF) — OFF on general, ON for GPU/BM  │   │
     │  • WireGuard transparent encryption; SPIRE mutual-auth available  │   │
     │  • Hubble · Maglev LB · BBR bandwidth mgr · local-redirect policy │   │
     │  • Cilium Gateway API (primary L7)   · optional ClusterMesh       │   │
     │  • default-deny CiliumClusterwideNetworkPolicy baseline          │   │
     └──────────────────────────────────────────────────────────────────┘   │
     ┌──────────────────────────────────────────────────────────────────┐   │
     │ Autoscaling: Karpenter (nodes) · KEDA (events) · HPA (CPU/mem)    │   │
     │             · Watermark PodAutoscaler (optional, off default)     │   │
     └──────────────────────────────────────────────────────────────────┘───┘
```

### 2.2 Design invariants

- **No AWS VPC CNI, no Fargate, no Istio.** Cilium is the sole CNI (the `vpc-cni` managed
  add-on is intentionally *absent*). All nodes are EC2 (a small managed "system" group +
  Karpenter). The mesh is **sidecarless**: east-west security is Cilium eBPF + WireGuard
  (transparent transit encryption), with optional Cilium+SPIRE mutual auth; L7 ingress is
  **Cilium Gateway API** (ADR-0009), Envoy Gateway secondary for advanced L7 (ADR-0025).
  Istio appears only in design docs and a dev experimental stack — no Istio module ships.
- **Bottlerocket node OS** (ADR-0030): immutable, read-only-root, SELinux-enforcing, no
  SSH/shell/package-manager; API/TOML-configured; kernel 6.12 on `aws-k8s-1.33/1.34/1.35`.
- **Two node tiers per cluster.** A tainted managed **system** group bootstraps
  cluster-critical workloads (CoreDNS, Cilium agents, Karpenter controller, KEDA, ESO);
  Karpenter provisions everything else just-in-time.
- **Karpenter replaces Cluster Autoscaler** (ADR-0007/0046): no autoscaling ASG node
  groups; Karpenter picks instance type/size/AZ/capacity-type per pod requests, sub-~60 s,
  and consolidates aggressively.
- **Private-by-default control plane** (ADR-0010): `endpoint_public_access` fail-closed
  (`_cidrs = []`); a per-account CIDR allow-list is the *only* source of public reach and
  must never be `0.0.0.0/0` in staging/prod.
- **EKS Pod Identity is the default workload identity** (ADR-0018); IRSA (OIDC) is retained
  only for bootstrap components that need identity before/around the agent (Cilium
  operator, Karpenter controller) and for Fargate (which Pod Identity does not support).
- **Everything is a Terragrunt unit.** Each concern (`eks`, `cilium`, `karpenter-iam`,
  `karpenter-controller`, `karpenter-nodepools`, `keda`, `hpa-defaults`, `wpa`) is its own
  unit, composed by a `terragrunt.stack.hcl` and ordered by `dependency` blocks.

### 2.3 Deployment ordering (per cluster)

The mainline `platform` stack composes catalog units in dependency order:

```
vpc, secrets ─▶ eks ─▶ cilium ─▶ karpenter-iam ─▶ karpenter-controller ─▶ karpenter-nodepools
               eks ─▶ keda / hpa-defaults / wpa / monitoring        rds ← (vpc, eks, secrets)
```

Cilium lands **after** the control plane but **before** Karpenter NodePools (nodes need a
working CNI to reach `Ready`). On strict greenfield bring-ups the `eks` unit is split into
`eks-cluster` + `eks-nodes` (see the sandbox `minimal-platform` stack) so Cilium installs
between control-plane creation and first node join — this breaks the CNI chicken-and-egg
cycle (§7).

---

## 3. Decision record

Cite as `ADR-NNNN <title>` — numbers refer to this estate's `docs/adrs/`. Statuses shown as
observed (`Accepted` = live; `Proposed` = plan/validate-only, apply-gated).

| Decision | Rationale | Trade-off accepted | Source ADR (status) |
|---|---|---|---|
| **Cilium (eBPF) replaces AWS VPC CNI on all EKS clusters**; `vpc-cni` add-on disabled; policy = `CiliumNetworkPolicy`/`CiliumClusterwideNetworkPolicy`. Run **ENI IPAM** so pods keep VPC-routable IPs. | eBPF avoids iptables overhead (~20–30% lower latency in source benchmarks); transparent WireGuard pod-to-pod encryption without sidecars; L3/L4/L7 DNS-aware policy; Hubble flow logs/service maps; ClusterMesh for cross-region. | Team learns Cilium CRDs; loses VPC-CNI security-groups-for-pods (policy moves entirely to Cilium); operator upgrades decouple from the EKS add-on lifecycle (mitigated by pinning the chart + gated upgrades). Kernel floor **5.10+** (met by AL2023/Bottlerocket). | ADR-0003 (Accepted) |
| **Karpenter replaces Cluster Autoscaler**; capacity shaped by `NodePool` + `EC2NodeClass` (pinned **v1 API**). | Bin-packs from real pod requests across a broad instance set, spot-prioritised; provisions in <~60 s via direct EC2 API; active consolidation; disruption budgets absorb rolling updates + spot interruptions; Graviton/arm64 defaults trivial. | EKS-specific (not portable); must author NodePool/EC2NodeClass CRDs; **no ASG lifecycle hooks / warm pools**; needs proper PDBs on workloads; a small managed system group still hosts the controller. | ADR-0007 (Accepted); ADR-0046 (Proposed) |
| **Bottlerocket node OS**; `ami_family="Bottlerocket"`, `amiSelectorTerms:[{alias:bottlerocket@latest}]`, AL2023 a commented fallback. | Immutable, read-only root, SELinux, no SSH/shell/pkg-mgr, atomic image updates; kernel 6.12 unblocks netkit (≥6.8); dedicated FIPS + NVIDIA variants. | No SSH/shell debugging (use disabled-by-default admin container); two-volume `/dev/xvda`+`/dev/xvdb` layout on every EC2NodeClass; privileged/hostPath DaemonSets may need Bottlerocket-aware config; **no in-place AL2023→Bottlerocket conversion** (roll fresh nodes). | ADR-0030 (Accepted) |
| **Spot-first, on-demand-fallback**; per-pool `spot_percentage`; reliability-critical tiers pin 0% spot. | Cost: default pools run 70–100% spot; consolidation + diversity dodge interruptions. | Spot reclaim needs interruption-tolerant workloads + PDBs + the SQS interruption queue; capacity-type is a per-pool knob teams must set correctly. | ADR-0046 (Proposed) |
| **EKS Pod Identity as default workload identity**; `PodIdentityAssociation` (SA↔role), trust = `pods.eks.amazonaws.com` with `sts:AssumeRole`+`sts:TagSession`; least-privilege via **ABAC on 6 injected session tags**. IRSA → legacy. | IRSA roles bake the OIDC issuer into the trust policy (per-cluster, non-portable) and multiply roles; the `eks-pod-identity-agent` add-on is already installed; one role reused across clusters; cross-account via `targetRoleArn`. | A coexistence window (two identity mechanisms); ABAC is condition-heavy (wrong-tag-key bugs); **never** put IRSA + Pod Identity on one SA (undocumented precedence); **Fargate unsupported**; Karpenter nodes must run the agent DaemonSet before cutover. | ADR-0018 (Implemented) |
| **Harvest latent Cilium/eBPF features** on the 1.19 dataplane: kube-proxy replacement, Maglev LB, BBR bandwidth mgr, local-redirect, Hubble metrics, Tetragon (observe-first), OBI/Beyla tracing; pilot ClusterMesh + netkit. | Already paying for the eBPF dataplane; Hubble UI is the missing operator surface; Tetragon (eBPF, can enforce) chosen over Falco. | More Cilium surface to run; per-node eBPF overhead; **netkit is beta, no in-place veth→netkit migration** (roll fresh nodes, kernel ≥6.8); SPIFFE mutual auth **deferred** (WireGuard already covers transit). | ADR-0019 (Partial) |
| **Private EKS endpoint + parameterized public CIDR allow-list**; `public_access` opt-in, `_cidrs` fail-closed `[]`. | Fail-closed default; CI may open dev narrowly; prod/staging stay private-only; the CIDR is visible in review and tightenable without a module change. | Operators reach private clusters via VPN/bastion/SSM; dev's explicit `["0.0.0.0/0"]` is a documented dev-only accepted risk. | ADR-0010 (Accepted) |
| **Cilium Gateway API = primary L7 ingress** (`gatewayAPI.enabled=true`, `GatewayClass cilium`); **Envoy Gateway = secondary** for rate-limit / ext-proc (AI-gateway) / WASM / circuit-breaking. | Enabling Gateway API adds a watch loop to the existing operator (zero extra pods); LBs provisioned per `Gateway` (not per `Ingress` → lower ALB sprawl); traffic visible in Hubble; Envoy is additive (own dataplane, not a CNI, no conflict). | Gateway API CRDs must install before the Cilium release (sync-wave ordering) or upgrades fail; not all NGINX Ingress annotations map; two ingress dataplanes can drift (pin both). | ADR-0009 (Accepted); ADR-0025 (Implemented) |
| **Dedicated clusters per specialized workload class** (general `platform`, dev `agent-cluster`, `blockchain` HPC, `gpu-analysis`, prod `gpu-inference`, sandbox `minimal-platform`) rather than one shared cluster. | Blast-radius isolation + capacity/tenancy separation (spot vs on-demand, GPU, PCI-CDE, low-latency HPC). GPU foundation is a greenfield `aws-eks-gpu-*` module set at parity with the GKE etalon. | More clusters to run/upgrade; cross-cluster traffic needs ClusterMesh/Gateway; higher baseline cost; two parallel GPU estates in-repo (`aws-eks-gpu-*` vs legacy `gpu-inference-*`). | ADR-0044 (Proposed); estate-wide pattern |
| **Break-glass IAM users are destroy-protected** (`prevent_destroy=true` + `force_destroy=false`). | Last-resort access when SSO is down must survive a stray `terraform destroy`/`moved` at *plan* time. | `terraform destroy` on such an account always fails for that user until the lifecycle block is removed via a reviewed PR (intended friction). *(Foundation/IAM concern — see SPEC-01; noted here because it gates cluster admin access.)* | ADR-0011 (Accepted) |

---

## 4. Implementation blueprint

### 4.1 Directory layout

```
terraform/modules/
  eks/                     # wraps terraform-aws-modules/eks/aws — mainline cluster
  eks-agent-cluster/       # EKS control plane with ZERO node groups (Karpenter-only)
  eks-addons/              # managed add-on baseline
  cilium/ gpu-inference-cilium{,-advanced,-encryption}/ baremetal-cilium-lb/
  karpenter/               # controller Helm release (custom module)
  karpenter-nodepools/     # NodePool + EC2NodeClass CRDs (per-pool, for_each)
  keda/ hpa-defaults/ wpa/ # pod autoscaling
catalog/units/{eks,cilium,karpenter-iam,karpenter-controller,karpenter-nodepools,keda,hpa-defaults,wpa}/
catalog/stacks/platform/terragrunt.stack.hcl        # composes the units
terragrunt/<env>/<region>/platform/terragrunt.stack.hcl   # live composition
terragrunt/<env>/account.hcl                         # ALL sizing knobs live here
apps/infra/cilium/                                   # GitOps (ArgoCD) Cilium chart + values
kubernetes/karpenter/                                # GitOps NodePool YAML + templates
```

> Note the estate has **two Karpenter delivery paths**: (a) Terraform `karpenter-nodepools`
> (module renders NodePool/EC2NodeClass from `account.hcl`, `ami_family=Bottlerocket`
> default) and (b) a **GitOps** path (`kubernetes/karpenter/*.yaml` + `templates/*.tpl` +
> `render-templates.sh`) applied via `kubectl`/ArgoCD. Pick one per cluster; do not run both
> against the same pools. The GitOps YAMLs additionally carry IMDS hardening and
> `instance-category/generation/cpu` requirements (§4.4).

**Version pins** (single source of truth: `terragrunt/versions.hcl`; mirrored to
`.tool-versions`):

| Tool / provider / chart | Pin |
|---|---|
| Terraform / OpenTofu | `1.14.8` (`= 1.14.8`) |
| Terragrunt | `1.0.8` |
| provider `aws` / `helm` / `kubernetes` | `~> 6.0` / `~> 2.12` / `~> 2.30` |
| EKS module `terraform-aws-modules/eks/aws` | `21.15.1` (`~> 21.15`) |
| Karpenter chart | `1.10.0` (history `1.1.1`→`1.8.1`→`1.10.0`) |
| **Cilium** | **`1.19.4` live via GitOps** (`apps/infra/cilium`, wrapper chart `1.1.0`, W4 uplift from `1.17.1`). ⚠ Drift: TF `cilium` module default `1.17.1`; catalog `cilium` unit input `1.16.5`. Reconcile before rebuild. |
| KEDA chart | `2.16.1` (no `ScaledObject`s shipped — teams add their own) |
| Gateway API CRDs / Envoy Gateway | `1.2.1` / `v1.8.x` |
| K8s cluster version | `1.32` (catalog default) · `1.34` (`_envcommon/eks.hcl` target) · `1.29` (dev agent-cluster) |

> `versions.hcl` bump policy: patch/minor → PR + green CI on a non-prod env first;
> **major → ADR required + multi-env soak.**

### 4.2 EKS control plane (mainline `eks` unit)

The catalog `eks` unit sources the registry module and disables VPC CNI:

```hcl
# catalog/units/eks/terragrunt.hcl
terraform { source = "tfr:///terraform-aws-modules/eks/aws?version=21.15.1" }

inputs = {
  cluster_name    = "${local.environment}-${local.aws_region}-platform"   # {{CLUSTER_NAME}}
  cluster_version = "1.32"

  cluster_endpoint_public_access       = local.account_vars.locals.eks_public_access
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = try(local.account_vars.locals.eks_public_access_cidrs, [])  # ADR-0010, default []

  enable_irsa               = true
  cluster_encryption_config = { provider_key_arn = dependency.kms.outputs.key_arns["eks-secrets"], resources = ["secrets"] }
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Add-on baseline — vpc-cni intentionally ABSENT (Cilium is the CNI)
  cluster_addons = {
    coredns                = { most_recent = true, configuration_values = jsonencode({
                                 tolerations = [{ key = "node.cilium.io/agent-not-ready", operator = "Exists", effect = "NoSchedule" }] }) }
    kube-proxy             = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }        # ADR-0018
  }

  node_security_group_tags = { "karpenter.sh/discovery" = local.cluster_name }   # Karpenter SG discovery

  # System managed node group — bootstraps cluster-critical pods, tainted until Cilium ready
  eks_managed_node_groups = {
    system = {
      ami_type       = "BOTTLEROCKET_x86_64"               # ADR-0030
      platform       = "bottlerocket"
      instance_types = local.account_vars.locals.eks_instance_types
      min_size       = local.account_vars.locals.eks_min_size
      max_size       = local.account_vars.locals.eks_max_size
      desired_size   = local.account_vars.locals.eks_desired_size
      taints = { cilium = { key = "node.cilium.io/agent-not-ready", value = "true", effect = "NO_SCHEDULE" } }
    }
  }

  enable_cluster_creator_admin_permissions = true          # DISABLE after bootstrap; rely on access_entries
  access_entries = {                                       # SSO permission-set roles → K8s groups
    platform_engineer = { principal_arn = "${local.sso_role_prefix}/AWSReservedSSO_PlatformEngineer_*", kubernetes_groups = ["platform-operators"], type = "STANDARD" }
    readonly_access   = { principal_arn = "${local.sso_role_prefix}/AWSReservedSSO_ReadOnlyAccess_*",  kubernetes_groups = ["platform-viewers"],   type = "STANDARD" }
    developer_access  = { principal_arn = "${local.sso_role_prefix}/AWSReservedSSO_DeveloperAccess_*", kubernetes_groups = ["platform-viewers"],   type = "STANDARD" }
  }
}
```

The **`eks-agent-cluster`** module is the Karpenter-only variant (the platform-agent-manual's
canonical EKS compute module): identical control-plane posture but
`eks_managed_node_groups = {}` and `create_node_group = false` — *all* node management is
Karpenter's. Used by the dev `agent-cluster` stack.

### 4.3 Cilium CNI (`cilium` unit + `terraform/modules/cilium`; live chart `apps/infra/cilium`)

General clusters run **ENI IPAM / native-routing** with eBPF features on. Load-bearing values
(sanitized excerpt from the live GitOps chart, Cilium 1.19.4):

```yaml
eni: { enabled: true, awsEnablePrefixDelegation: true, updateEC2AdapterLimitViaAPI: true, awsReleaseExcessIPs: true }  # Bottlerocket+ENI
ipam:        { mode: eni }
routingMode: native                 # no overlay/tunnel — pods get VPC IPs (no VXLAN anywhere)
cni:         { chainingMode: none, exclusive: true }
kubeProxyReplacement: false         # general clusters KEEP kube-proxy (flip per-account after validation)
k8sServicePort: 443                 # + k8sServiceHost = <cluster endpoint> when replacement=true
encryption:  { enabled: true, type: wireguard, nodeEncryption: false }        # in-transit encryption
authentication.mutual.spire: { enabled: true, trustDomain: cluster.local }    # optional mTLS (SPIFFE deferred, ADR-0019)
loadBalancer:{ algorithm: maglev }
bpf:         { masquerade: true, preallocateMaps: true, tproxy: true }
bandwidthManager: { enabled: true, bbr: true }
localRedirectPolicy: true
gatewayAPI:  { enabled: true, enableAlpn: true }                              # ADR-0009, GatewayClass cilium
hubble:      { enabled: true, relay: {replicas: 2}, ui: {enabled: true}, metrics: {enabled: [dns,drop,tcp,flow,port-distribution,icmp,httpV2]} }
operator:    { replicas: <prod:2/nonprod:1>, priorityClassName: system-cluster-critical, tolerations: [{operator: Exists}], extraEnv: [{name: AWS_REGION, value: <region>}] }
cluster:     { name: <=32 chars, id: <clustermesh id or 0> }
clustermesh: { useAPIServer: <enable_clustermesh> }
```

- **IRSA for the operator (and agent):** a dedicated IAM role (`<cluster>-cilium-operator`)
  grants EC2 ENI APIs (`Create/Attach/Detach/Delete/ModifyNetworkInterface`,
  `Assign/UnassignPrivateIpAddresses`, `Describe*`, scoped `CreateTags` on
  `network-interface/*`). Without it, ENI mode fails immediately. Both `cilium` and
  `cilium-operator` service accounts are annotated with the role ARN.
- **Default-deny** ships as a `CiliumClusterwideNetworkPolicy` (`default-deny-all`) applied
  via `kubectl_manifest` (apply-time GVK validation — the CRD is created by the same Helm
  release, so `kubernetes_manifest`'s plan-time check would fail). It permits only
  `reserved:init`, `kube-apiserver`/`host`, and kube-dns (UDP/TCP 53).
- **GPU-inference clusters differ:** `ipam.mode = cluster-pool` (`100.64.0.0/10`, `/24`
  blocks) + `autoDirectNodeRoutes` + `bgpControlPlane.enabled`, and
  **`kubeProxyReplacement: true`** (kube-proxy-less). Bare-metal is also kube-proxy-less
  (LB-IPAM + BGP, ADR-0051). No overlay anywhere (`routingMode: native` universally).

### 4.4 Karpenter (IAM · controller · NodePools — three units)

**Controller** (`terraform/modules/karpenter`, chart `1.10.0`, OCI
`oci://public.ecr.aws/karpenter`): installed in `kube-system`, 2–3 replicas + PDB
(`minAvailable: 1`); controller resources `500m/512Mi` → `1000m/1Gi`; runs on the system
group (`nodeSelector karpenter.sh/controller=true`, tolerates `CriticalAddonsOnly`).
Settings use **EKS Pod Identity** (`settings.clusterName/clusterEndpoint/interruptionQueue`)
and the SQS **interruption queue** for spot-termination warnings. **Node auto-repair** is on
(`featureGates.nodeRepair = true`, v1.10 alpha; requires the `eks-node-monitoring-agent`
add-on; disruption hard-capped at **20%** of a NodePool independent of budgets).

**NodePools + EC2NodeClasses** (`karpenter-nodepools`, one pair per `var.nodepool_configs`
entry, `for_each`-generated as `kubernetes_manifest`). EC2NodeClass (`karpenter.k8s.aws/v1`):

```yaml
amiSelectorTerms: [{ alias: "bottlerocket@latest" }]     # or al2023@latest for VPC-CNI
role: <karpenter node IAM role>
subnetSelectorTerms:        [{ tags: { "karpenter.sh/discovery": <cluster> } }]
securityGroupSelectorTerms: [{ tags: { "karpenter.sh/discovery": <cluster> } }]
metadataOptions: { httpTokens: required, httpEndpoint: enabled, httpPutResponseHopLimit: 2, httpProtocolIPv6: disabled }  # CDE uses hopLimit 1
blockDeviceMappings:                                     # Bottlerocket = 2 volumes
  - deviceName: /dev/xvda  { volumeSize: 4Gi,  volumeType: gp3, encrypted: true }                       # OS
  - deviceName: /dev/xvdb  { volumeSize: 50Gi, volumeType: gp3, encrypted: true, iops: 3000, throughput: 125 }  # data
userData: |                                              # Bottlerocket TOML (not cloud-init)
  [settings.kubernetes]
  cluster-name = "<cluster>"
  [settings.kubernetes.node-labels]
  "karpenter.sh/nodepool" = "<pool>"
placement: { placementGroupName: <opt>, availabilityZone: <opt> }   # HPC single-AZ pinning
```

NodePool (`karpenter.sh/v1`) generated from per-pool knobs:

```yaml
requirements:
  - karpenter.sh/capacity-type ∈ (spot%>=100 → [spot]; <=0 → [on-demand]; else [spot,on-demand])
  - kubernetes.io/arch          ∈ architectures            # [amd64] / [arm64]
  - kubernetes.io/os            ∈ [linux]
  - karpenter.k8s.aws/instance-family ∈ instance_families  # e.g. [m6i,m6a,m5,m5a]
  - karpenter.k8s.aws/instance-size   ∈ instance_sizes     # optional
taints / startupTaints: <per pool>
expireAfter: <expire_after, default 720h>                  # node max-lifetime (30d → AMI refresh)
limits:     { cpu: <cpu_limit>, memory: "<memory_limit>Gi" }
disruption: { consolidationPolicy: <WhenEmptyOrUnderutilized|WhenEmpty>, consolidateAfter: <30s..Never>,
              budgets: <default [{nodes:"10%"}] or scheduled per-pool> }
weight: <lower = higher priority>
```

The **GitOps** NodePools (`kubernetes/karpenter/*.yaml`) express finer requirements —
`karpenter.k8s.aws/instance-category ∈ [c,m,r(,t)]`, `instance-generation Gt 5`,
`instance-cpu ∈ [...]`, `topology.kubernetes.io/zone` — and add IMDS hardening. Canonical
pools: **x86-general-purpose** (al2023, `weight 10`), **arm64-graviton** (Bottlerocket,
Graviton4/3/2 families, `weight 20`), **c-series-compute** (taint
`workload-type=compute-intensive`, `weight 15`), **spot-flexible** (100% spot, multi-arch,
`consolidateAfter 15s`, `weight 50`), **cde-nodes** (Bottlerocket, Intel-only, on-demand,
taint `pci-dss=cde`, `expireAfter 720h`, `WhenEmpty`/`Never`), and **dev-general-purpose**
(business-hours scale-to-zero: `budgets: [{nodes:"0", schedule:"0 20 * * 1-5", duration:11h}, {nodes:"10%"}]`).

### 4.5 Autoscaling stack (pods)

- **KEDA** (`keda` unit, chart `2.16.1`): event-driven scaling (SQS depth, Prometheus, cron,
  …), can scale to zero. Operator + metrics-server replicas env-sized; Prometheus metrics on.
  This spec owns the autoscaling **contract**; concrete `ScaledObject`/`TriggerAuthentication`
  instances ship per-workload via SPEC-04's delivery machinery (none are committed in the
  estate today — see §7). The canonical shape (SQS-depth worker, scale-to-zero, identity via
  the operator's Pod Identity) is:

  ```yaml
  apiVersion: keda.sh/v1alpha1
  kind: ScaledObject
  metadata: { name: video-worker, namespace: workloads }
  spec:
    scaleTargetRef: { name: video-worker }
    minReplicaCount: 0            # scale-to-zero
    maxReplicaCount: 50
    cooldownPeriod: 300
    triggers:
      - type: aws-sqs-queue
        metadata:
          queueURL: https://sqs.{{PRIMARY_REGION}}.amazonaws.com/{{PROD_ACCOUNT_ID}}/video-jobs
          queueLength: "5"        # target messages-per-replica
          awsRegion: {{PRIMARY_REGION}}
          identityOwner: operator # use the KEDA operator's EKS Pod Identity (ADR-0018)
  ```
- **HPA defaults** (`hpa-defaults` unit): platform-component HPAs, e.g. **CoreDNS**
  `min 2 / max 10`, CPU 70% + memory 80% targets, 300 s scale-down stabilization. Gated by
  `enable_hpa_defaults` (off in dev).
- **Watermark PodAutoscaler** (`wpa` unit, Datadog chart): optional watermark/latency
  autoscaling, **off by default** (`enable_wpa = false`).

### 4.6 Ordering & dependencies (what must exist before what)

```
KMS(eks-secrets) ─┐
VPC (private subnets + karpenter.sh/discovery tags) ─┴─▶ eks ─▶ cilium ─▶ karpenter-iam
                                                                     │        │
                                                      karpenter-controller ◀──┘
                                                                     │
                                              karpenter-nodepools (needs cilium + iam + controller)
eks ─▶ keda | hpa-defaults | wpa | monitoring         rds ← (vpc, eks, secrets)
```

`karpenter-nodepools` declares `dependency` on **eks, karpenter-iam, karpenter-controller,
and cilium** (Bottlerocket nodes need the CNI). Each unit's Kubernetes/Helm providers
authenticate via the `aws eks get-token` exec-plugin against the dependency's cluster
outputs; the controller unit also declares an `aws.virginia` (us-east-1) alias for the ECR
Public token Karpenter's OCI chart needs.

---

## 5. Parameterization table

All sizing lives in `terragrunt/<env>/account.hcl`. Placeholders consumed here (recurring
ones defined in `SPEC-00-overview.md`; spec-local ones marked ✦):

| Placeholder | Meaning | Example shape |
|---|---|---|
| `{{ORG}}` | org slug | `acme` |
| `{{PRIMARY_REGION}}` / `{{SECONDARY_REGIONS}}` | regions | `eu-west-1` / `["eu-central-1", …]` |
| `{{DEV/STAGING/PROD_ACCOUNT_ID}}` | workload account IDs | `111111111111` (dummy) |
| ✦ `{{CLUSTER_NAME}}` | cluster-name pattern | `<env>-<region>-platform` |
| ✦ `{{KMS_EKS_SECRETS_KEY_ARN}}` | secrets CMK ARN | KMS unit `key_arns["eks-secrets"]` |
| ✦ `{{ADMIN_CIDR_ALLOWLIST}}` | operator/VPN egress CIDRs for public API | narrow RFC1918 range, **never** `0.0.0.0/0` |

### 5.1 Cluster sizing knobs (defaults observed; resize per client)

| Setting (`account.hcl`) | dev | staging | prod | dr | Guidance |
|---|---|---|---|---|---|
| `eks_instance_types` (system NG) | `m6i.large` | `m6i.xlarge` | `m6i.2xlarge` | `m6i.xlarge` | System group only hosts CoreDNS/Cilium/Karpenter/KEDA/ESO — keep small. |
| `eks_min/desired/max_size` | `1/2/3` | `2/3/5` | `3/5/10` | `1/2/5` | Size for add-on HA, not app load (Karpenter runs the rest). |
| `eks_public_access` / `_cidrs` | `true` / `["0.0.0.0/0"]` | `false` / `[]` | `false` / `[]` | `false` / `[]` | dev-only open access is a deliberate exception; prod/staging private-only (ADR-0010). |
| `cluster_version` | env-set (`1.29` agent-cluster) | env-set | `1.32` (catalog) | env-set | `_envcommon` target `1.34`; upgrade one minor at a time (§7). |
| `cilium_replace_kube_proxy` | per-env | `false` (initial) | per-env | per-env | Start with kube-proxy present; flip after validation. GPU/bare-metal = kube-proxy-less. |
| `single_nat_gateway` | `true` | `false` (HA) | `false` (HA) | `true` | NAT posture (SPEC-02); affects node egress cost. |
| `karpenter_controller_replicas` / `_log_level` | `2` / `info` | `2` / `info` | `3` / `warn` | — | Controller HA + verbosity. |
| `keda_operator/metrics_replicas` | `1/1` | `2/2` | `3/3` | — | Size for CRD watch load. |
| `enable_hpa_defaults` / `enable_wpa` | `false` / `false` | `true` / `false` | `true` / `false` | — | WPA optional. |
| `enable_clustermesh` | `false` | `true` | per-env | — | Cross-region service discovery; needs per-region `clustermesh_cluster_ids`. |
| `enable_cde_isolation` | `false` | `false` | `true` | — | PCI CDE: dedicated `cde` NodePool + taint + policies. |

### 5.2 Karpenter NodePool knobs (`karpenter_nodepools` map)

Per-pool fields (`karpenter-nodepools`): `enabled`, `cpu_limit`, `memory_limit`,
`spot_percentage` (0 = on-demand only, 100 = spot only), `instance_families`,
`instance_sizes`, `excluded_instance_types`, `architectures` (`amd64`/`arm64`),
`consolidation_policy` (`WhenEmptyOrUnderutilized` | `WhenEmpty`), `consolidate_after`
(`30s`…`Never`), `weight`, `expire_after` (default `720h`), `taints`/`startup_taints`,
`labels`, `disruption_budgets` (optional `schedule`/`duration`), and HPC options
`placement_group_name`, `availability_zone`, `block_device_overrides` (io2/high-IOPS).

**Representative prod pools** (illustrative; resize per client):

| Pool | families | arch | spot % | cpu/mem limit | consolidate | notes |
|---|---|---|---|---|---|---|
| `x86` | `m6i,m6a,m5,m5a` | amd64 | 70 | 2000 / 4000Gi | `WhenEmptyOrUnderutilized` @300s | general purpose |
| `arm64` | `m6g,m7g,c6g,c7g` | arm64 | 70 | 1000 / 2000Gi | @300s | Graviton, cheapest |
| `c-series` | `c6i,c6a,c5,c5a` | amd64 | 60 | 500 / 1000Gi | @300s | CPU-bound/batch |
| `spot-flexible` | wide | amd64 | 100 | (disabled in prod) | @300s | max savings, interruption-tolerant |
| `cde` | `c6i,c7i,m6i,m7i` | amd64 | **0** | 32 / 64Gi | **`WhenEmpty` / Never** | PCI CDE, on-demand, taint `pci-dss=cde:NoSchedule`, `expireAfter 720h` |

dev/staging use the same pools at smaller limits and shorter `consolidate_after` (`30–60s`).
Specialized clusters define their own pools — e.g. staging **blockchain**
(execution/consensus/mev/bitcoin, 0% spot, cluster placement group, io2/gp3 high-IOPS,
`Never` consolidation, slashing-risk taints) and staging **gpu-analysis**
(`g5`/`g4dn` A10G/T4, `nvidia.com/gpu` taint, placement group, business-hours disruption
budgets).

---

## 6. Best practices distilled

1. **Never run VPC CNI and Cilium together.** Omit the `vpc-cni` add-on entirely and install
   Cilium before nodes carry workloads. *Why:* two CNIs both program the dataplane and race
   for pod IPs.
2. **Keep the managed system node group tiny and tainted.** Taint it
   `node.cilium.io/agent-not-ready:NoSchedule` and tolerate that taint on CoreDNS so nothing
   schedules before the CNI is `Ready`; let Karpenter own everything else. *Why:* avoids
   scheduling pods onto nodes with no working network.
3. **Run Cilium in ENI + native-routing on general EKS** for VPC-routable pod IPs and no
   tunnel overhead; enable `awsEnablePrefixDelegation` for pod density and `awsReleaseExcessIPs`
   for Bottlerocket. Reserve cluster-pool IPAM + BGP for GPU/bare-metal. *Why:* matches
   VPC-CNI reachability while keeping eBPF benefits.
4. **Set `AWS_REGION` explicitly on the Cilium operator** and give it
   `system-cluster-critical` priority + `{operator: Exists}` toleration. *Why:* in ENI mode
   the operator calls `DescribeInstanceTypes`; the SDK can't infer region from IMDS in the
   operator pod, and bootstrap taints otherwise leave it `Pending`.
5. **Roll out kube-proxy replacement gated.** Ship general clusters *with* kube-proxy
   (`kubeProxyReplacement: false`), validate Cilium stability, then flip per env; run
   GPU/bare-metal kube-proxy-less from the start. *Why:* de-risks a dataplane-wide change on
   live clusters.
6. **Express node strategy declaratively in NodePools, not imperatively.** Encode instance
   families/category/generation, arch, spot ratio, consolidation policy, disruption budgets,
   and `expireAfter` as data (`account.hcl` / GitOps YAML) so capacity policy is PR-reviewable.
7. **Tune `spot_percentage` and disruption per workload class.** 0% spot +
   `WhenEmpty`/`Never` for reliability-critical tiers (payments/CDE, blockchain slashing
   risk, GPU SLA, training gangs); high spot + aggressive consolidation for stateless/batch.
   Freeze disruption in business hours with scheduled budgets
   (`{nodes:"0", schedule:"0 9 * * 1-5", duration:"10h"}`).
8. **Diversify instance families for spot resilience** so Karpenter can dodge capacity
   shortfalls and interruptions.
9. **Bottlerocket needs a two-volume layout** (`/dev/xvda` OS 4Gi, `/dev/xvdb` data) and TOML
   userData, not cloud-init; encrypt both volumes; harden IMDS (`httpTokens: required`, hop
   limit 2, CDE hop limit 1). *Why:* wrong layout starves container storage; it's Bottlerocket's model.
10. **Prefer EKS Pod Identity for app workloads; reserve IRSA for bootstrap + Fargate.**
    Install `eks-pod-identity-agent`; keep IRSA only for Cilium operator and Karpenter
    (identity before/around the agent) and Fargate (unsupported by Pod Identity). Never put
    both on one SA. Scope least-privilege via ABAC on the 6 injected session tags. *Why:*
    fewer per-role OIDC trust policies; portable roles (ADR-0018).
11. **Encrypt secrets at rest (KMS envelope) and traffic in transit (WireGuard),** enable all
    five control-plane log types → CloudWatch, and ship a default-deny baseline. *Why:*
    PCI-DSS Req 3.4/4.1/10.2 and defense-in-depth; these are `account.hcl`-independent invariants.
12. **Fail closed on the API endpoint.** Default `eks_public_access_cidrs = []`; require an
    explicit, narrow, account-scoped allow-list to open it; never `0.0.0.0/0` outside dev.
13. **Enable Karpenter node auto-repair with the Node Monitoring Agent add-on.** The 20%
    per-NodePool cap plus your disruption budgets bound the blast radius of a correlated
    health-signal failure. *Why:* self-healing without draining a whole pool.
14. **Turn on the eBPF features you already pay for:** Maglev LB, BBR bandwidth manager,
    local-redirect policy, Hubble metrics, Tetragon (observe-first) — near-free once Cilium is
    the dataplane (ADR-0019). Defer SPIFFE mutual auth while WireGuard covers transit.
15. **Give every cluster a default-deny baseline** (`CiliumClusterwideNetworkPolicy`) that
    still allows DNS + apiserver, then open flows explicitly per namespace. Apply it with
    `kubectl_manifest` (apply-time CRD validation), not `kubernetes_manifest`.
16. **Split `eks` into `eks-cluster` + `eks-nodes` for strict first-boot** so Cilium installs
    between control-plane creation and first node join (breaks the CNI chicken-and-egg cycle
    on greenfield accounts).
17. **Isolate specialized workloads into their own clusters**, not just namespaces:
    HPC/blockchain, GPU, PCI-CDE, and the general platform have different tenancy, capacity,
    and blast-radius needs.
18. **Pick one Karpenter delivery path per cluster** (Terraform-rendered *or* GitOps YAML);
    running both against the same pool names causes drift and thrash.

---

## 7. Known pitfalls

- **Cilium operator stuck `Pending` on bring-up.** Key-specific tolerations are insufficient;
  nodes also carry kubelet `not-ready`/`unreachable` taints during bootstrap. Fix:
  `tolerations: [{operator: Exists}]` + `priorityClassName: system-cluster-critical`
  (Round 11 post-mortem).
- **Operator crash-loops "Missing Region" in ENI mode.** `DescribeInstanceTypes` via IRSA
  can't infer region from IMDS in the operator pod. Fix: set `AWS_REGION` in operator
  `extraEnv` (Round 13 finding).
- **`kubernetes_manifest` fails at plan time for CRDs created in the same apply.** Use
  `gavinbunney/kubectl` `kubectl_manifest` for the Cilium default-deny policy; NodePool/
  EC2NodeClass manifests apply only after the Karpenter controller unit installs the chart CRDs.
- **CNI chicken-and-egg on greenfield.** Nodes never reach `Ready` if they join before Cilium
  exists. Either taint the system group until agent-ready (mainline) or split
  `eks-cluster`/`eks-nodes` (minimal-platform).
- **`cluster.name` > 32 chars breaks the Cilium chart.** When ClusterMesh is off, the module
  truncates `cluster_name` to 32 chars for local identity.
- **Bottlerocket ≠ AL2023 config.** The EC2NodeClass must switch AMI alias *and* block-device
  layout *and* userData format together; mixing them yields unschedulable/mis-provisioned nodes.
  No in-place AL2023→Bottlerocket conversion — roll fresh nodes.
- **Spot without PDBs or interruption tolerance = outages.** Wire the SQS interruption queue
  and use interruption-tolerant workloads; `cde`, blockchain, and training pools deliberately
  use 0% spot.
- **Leaving `enable_cluster_creator_admin_permissions = true` after bootstrap** is a standing
  admin backdoor — disable it and rely on `access_entries` once RBAC is applied.
- **As-built divergence: Cilium version is pinned in three places.** Live GitOps chart
  `1.19.4` (`apps/infra/cilium`), TF `cilium` module default `1.17.1`, catalog `cilium` unit
  input `1.16.5`; the reference manuals cite yet another aspirational `1.18.x`. **Authority
  ruling for a rebuild:** what GitOps reconciles is what actually runs, so **`1.19.4` is the
  as-built truth**. Guidance: **pin ONE version in a single source** (`versions.hcl` *or* the
  GitOps chart) and derive every other reference from it — do not carry three independent pins.
- **As-built divergence: cluster Kubernetes version spread.** `1.29` (dev agent-cluster),
  `1.32` (catalog `eks` unit), `1.34` (`_envcommon/eks.hcl` target); manuals cite `1.33`.
  **Recommendation:** adopt the estate's own declared target — **`1.34` (`_envcommon`)** — as
  the floor for new builds, and converge the older clusters up one minor at a time.
- **As-built divergence: Istio is declared but not deployed.** The reference manual documents
  Istio sidecar + multi-cluster and the dev `agent-cluster` stack **lists an `istio` unit**,
  but **no Istio module ships** and nothing (ztunnel/waypoint/istio-cni) is deployed. The
  as-built mesh is **sidecarless**: Cilium eBPF + WireGuard + optional SPIRE mTLS; L7 = Cilium
  Gateway API (ADR-0009) + Envoy Gateway secondary (ADR-0025). **Recommendation:** remove the
  `istio` unit (or explicitly mark it experimental) — the sidecarless design is the documented
  target; do not assume a service mesh unless a cluster explicitly opts in.
- **As-built divergence: KEDA is deployed with zero `ScaledObject`s.** The `keda` unit
  installs the controller everywhere, but no `ScaledObject`/`TriggerAuthentication` instances
  are committed — the autoscaling *contract* exists without instances. (The vLLM autoscaler
  today is a plain `autoscaling/v2` HPA on custom `vllm:num_requests_*` metrics, not KEDA.)
  **Recommendation:** ship concrete instances via the delivery layer (SPEC-04) using the §4.5
  template; treat KEDA presence-without-instances as intentional platform capability, not dead
  config.
- **`eks_agent_cluster_design.excalidraw` is an unlabeled wireframe** (no text). The EKS
  compute design lives in code (`terraform/modules/eks-agent-cluster`) and the
  platform-agent-manual, not the diagram.

### Upgrade strategy

- **One minor at a time**, non-prod first (dev → staging → prod → dr), driven by the
  `cluster_version` knob in `account.hcl`; **majors of any pinned tool require an ADR +
  multi-env soak** (`versions.hcl` bump policy).
- **Control plane before data plane:** bump `cluster_version`, let the managed system group
  roll (Bottlerocket managed-node-group update), then let Karpenter recycle nodes.
  `expireAfter` (default `720h`) guarantees nodes churn onto new AMIs within the window; drain
  faster by lowering it or forcing consolidation. The PCI `cde` pool's `expireAfter 720h` is a
  compliance control (30-day forced AMI refresh).
- **Add-ons `most_recent = true`** track the cluster version on apply; validate CoreDNS and
  `eks-pod-identity-agent` compatibility per minor.
- **Cilium/Karpenter/KEDA chart bumps** go through the same non-prod-first PR flow; flip risky
  Cilium features (kube-proxy replacement, netkit) gated on fresh node groups.

### Multi-cluster boundaries

| Cluster | Where | Node strategy | Why its own cluster |
|---|---|---|---|
| `platform` (general) | every env × region | system NG + Karpenter x86/arm64/c-series/spot(/cde) | Default tenancy; app workloads. |
| `agent-cluster` (dev) | `dev/us-east-1` | Karpenter-only (`eks-agent-cluster`, no NG) + Cilium + KEDA (+experimental istio unit) | Isolated agent workloads; mesh experimentation (not mainline). |
| `blockchain` (HPC) | `staging/eu-central-1` | on-demand-only pools, cluster placement groups, io2/gp3 high-IOPS, `Never` consolidation | Slashing risk (no spot), low-latency P2P, single-AZ locality. |
| `gpu-analysis` | `staging/eu-west-3` | GPU pools (A10G `g5` / T4 `g4dn`) + CPU coordination, placement groups | GPU tenancy, real-time SLA, video-pipeline isolation. |
| `gpu-inference` (prod) | `prod/eu-west-1` | H100 (`p5.48xlarge`) MNG + Karpenter GPU, cluster-pool IPAM + BGP, kube-proxy-less | Prod inference SLA + GPU fabric (ADR-0044/0046). |
| `minimal-platform` | `sandbox` | split `eks-cluster`+`eks-nodes`, single NAT, IP-locked public API | Cheapest bring-up; validates the split-unit ordering. |

**ClusterMesh** (Cilium) provides cross-region service discovery within an env (staging
`eu-west-1`↔`eu-central-1`, per-cluster IDs, apiserver over internal NLB, TLS material
exchanged via Secrets Manager, SG rules opening etcd/2379 · WireGuard/51871 · Hubble/4244).
It is gated (`clustermesh_connect_enabled`) until both peers' certs are exchanged — the L3/mesh
fabric is SPEC-02's subject.

---

## 8. Acceptance checklist

A rebuild passes when:

- [ ] `terragrunt stack plan` on `terragrunt/<env>/{{PRIMARY_REGION}}/platform` is clean from a
      bootstrapped-but-empty account (mock outputs satisfy `init/validate/plan`).
- [ ] The EKS control plane comes up **private-only** in staging/prod
      (`cluster_endpoint_public_access = false`, `_cidrs = []`); dev is the only env with a
      non-empty allow-list and it is explicit.
- [ ] `kubectl get nodes` shows only the **system** Bottlerocket group until Cilium is `Ready`;
      the `node.cilium.io/agent-not-ready` taint clears after the agent starts.
- [ ] `kubectl -n kube-system get ds cilium` is fully rolled out; `cilium status` reports
      **IPAM: ENI**, **routing: native**, and kube-proxy replacement at the env-configured mode.
      The `vpc-cni` add-on is **absent**.
- [ ] `kubectl get ciliumclusterwidenetworkpolicy default-deny-all` exists and DNS + apiserver
      still work; the Cilium GatewayClass `cilium` is present.
- [ ] `kubectl get deploy -n kube-system karpenter` is Available with the configured replicas +
      PDB; `kubectl get nodepool` / `kubectl get ec2nodeclass` list every enabled pool.
- [ ] A test Deployment with `nodeSelector karpenter.sh/nodepool=<pool>` provisions a matching
      **Bottlerocket** node of the right family/arch/capacity-type, later consolidated when idle
      per `consolidate_after`.
- [ ] Spot interruptions are handled (SQS queue drains warnings; pods reschedule); 0%-spot pools
      (`cde`, blockchain, training) only ever get on-demand nodes.
- [ ] `eks-pod-identity-agent`, `coredns`, `kube-proxy` add-ons are present/healthy; a workload
      assumes an AWS role via a `PodIdentityAssociation` with no IRSA wiring; no SA carries both
      IRSA + Pod Identity.
- [ ] KEDA is installed and a sample `ScaledObject` scales its target (including to zero); the
      CoreDNS HPA exists where `enable_hpa_defaults = true`.
- [ ] Control-plane logs (all 5 types) reach CloudWatch; secrets are KMS-encrypted at rest;
      WireGuard node-to-node encryption is active.
- [ ] `enable_cluster_creator_admin_permissions` is disabled post-bootstrap; SSO roles map to
      `platform-operators`/`platform-viewers` via access entries.
- [ ] A minor-version upgrade rolls dev → staging → prod one step at a time with no manual node
      surgery (managed group rolls; Karpenter recycles within `expireAfter`).

---

## 9. Dependencies on other specs

- **SPEC-00 — Overview**: defines shared placeholders (`{{ORG}}`, `{{PRIMARY_REGION}}`,
  account IDs) consumed here.
- **SPEC-01 — Foundation (IaC, account topology, state)**: the 9-account Control Tower landing
  zone, the Terragrunt `root.hcl`/`versions.hcl`/`_envcommon`/`catalog` skeleton this plane's
  units plug into, tool/provider version pins, and the tagging taxonomy (ADR-0028).
- **SPEC-02 — Network & DNS**: VPC/subnet layout, the `karpenter.sh/discovery` subnet + SG
  tags, NAT posture, Transit Gateway, and the Cilium **ClusterMesh** L3 fabric this plane rides
  on.
- **SPEC-04 — Delivery (GitOps)**: ArgoCD app-of-apps, the ApplicationSet `cluster_role` label
  scheme (ADR-0012), Kargo promotion, Argo Rollouts, the `kubernetes/karpenter/` GitOps
  NodePool path, and the concrete KEDA `ScaledObject`/`TriggerAuthentication` instances (§4.5
  template) that deploy *onto* these clusters.
- **SPEC-05 — Security (incl. secrets)**: SCP/RCP/GuardDuty/SecurityHub, SSO permission sets
  that back EKS access entries, Pod Security Admission, Falco/Tetragon runtime policy, PCI-CDE
  isolation contents, the break-glass procedure (ADR-0011), and secrets management — the
  `eks-secrets` CMK (control-plane envelope encryption), External Secrets Operator (ADR-0008,
  cutover on Pod Identity per ADR-0018), and ClusterMesh TLS material in Secrets Manager.
- **SPEC-07 — Observability**: Hubble UI, Prometheus/Thanos/VictoriaMetrics, DCGM, OpenCost,
  and the metrics this plane emits (ADR-0026/0027).
- **SPEC-10 — ML workloads (incl. GPU inference)**: the specialized GPU/ML plane that reuses
  this spec's EKS + Karpenter + Cilium patterns — GPU NodePools + GPU Operator + DRA + Volcano
  (ADR-0044/0046), EFA fabric (ADR-0045), and the bare-metal Talos plane (ADR-0049–0054).
```