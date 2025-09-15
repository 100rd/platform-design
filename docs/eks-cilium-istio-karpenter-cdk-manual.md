# 🧰 Production EKS + Cilium + Istio + Karpenter (Go CDK) — End‑to‑End Manual

> Opinionated, security‑first reference for building an **Amazon EKS** platform with **private‑only worker nodes**, **Cilium CNI**, **Istio service mesh** (including **multi‑cluster**), **Karpenter** autoscaling, **strong secrets management**, and **IaC in Go with AWS CDK**.  
> **No Fargate** is used anywhere.

---

## Table of Contents

- [Architecture at a glance](#architecture-at-a-glance)
- [Prereqs & versions](#prereqs--versions)
- [VPC & subnet layout (private nodes only)](#vpc--subnet-layout-private-nodes-only)
- [AWS CDK (Go) project design & best practices](#aws-cdk-go-project-design--best-practices)
- [Create the EKS cluster (Go CDK)](#create-the-eks-cluster-go-cdk)
- [Encrypt EKS control plane logs (CloudWatch + KMS)](#encrypt-eks-control-plane-logs-cloudwatch--kms)
- [Secrets management patterns](#secrets-management-patterns)
- [Install Cilium (detailed)](#install-cilium-detailed)
- [Network policies (deny `app=default`)](#network-policies-deny-appdefault)
- [Pod Security Standards (PSS)](#pod-security-standards-pss)
- [Karpenter: before you enable it](#karpenter-before-you-enable-it)
- [Horizontal/Vertical/Event-driven scaling](#horizontalverticalevent-driven-scaling)
- [Istio (single cluster)](#istio-single-cluster)
- [Istio multi-cluster architecture (2+ clusters as one logical mesh)](#istio-multi-cluster-architecture-2-clusters-as-one-logical-mesh)
- [Traffic management kinds (HTTP/HTTPS & gRPC)](#traffic-management-kinds-httphttps--grpc)
- [Go application design principles (for the mesh)](#go-application-design-principles-for-the-mesh)
- [References & examples](#references--examples)

---

## Architecture at a glance

- **EKS v1.33** control plane. Worker nodes **only in private subnets**.
- **Cilium** as the CNI:
  - Either **ENI IPAM** (VPC‑routable pod IPs) or **cluster‑pool IPAM** (overlay to conserve IPs).
  - Optional: **kube-proxy replacement** and **Hubble**.
- **Istio 1.27.x** service mesh with sidecars. Gateways for **north‑south** and **east‑west**.
- **Karpenter v1** for infra autoscaling (**EC2NodeClass/NodePool**).
- **Secrets** via **AWS Secrets Manager** using **Secrets Store CSI Driver (ASCP)** or **External Secrets Operator (ESO)**.
- **CDK (Go)** drives VPC, EKS, KMS, CloudWatch, Karpenter, and Helm bootstrap.

> EKS supported versions & AL2 deprecation from 1.33 onward: see AWS docs.  

---

## Prereqs & versions

Tools on your workstation:
- `kubectl`, `helm`, `aws` CLI, **Go 1.22+**, **AWS CDK v2**.

Versions (as of Sep 2025):
- **Kubernetes 1.33** on EKS
- **Istio 1.27.x**
- **Cilium 1.18.x**
- **Karpenter v1** (`EC2NodeClass` + `NodePool` APIs)

> Verify current versions in the references section below.

---

## VPC & subnet layout (private nodes only)

Goal: nodes in **private subnets** only; public subnets are used for NAT/ingress LBs.

- Use 2–3 AZs, each with:
  - **Public subnet**: Internet/NAT gateways, ingress LBs.
  - **Private subnet**: **EKS nodes** and pods. (Disable “Auto‑assign Public IPv4” on these subnets.)
- If nodes are private‑only, ensure **egress** for pulls/STS via NAT **or** VPC endpoints: at minimum `com.amazonaws.<region>.ecr.api`, `ecr.dkr`, and S3 **Gateway** endpoint.
- Plan **service CIDR** and, if using overlay IPAM, **pod CIDR** to **avoid overlap** with any peered networks. Typical picks:
  - Service CIDR (example): `172.20.0.0/16`
  - Cilium cluster‑pool pod CIDR (example): `100.64.0.0/11`

---

## AWS CDK (Go) project design & best practices

Recommended repo structure:

```
/cmd/platform/main.go         # CDK app
/pkg/stacks/network.go        # VPC, endpoints, NAT, KMS
/pkg/stacks/eks.go            # EKS cluster, OIDC, logging
/pkg/stacks/karpenter.go      # Karpenter IAM + Helm chart
/pkg/stacks/cilium.go         # Cilium Helm
/pkg/stacks/mesh.go           # Istio Helm
/pkg/stacks/observability.go  # Hubble, metrics, logging
/pkg/constructs/...           # Reusable constructs
```

Guardrails:
- Add **cdk‑nag** to catch insecure patterns in CI.
- Separate stacks per concern; pass outputs via stack references.
- Prefer **AL2023** or **Bottlerocket** AMIs for 1.33+ (AL2 AMIs end with 1.32).

---

## Create the EKS cluster (Go CDK)

> Targeting **Kubernetes 1.33**, **private endpoint access**, **control‑plane logs enabled**, and **nodes only in private subnets**.

```go
package eksstack

import (
  "github.com/aws/aws-cdk-go/awscdk/v2"
  "github.com/aws/aws-cdk-go/awscdk/v2/awseks"
  "github.com/aws/aws-cdk-go/awscdk/v2/awsec2"
  "github.com/aws/constructs-go/constructs/v10"
  "github.com/aws/jsii-runtime-go"
)

type EksStackProps struct {
  awscdk.StackProps
  Vpc awsec2.IVpc
}

type EksStack struct {
  awscdk.Stack
  Cluster awseks.Cluster
}

func NewEksStack(scope constructs.Construct, id string, props *EksStackProps) *EksStack {
  s := &EksStack{ Stack: awscdk.NewStack(scope, &id, &props.StackProps) }

  clusterName := "prod-octarine"

  s.Cluster = awseks.NewCluster(s, jsii.String("Eks"), &awseks.ClusterProps{
    Version:        awseks.KubernetesVersion_V1_33(),
    ClusterName:    jsii.String(clusterName),
    Vpc:            props.Vpc,
    VpcSubnets:     &[]*awsec2.SubnetSelection{{ SubnetType: awsec2.SubnetType_PRIVATE_WITH_EGRESS }},
    EndpointAccess: awseks.EndpointAccess_PRIVATE(),
    ClusterLogging: &[]awseks.ClusterLoggingTypes{
      awseks.ClusterLoggingTypes_API,
      awseks.ClusterLoggingTypes_AUDIT,
      awseks.ClusterLoggingTypes_AUTHENTICATOR,
      awseks.ClusterLoggingTypes_CONTROLLER_MANAGER,
      awseks.ClusterLoggingTypes_SCHEDULER,
    },
    DefaultCapacity: jsii.Number(0),
  })

  // Example managed node group (private subnets only)
  s.Cluster.AddNodegroupCapacity(jsii.String("ng-main"), &awseks.NodegroupOptions{
    DesiredSize: jsii.Number(3),
    MinSize:     jsii.Number(3),
    MaxSize:     jsii.Number(30),
    InstanceTypes: &[]awsec2.InstanceType{
      awsec2.NewInstanceType(jsii.String("m7i.large")),
    },
    Subnets: &awsec2.SubnetSelection{SubnetType: awsec2.SubnetType_PRIVATE_WITH_EGRESS},
  })

  // Tag private subnets and the cluster security group for Karpenter discovery
  for _, s := range props.Vpc.PrivateSubnets() {
    awscdk.Tags_Of(s).Add(jsii.String("karpenter.sh/discovery"), s.Stack().StackName(), nil)
  }
  awscdk.Tags_Of(s.Cluster.ClusterSecurityGroup()).Add(jsii.String("karpenter.sh/discovery"), s.Stack().StackName(), nil)

  return s
}
```

Notes:
- **Private‑only workers**: `PRIVATE_WITH_EGRESS` subnets ensure no public IPs on nodes.
- **No Fargate**: only managed node groups and Karpenter‑provisioned nodes.

---

## Encrypt EKS control plane logs (CloudWatch + KMS)

1. **Enable** EKS control plane logging (API, Audit, Authenticator, Controller Manager, Scheduler).  
2. **Encrypt** the CloudWatch log groups with **KMS** (associate a CMK):

```bash
aws logs associate-kms-key \
  --log-group-name "/aws/eks/<cluster>/cluster" \
  --kms-key-id arn:aws:kms:<region>:<acct>:key/<key-id>

# repeat for:
# /aws/eks/<cluster>/kube-apiserver
# /aws/eks/<cluster>/audit
# /aws/eks/<cluster>/authenticator
# /aws/eks/<cluster>/controller-manager
# /aws/eks/<cluster>/scheduler
```

---

## Secrets management patterns

Pick one (or both):

### A) Secrets Store CSI + **AWS Provider (ASCP)**

Mount **Secrets Manager**/**Parameter Store** values as **files** in Pods with **IRSA** or **EKS Pod Identity**.

```bash
# Secrets Store CSI Driver
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver -n kube-system

# AWS provider (ASCP)
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
helm upgrade --install ascp aws-secrets-manager/secrets-store-csi-driver-provider-aws -n kube-system
```

### B) **External Secrets Operator (ESO)**

CRDs that **sync** from AWS Secrets Manager / SSM Parameter Store into Kubernetes **Secret** objects.

---

## Install Cilium (detailed)

> **You must be connected** to the target cluster context before installation:  
> `aws eks update-kubeconfig --name <cluster> --region <region>`

Choose your IPAM mode:

- **ENI IPAM** (Pods get IPs from VPC subnets; simple L3, consumes VPC IPs)
- **Cluster‑pool IPAM** (overlay pod CIDRs; conserves IPv4 space — pick a non‑overlapping CIDR, e.g. `100.64.0.0/11`)

If your cluster currently runs **AWS VPC CNI managed add‑on**, remove it first to avoid CNI conflicts (ideally, install Cilium before adding nodes).

**Helm install (Cilium 1.18.1)**

```bash
# 0) Ensure kubectl context points at the cluster
kubectl config use-context <your-eks-context>

# 1) Repos
helm repo add cilium https://helm.cilium.io
helm repo update

# 2a) ENI IPAM mode (pods receive VPC IPs)
helm upgrade --install cilium cilium/cilium \
  --version 1.18.1 \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set ipam.mode=eni \
  --set routingMode=native \
  --set eni.updateEC2AdapterLimits=true \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true

# 2b) OR cluster-pool IPAM (overlay pod CIDRs; change CIDR to your plan)
helm upgrade --install cilium cilium/cilium \
  --version 1.18.1 \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set ipam.mode=cluster-pool \
  --set cluster.name=<my-cluster> \
  --set cluster.id=1 \
  --set clusterPoolIpv4PodCidrList="{100.64.0.0/11}" \
  --set tunnel=vxlan \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true

# Check
kubectl -n kube-system rollout status ds/cilium
```

**Network ranges:**  
- In **ENI** mode, Pod IPs come **from your VPC subnets** — size subnets accordingly (prefix delegation helps).  
- In **cluster‑pool** mode, Pod IPs come from your configured **overlay CIDR**.

---

## Network policies (deny `app=default`)

> Kubernetes label values cannot include spaces; use a valid label like `app=default`.

**Option A — Kubernetes NetworkPolicy (deny all ingress & egress for pods with `app=default`)**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-for-app-default
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: default
  policyTypes:
    - Ingress
    - Egress
  ingress: []
  egress: []
```

**Option B — CiliumNetworkPolicy (explicit deny)**
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-app-default
  namespace: default
spec:
  endpointSelector:
    matchLabels:
      app: default
  ingressDeny:
    - fromEntities: [ "all" ]
  egressDeny:
    - toEntities: [ "all" ]
```

---

## Pod Security Standards (PSS)

**What:** Built‑in **Pod Security Admission** enforces **baseline** or **restricted** controls per namespace via labels (PSP is removed).

**Enforce `restricted` in a namespace:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: workloads
  labels:
    pod-security.kubernetes.io/enforce: "restricted"
    pod-security.kubernetes.io/enforce-version: "latest"
    pod-security.kubernetes.io/audit: "restricted"
    pod-security.kubernetes.io/warn: "restricted"
```

---

## Karpenter: before you enable it

Karpenter v1 provisions the *right* node at the *right* time. Use **private subnets only**.

**Required setup:**
1. **OIDC/IRSA** enabled for the cluster.
2. **Controller IAM role** (IRSA) with the official controller policy; bind to the `karpenter` service account.
3. **Node IAM role** (instance profile) with `AmazonSSMManagedInstanceCore` and minimal EC2/ECR permissions.
4. **Discovery tags** on **private subnets** and the **node security group**:  
   `karpenter.sh/discovery=<cluster-name>`  
   (Keep the classic EKS `kubernetes.io/cluster/<name>=shared|owned` tags as well.)
5. For private clusters, create **VPC endpoint for STS** so Karpenter can assume roles without internet.

**Example EC2NodeClass + NodePool**
```yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: general-al2023
spec:
  amiFamily: AL2023
  role: "KarpenterNodeRole-Prod"   # IAM instance profile
  subnetSelectorTerms:
    - tags: { karpenter.sh/discovery: prod-octarine }
  securityGroupSelectorTerms:
    - tags: { karpenter.sh/discovery: prod-octarine }
  tags:
    Name: karpenter-general
    Environment: prod
---
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: general
spec:
  template:
    metadata:
      labels: { workload: general }
    spec:
      nodeClassRef: { name: general-al2023 }
      taints:
        - key: dedicated
          value: general
          effect: NoSchedule
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 120s
  limits:
    cpu: "500"
```

---

## Horizontal/Vertical/Event-driven scaling

- **HPA (autoscaling/v2)** for CPU/memory/custom metrics.
- **VPA** for resource recommendations/updates (careful with HPA interactions).
- **KEDA** for event‑driven scaling (e.g., SQS depth → replicas; can scale to zero).

---

## Istio (single cluster)

Install **Istio 1.27.x**:
```bash
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.27.1 sh -
cd istio-1.27.1
./bin/istioctl install -y --set profile=default
kubectl label namespace default istio-injection=enabled
```

**Example HTTPS ingress + routing**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata: { name: public-gw, namespace: istio-system }
spec:
  selector: { istio: ingressgateway }
  servers:
  - port: { number: 80, name: http, protocol: HTTP }
    hosts: [ "example.com" ]
  - port: { number: 443, name: https, protocol: HTTPS }
    tls: { mode: SIMPLE, credentialName: tls-example-com }
    hosts: [ "example.com" ]
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata: { name: web-vs }
spec:
  hosts: [ "example.com" ]
  gateways: [ "istio-system/public-gw" ]
  http:
  - match: [{ uri: { prefix: "/api" }}]
    route:
    - destination: { host: api.default.svc.cluster.local, subset: v1, port: { number: 8080 } }
  - route:
    - destination: { host: web.default.svc.cluster.local, port: { number: 80 } }
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata: { name: api-dr }
spec:
  host: api.default.svc.cluster.local
  subsets:
  - name: v1
    labels: { version: v1 }
  trafficPolicy:
    outlierDetection: { consecutive5xxErrors: 3, interval: 5s, baseEjectionTime: 30s }
```

**gRPC routing** (gRPC uses HTTP/2; match by header or use Gateway API `GRPCRoute`):
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata: { name: grpc-vs }
spec:
  hosts: [ "greeter.default.svc.cluster.local" ]
  http:
  - match:
    - headers:
        content-type:
          exact: "application/grpc"
    route:
      - destination: { host: greeter.default.svc.cluster.local, port: { number: 50051 } }
```

---

## Istio multi-cluster architecture (2+ clusters as one logical mesh)

**Model:** **Multi‑primary, multi‑network** with **east‑west gateways** on each cluster, forming a single logical mesh across clusters/VPCs/regions.

Key building blocks:
- Same **meshID** / **trust domain** across clusters; unique `clusterName`; set `network` per cluster.
- `istiod` on each cluster (multi‑primary).
- **East‑west gateway** on each cluster exposing **port 15443** with `tls.mode: AUTO_PASSTHROUGH`.
- **Remote secrets** exchanged between clusters for endpoint discovery.
- Locality‑aware routing & failover via **DestinationRule** (`localityLbSetting`, `outlierDetection`).

High‑level steps:
1. Install Istio on **cluster‑A** and **cluster‑B** with matching mesh config (`meshID`, `trustDomain`) and per‑cluster `network` value.
2. Deploy **east‑west gateways** and expose **15443** for SNI passthrough.
3. **Exchange remote secrets** so each control plane watches the other cluster’s API server.
4. Verify cross‑cluster calls; keep traffic local by default and fail over when endpoints are unhealthy.

---

## Traffic management kinds (HTTP/HTTPS & gRPC)

Two API surfaces (pick one per org for consistency):

### A) **Istio APIs** (mature)
- **Gateway** (edge & east‑west L4/L7 entry)
- **VirtualService** (HTTP/1.1, **HTTP/2/gRPC**, TCP routing)
- **DestinationRule** (subsets, mTLS, retries, outlier detection, locality)

### B) **Kubernetes Gateway API** (future‑leaning)
- **GatewayClass/Gateway** + **HTTPRoute** for HTTP/HTTPS
- **GRPCRoute** for gRPC (match by service/method/headers)

**Gateway API example (GRPCRoute)**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata: { name: greeter, namespace: default }
spec:
  parentRefs: [{ name: public-gw, namespace: istio-system }]
  hostnames: ["greeter.example.com"]
  rules:
  - matches:
    - method:
        service: "helloworld.Greeter"
        method: "SayHello"
    backendRefs:
    - name: greeter
      port: 50051
```

---

## Go application design principles (for the mesh)

**Container & security**
- Use **distroless** or minimal base; run as **non‑root**; read‑only root FS.
- Add **liveness** (`/livez`) and **readiness** (`/readyz`) endpoints.
- Implement **graceful shutdown** on `SIGTERM` with a 30s timeout.

**Observability**
- Expose **Prometheus** metrics (`/metrics`) and **OpenTelemetry** traces.

**Tiny Go HTTP server (graceful shutdown + metrics)**
```go
mux := http.NewServeMux()
mux.Handle("/metrics", promhttp.Handler())
mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request){ w.WriteHeader(200) })
mux.HandleFunc("/livez",  func(w http.ResponseWriter, r *http.Request){ w.WriteHeader(200) })

srv := &http.Server{
  Addr:              ":8080",
  Handler:           mux,
  ReadHeaderTimeout: 5 * time.Second,
  IdleTimeout:       120 * time.Second,
}

go func() { _ = srv.ListenAndServe() }()

ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
defer stop()
<-ctx.Done()

shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()
_ = srv.Shutdown(shutdownCtx)
```

**Dockerfile (multi‑stage, distroless)**
```dockerfile
# build
FROM golang:1.22 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /out/app ./cmd/app

# run
FROM gcr.io/distroless/static
USER 65532:65532
COPY --from=build /out/app /app
EXPOSE 8080
ENTRYPOINT ["/app"]
```

---

## References & examples

- **EKS supported versions & lifecycle**: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html  
  **AL2 AMI note (1.33+)**: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html
- **Istio docs** (install, traffic mgmt): https://istio.io/latest/docs/  
  **Istio 1.27 release**: https://istio.io/latest/news/releases/1.27.x/announcing-1.27/  
  **Multi‑primary, multi‑network**: https://istio.io/latest/docs/setup/install/multicluster/multi-primary_multi-network/  
  **VirtualService ref**: https://istio.io/latest/docs/reference/config/networking/virtual-service/  
  **DestinationRule ref**: https://istio.io/latest/docs/reference/config/networking/destination-rule/  
  **Locality failover task**: https://istio.io/latest/docs/tasks/traffic-management/locality-load-balancing/failover/
- **Gateway API**:  
  **GRPCRoute spec**: https://gateway-api.sigs.k8s.io/api-types/grpcroute/  
  **Gateway API reference**: https://gateway-api.sigs.k8s.io/reference/spec/  
  **gRPC routing guide**: https://gateway-api.sigs.k8s.io/guides/grpc-routing/
- **Cilium docs**:  
  **IPAM overview**: https://docs.cilium.io/en/stable/network/concepts/ipam/index.html  
  **ENI IPAM**: https://docs.cilium.io/en/stable/network/concepts/ipam/eni.html  
  **Configuring IPAM modes**: https://docs.cilium.io/en/stable/network/kubernetes/ipam.html
- **Karpenter v1**:  
  **NodeClasses**: https://karpenter.sh/docs/concepts/nodeclasses/  
  **NodePools**: https://karpenter.sh/docs/concepts/nodepools/
- **Secrets**:  
  **External Secrets Operator**: https://external-secrets.io/ and AWS provider: https://external-secrets.io/latest/provider/aws-secrets-manager/  
  **Secrets Store CSI Driver (AWS provider)**: https://aws.github.io/secrets-store-csi-driver-provider-aws/ and https://github.com/aws/secrets-store-csi-driver-provider-aws  
  **IRSA with ASCP**: https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_ascp_irsa.html
- **Pod Security Standards / Admission**:  
  https://kubernetes.io/docs/concepts/security/pod-security-standards/  
  https://kubernetes.io/docs/concepts/security/pod-security-admission/
- **AWS Load Balancer Controller**:  
  Helm install (AWS docs): https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html  
  Project docs: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- **Control plane logging + KMS encryption**:  
  EKS control plane logs: https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html  
  CloudWatch logs + KMS: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html  
  CLI `associate-kms-key`: https://docs.aws.amazon.com/cli/latest/reference/logs/associate-kms-key.html

---

### Appendix — Pod/Service CIDRs

- Pick **non‑overlapping** ranges across all environments and peered networks.
- With **Cilium cluster‑pool**, set `clusterPoolIpv4PodCidrList` (e.g., `100.64.0.0/11`).
- With **ENI** mode, Pod IPs come from your **VPC subnets** (size accordingly; consider prefix delegation).

