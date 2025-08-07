# Designing a US‑Wide Telemetry Platform on Amazon EKS (1 000 – 5 000 nodes)

A blueprint‑style design dossier for a Datadog‑like telemetry collection service, purpose‑built for **Amazon EKS**, **Kafka**, and **InfluxDB**. Use it as follow‑up material in interviews to showcase large‑scale Kubernetes craftsmanship.

---

## Table of Contents

1. [Cluster Scope & Control‑Plane Hardening](#1-cluster-scope--control-plane-hardening)
2. [Network Architecture & Connectivity](#2-network-architecture--connectivity)
3. [Node Scaling with Karpenter](#3-node-scaling-with-karpenter)
4. [Pod Autoscaling with KEDA + Metrics‑Server](#4-pod-autoscaling-with-keda--metrics-server)
5. [Workload Isolation](#5-workload-isolation)
6. [Health & Resilience](#6-health--resilience)
7. [Cloud‑Native & 12‑Factor Alignment](#7-cloud-native--12-factor-alignment)
8. [Observability & Cost Guard‑Rails](#8-observability--cost-guard-rails)
9. [Security](#9-security)
10. [Interview‑Ready Talking Points](#10-interview-ready-talking-points)
11. [References](#11-references)

---

## 1. Cluster Scope & Control‑Plane Hardening

| Item             | Decision                                                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **Blast‑radius** | One ultra‑scale EKS cluster per AWS Region (`us‑east‑1`) to simplify Kafka replication and reduce latency.               |
| **EKS limits**   | Tuned for **5 000 nodes** per AWS *Ultra‑Scale* guidance—vertical control‑plane boosts plus **API Priority & Fairness**. |
| **etcd hygiene** | Hourly compaction / weekly defrag; keep DB < 8 GiB for low latency.                                                      |
| **Network CIDR** | VPC `/16` with **VPC CNI prefix delegation** (/28 per ENI) to avoid ENI exhaustion at 100 k+ pods.                       |

---

## 2. Network Architecture & Connectivity

### 2.1 VPC & Subnet Layout

- `/16` VPC carved into:
  - **Private‑Pods** (/18 per AZ)
  - **Private‑Services** (/20 per AZ)
  - **Private‑Storage** (/21 per AZ)
  - **Public‑Ingress** (/24 per AZ) — strictly for NLB/ALB.
- Enable **VPC CNI prefix delegation**; target 16 IPs per ENI, giving ≈120 pods/ENI.

### 2.2 Ingress / Egress Path

| Path               | Component                                                                     | Notes                                                    |
| ------------------ | ----------------------------------------------------------------------------- | -------------------------------------------------------- |
| External → Cluster | **AWS Global Accelerator** → ALB (TLS termination) → Envoy ingress            | Any‑cast entry, low latency nationwide.                  |
| Cluster → Internet | NAT Gateway (per AZ) for egress; PrivateLink for AWS services (S3, STS, ECR). |                                                          |
| Partner VPN/DC     | Direct Connect + Transit Gateway → Private ALB                                | Keeps partner telemetry private, avoids public Internet. |

### 2.3 Service Networking

- **Cilium** eBPF CNI (addon) for high‑scale pod routing, NetworkPolicy, and transparent encryption.
- **NodeLocal DNSCache** on every node; CoreDNS HPA (CPU+QPS) keeps P99 < 30 ms.
- **Cilium Cluster Mesh** enabled to optimise cross‑AZ flows.

### 2.4 Security Boundaries

- Default **deny‑all** Cilium policy; allow via namespace & service selectors.
- **Security Group for Pod** feature on Kafka / InfluxDB to open minimal inbound ports (9092, 8086).
- AWS WAF on ALB defends HTTP ingest endpoints; rate‑limits abusive IPs.

### 2.5 IP & Capacity Monitoring

- **AWS VPC IPAM** alerts at 80 % CIDR usage.
- Prometheus scrape `cilium_ipam_ips` & `aws_vpc_ipam_pool_available_ips` → Grafana script sends Slack page when <15 % free.
- **Karpenter **`` triggers auto‑scale if IP pressure >90 %.

### 2.6 DNS & Service Discovery

- External clients: `telemetry.api.example.com` → Global Accelerator.
- Internal: Cluster DNS. Split‑horizon view to prevent internal pods leaking private hostnames.

### 2.7 L7 Traffic Shaping

- **Envoy RateLimit** service uses Redis to provide per‑tenant quotas (API‑key based).
- PriorityClass maps to Envoy priority so `system-node-critical` bypasses rate‑limit in outage.

> **Outcome:** End‑to‑end encrypted, IP‑efficient, multi‑AZ network capable of 100 Gbps+ ingest while staying within ENI, IP, and latency targets.

---

## 3. Node Scaling with **Karpenter**

### Why Karpenter?

- Sub‑minute launches.
- Heterogeneous instance mix via a single *Provisioner*.
- Built‑in consolidation → ≈30 % compute savings.

| Provisioner     | Purpose                   | Key Constraints                                                           |
| --------------- | ------------------------- | ------------------------------------------------------------------------- |
| `spot‑ingest`   | Edge HTTP/GRPC collectors | `capacityType=spot`, `instanceFamily=[m7g,r7g]`, disruption budget 15 min |
| `ondemand‑core` | Kafka brokers, InfluxDB   | `capacityType=on‑demand`, critical toleration, zones = all                |
| `gpu‑ml`        | ML anomaly detection      | `accel=gpu`, `arch=arm64,x86_64`                                          |

> **Scale record:** AWS 2025 ultra‑scale test: **2 000 nodes/min** join rate; 100 k node drain in 4 h.

---

## 4. Pod Autoscaling with **KEDA + Metrics‑Server**

### 4.1 HTTP RPS Scaler (example)

```yaml
triggers:
- type: prometheus
  metadata:
    serverAddress: http://thanos-query:9090
    query: |
      sum(irate(istio_requests_total{service="telemetry-ingest"}[1m]))
    threshold: "800"              # total RPS target for deployment
    activationThreshold: "100"   # scale from zero after 100 RPS
```

Replica formula: `replicas = ceil(total_RPS / 200)` (200 RPS safe per pod).

### 4.2 Other Scalers

| Workload        | Trigger                               | Logic                        |
| --------------- | ------------------------------------- | ---------------------------- |
| Kafka consumers | `kafka‑lag`                           | 1 consumer → every 2 000 lag |
| InfluxDB ingest | `prometheus` (`write_requests_total`) | 1 pod → 5 000 writes/s       |

---

## 5. Workload Isolation

| Layer                      | Primitive                                                                                  | Rationale                                       |
| -------------------------- | ------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| **QoS**                    | `Guaranteed`: Kafka/InfluxDB`Burstable`: API`BestEffort`: batch                            | Avoids eviction of stateful tiers.              |
| **PriorityClass**          | `system-node-critical` (10 000)`platform-core` (9 000)`ingest` (5 000)`background` (1 000) | Scheduler + APF respect priority.               |
| **Taints/Tolerations**     | `db=true:NoSchedule` on `ondemand‑core` nodes                                              | Brokers never land on spot.                     |
| **Affinity/Anti‑Affinity** | Hard zone anti‑affinity for Kafka & InfluxDB                                               | One replica per AZ; protects against AZ outage. |

---

## 6. Health & Resilience

- **Readiness probes**: Kafka `/healthz?ready` (fails if ISR < 3).
- **Startup probes**: 5‑min grace for InfluxDB WAL replay.
- **Node‑Problem‑Detector**: Emits NodeCondition → Karpenter spins replacement.
- **PodDisruptionBudgets**: `minAvailable` ≥ `replicas‑1` for storage tiers.

---

## 7. Cloud‑Native & 12‑Factor Alignment

| 12‑Factor            | Implementation                                                     |
| -------------------- | ------------------------------------------------------------------ |
| **Codebase**         | Mono‑repo. Services in `/cmd`, Terraform + Helm alongside.         |
| **Config**           | AWS Parameter Store + `secrets‑store‑csi`.                         |
| **Backing services** | Kafka, InfluxDB, OpenTelemetry Collector as Helm releases.         |
| **Concurrency**      | Horizontal scaling only; no shared state.                          |
| **Logs**             | STDOUT → Fluent Bit → Amazon OpenSearch.                           |
| **Disposability**    | Boot < 30 s; enables Karpenter consolidation & KEDA scale‑to‑zero. |

---

## 8. Observability & Cost Guard‑Rails

- **Prometheus + Thanos** shards (functional split) with S3 object storage.
- **Loki** for logs, **Tempo** for traces.
- Cost sidecar publishes AWS Cost Explorer metrics; KEDA scales down low‑ROI dev workloads nightly.

---

## 9. Security

- **IRSA** only—no node IAM keys.
- **OPA / Gatekeeper** policies: require readiness probes, disallow `:latest` tags, forbid `hostPID`.
- **mTLS** via **SPIRE**.

---

## 10. Interview‑Ready Talking Points

1. Control‑plane scaling & API Priority & Fairness.
2. End‑to‑end network design: prefix delegation, Cilium overlay, Global Accelerator.
3. Karpenter vs. Cluster Autoscaler for ultra‑scale.
4. Real‑metric (HTTP RPS) autoscaling pipeline: request → pod → node.
5. QoS + Priority for multi‑tenant SLOs.
6. Zone‑aware anti‑affinity for stateful sets.
7. 12‑Factor compliance enabling infra agility.
8. Cost levers: spot pools, scale‑to‑zero, Karpenter consolidation.

---

## 11. References

1. AWS Blog: **“Under the hood: Amazon EKS ultra‑scale clusters”** (Jul 2025).
2. AWS Docs: **“Scale cluster compute with Karpenter.”**
3. AWS Docs

