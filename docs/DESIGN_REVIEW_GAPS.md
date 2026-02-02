# Platform Design Review: Gaps, Outdated Software, and Weaknesses

**Review Date**: 2026-02-02 (Updated)
**Previous Review**: 2026-01-28
**Reviewed By**: Architecture Review
**Scope**: Complete platform design including Terraform, Kubernetes, Helm charts, services, CI/CD, and documentation

---

## Executive Summary

This is a **second-pass review** of the platform design. Some issues from the initial review have been addressed (EKS version updated to 1.34, Karpenter NodePools use v1 API, VPC module updated to v6.5.0, EKS module to v21.8.0). However, many issues remain unfixed, and this review identifies additional findings with accurate version comparisons against current stable releases.

**Severity scale**:
- **CRITICAL**: Must fix before production deployment
- **HIGH**: Address within 30 days
- **MEDIUM**: Address within 90 days
- **LOW**: Technical debt for future sprints

---

## 1. Outdated Software Versions

### 1.1 CRITICAL: Go Runtime - 4 Major Versions Behind

All Go services are severely outdated. Go 1.21 reaches end-of-life when Go 1.26 releases (expected Feb 2026). Go 1.22 is one release from EOL.

| Service | Current | Latest Stable | Versions Behind | EOL Risk |
|---------|---------|---------------|-----------------|----------|
| **hello-world** | Go 1.22 | Go 1.25.6 | 3 major | Near EOL |
| **dns-monitor** | Go 1.21 | Go 1.25.6 | 4 major | **Already EOL** |
| **failover-controller** | Go 1.21 | Go 1.25.6 | 4 major | **Already EOL** |
| **example-api** (Dockerfile) | Go 1.21-alpine | Go 1.25.6 | 4 major | **Already EOL** |

**Dependencies also outdated**:

| Dependency | Service | Current | Latest |
|-----------|---------|---------|--------|
| prometheus/client_golang | hello-world | v1.17.0 | v1.21.x+ |
| prometheus/client_golang | dns-monitor, failover | v1.19.0 | v1.21.x+ |
| miekg/dns | dns-monitor | v1.1.58 | v1.1.62+ |

**Impact**: Missing 3 years of security patches, Swiss Tables maps (60% faster), FIPS 140-3 support, and performance improvements.

**Action**: Upgrade all services to Go 1.25.x immediately.

### 1.2 CRITICAL: Helm Chart Versions - Significantly Behind

| Chart | Current | Latest | Versions Behind | Impact |
|-------|---------|--------|-----------------|--------|
| **kube-prometheus-stack** | ~65.3.0 | **81.4.2** | ~16 minor | Missing Prometheus 3.x features, bug fixes, CRD updates |
| **Thanos (Bitnami)** | ~15.7.0 | **17.3.1** | 2 major | Missing Thanos 0.40.x features, security fixes |
| **Loki** | ~6.6.0 | **6.51.0** | ~45 minor | Missing Loki 3.x improvements, schema updates |
| **Fluent Bit** | ~0.47.0 | **0.55.0** | 8 minor | Missing Fluent Bit 4.x, log processing improvements |
| **Tempo Distributed** | ~1.9.0 | Latest (Tempo 2.9) | Multiple | Missing Tempo 2.9 features, breaking changes |
| **OTel Collector** | ~0.96.0 | **0.143.0** | ~47 minor | Massive gap - missing critical collector improvements |
| **Pyroscope** | ~1.7.0 | Latest | Multiple | Missing profiling improvements |

**Most concerning**: OpenTelemetry Collector is ~47 versions behind. This is one of the fastest-moving projects in the CNCF ecosystem.

**Action**: Update all Helm chart dependencies. Test in dev first as kube-prometheus-stack and Thanos have breaking changes.

### 1.3 CRITICAL: External Secrets Operator - Entire Major Version Behind

| Component | Current | Latest | Gap |
|-----------|---------|--------|-----|
| **External Secrets chart** | v0.18.0 (appVersion v0.18.0) | **v1.3.1** (appVersion v1.2.1) | 1 full major version |
| **Dependency pin** | `"^0"` | Should be `"~1.3.0"` | Dangerously permissive |

**File**: `apps/infra/external-secrets/Chart.yaml:10`

The External Secrets Operator has graduated to **v1.x** with stable APIs. The current `v0.x` line is deprecated. The `"^0"` dependency constraint is extremely dangerous - it will match any `0.x.y` version but NOT the `1.x` line, leaving you permanently pinned to deprecated software.

**Additional concern**: The `unsafeServeV1Beta1` flag is being removed on **2026-05-01**, breaking v1beta1 API consumers.

**Action**: Upgrade to ESO v1.x and pin to `"~1.3.0"`.

### 1.4 HIGH: GitHub Actions - Outdated

**File**: `.github/workflows/well-architected.yml`

| Action | Current | Latest | Gap |
|--------|---------|--------|-----|
| **actions/checkout** | v3 | **v4** | 1 major |
| **aquasecurity/trivy-action** | **v0.12.0** | **v0.33.1** | 21 minor versions (2+ years old) |

Trivy v0.12.0 uses an ancient Trivy binary that lacks:
- Detection for thousands of newer CVEs
- Support for SBOM scanning
- OCI artifact scanning
- Next-gen Trivy features (arriving 2026)

**Action**: Update `actions/checkout@v4` and `trivy-action@v0.33.1`.

### 1.5 HIGH: Monitoring Module Version Drift

**File**: `terraform/modules/monitoring/prometheus.tf:7`

The Terraform monitoring module pins kube-prometheus-stack to `56.0.0`, while the Helm chart in `apps/infra/observability/prometheus-stack/Chart.yaml` references `~65.3.0`.

| Location | Version | Gap |
|----------|---------|-----|
| Terraform module | 56.0.0 | **25 versions behind** the Helm chart |
| Helm chart dependency | ~65.3.0 | 16 versions behind latest |

**Additional issue in monitoring module**:
```
adminPassword = "admin"  # Hardcoded default password
```
Line 36 of `prometheus.tf` contains a hardcoded Grafana admin password.

**Action**: Align versions and remove hardcoded password.

### 1.6 HIGH: PostgreSQL Version Behind

**File**: `terraform/modules/rds/postgres.tf:8`

| Component | Current | Latest on RDS | Gap |
|-----------|---------|---------------|-----|
| PostgreSQL | 15 | **17** | 2 major versions |

PostgreSQL 17 offers 2x better write throughput, improved WAL processing, better IN clause performance with B-tree indexes, and 20x less memory for vacuum operations. PostgreSQL 15 standard support ends in late 2027.

**Action**: Plan upgrade path to PostgreSQL 16 or 17.

### 1.7 MEDIUM: Azure Documentation - Severely Outdated

**File**: `docs/azure.md`

| Component | Documented | Current | Gap |
|-----------|-----------|---------|-----|
| Kubernetes (AKS) | **1.28.3** | 1.34+ | **6 minor versions behind** |
| Cilium | **1.14.5** | 1.16.x+ | 2 minor versions |
| VM size | Standard_DS2_v2 | Dv5/Ev5 series | Legacy VM series |

AKS 1.28 has already exited standard support. The documented version cannot be deployed on new clusters.

### 1.8 MEDIUM: Karpenter Minor Version Gap

| Component | Current | Latest | Gap |
|-----------|---------|--------|-----|
| Karpenter | 1.8.1 | **1.8.6** | 5 patch versions |

Note: Avoid v1.8.4 due to a known regression with TopologySpreadConstraint scheduling.

### 1.9 LOW: EKS Kubernetes Not Latest

| Component | Current | Latest | Gap |
|-----------|---------|--------|-----|
| EKS Kubernetes | 1.34 | **1.35** | 1 minor |

EKS 1.35 is now available. K8s 1.34 is still under standard support (14 months from release), so this is not urgent but should be planned.

---

## 2. Design Gaps (Remaining)

### 2.1 CRITICAL: EKS Cluster Endpoint Still Public

**File**: `terraform/modules/eks/main.tf:7`
```hcl
cluster_endpoint_public_access = true
```

**This was flagged in the previous review and remains unfixed.** Public API server access is the #1 attack vector for Kubernetes clusters.

**Action**: Set to `false` for production or add `cluster_endpoint_public_access_cidrs` to restrict access.

### 2.2 CRITICAL: Hardcoded Grafana Admin Password

**File**: `terraform/modules/monitoring/prometheus.tf:36`
```hcl
adminPassword = "admin"
```

Hardcoded credentials in IaC are a critical security risk. This will be committed to version control.

**Action**: Source from AWS Secrets Manager via External Secrets Operator.

### 2.3 HIGH: Missing Pod Security Standards

No Pod Security Admission (PSA) configuration exists anywhere in the codebase. With EKS 1.34, PSA is stable and should be enforced.

**Action**: Create namespace-level PSA labels enforcing `restricted` profile.

### 2.4 HIGH: Incomplete Network Policies

Still only 3 basic policies:
- `default-deny-all.yaml`
- `allow-dns-egress.yaml`
- `allow-from-same-namespace.yaml`

**Missing policies for**:
- Observability namespace (Prometheus scraping, Loki ingestion)
- Database tier isolation
- External egress whitelist
- Inter-namespace communication rules

### 2.5 HIGH: No Disaster Recovery Plan

No RTO/RPO targets, no cross-region failover, no tested recovery procedures. DNS failover components exist (dns-monitor, failover-controller) but are not integrated into a DR plan.

### 2.6 HIGH: No Secret Rotation Strategy

AWS Secrets Manager is configured but rotation is not automated. No Lambda rotation functions, no rotation schedules.

### 2.7 HIGH: Dockerfile Security Issues

**File**: `services/example-api/Dockerfile`
```dockerfile
FROM golang:1.21-alpine
WORKDIR /app
COPY . .
RUN go build -o api .
CMD ["./api"]
```

Multiple issues:
1. **Single-stage build** - final image contains Go toolchain, source code, and build artifacts
2. **No non-root user** - container runs as root
3. **No .dockerignore** - likely copies unnecessary files
4. **No health check** - Docker cannot determine container health
5. **Go 1.21** - EOL runtime

Compare with hello-world Dockerfile which correctly uses multi-stage builds.

**Action**: Adopt multi-stage build pattern, add non-root user, add HEALTHCHECK.

### 2.8 MEDIUM: No GitOps for Infrastructure

ArgoCD manages applications but Terraform/Terragrunt changes are manual. No Atlantis, Spacelift, or env0 integration.

### 2.9 MEDIUM: Missing Kubernetes Backup (Velero)

No Velero or equivalent for:
- Kubernetes resource backup
- PersistentVolume snapshots
- Namespace disaster recovery
- Migration between clusters

### 2.10 MEDIUM: RDS `skip_final_snapshot = true`

**File**: `terraform/modules/rds/postgres.tf:29`

Even with the comment "set false for prod", there's no variable or environment-based logic to enforce this. A production deployment using defaults would skip the final snapshot.

**Action**: Default to `false` and require explicit opt-in for dev environments.

---

## 3. Architectural Weaknesses

### 3.1 HIGH: Single Region Design

All infrastructure targets `us-east-1` with no multi-region capability. A regional outage means complete service unavailability.

### 3.2 HIGH: Observability Version Fragmentation

Two separate Prometheus stack versions exist:
- Terraform module: `kube-prometheus-stack 56.0.0` with 15-day retention
- Helm chart: `kube-prometheus-stack ~65.3.0` with 2-hour retention

This creates confusion about which is the source of truth and risks deploying different configurations.

### 3.3 HIGH: No Connection Pooling for PostgreSQL

No PgBouncer or RDS Proxy configured. With Kubernetes pods scaling dynamically via Karpenter/HPA, connection exhaustion is a real risk. Each pod creates its own DB connections.

**Action**: Add RDS Proxy or deploy PgBouncer as a sidecar/service.

### 3.4 MEDIUM: Spot Instance Risk Profile

| NodePool | Spot % | Risk |
|----------|--------|------|
| x86-general | 80% | Medium - broad instance family diversity helps |
| arm64-graviton | mixed | Medium |
| c-series-compute | 70% | High - narrow instance family (c-series only) |
| spot-flexible | 100% | High - no on-demand fallback |

The c-series pool is especially risky: limiting to only `c7i, c7a, c6i, c6a, c6in` with 70% spot reduces the available capacity pool significantly.

### 3.5 MEDIUM: Karpenter Controller on t3.medium

**File**: `terraform/modules/eks/variables.tf:26`
```hcl
default = ["t3.medium"]  # 2 vCPU, 4 GiB
```

For clusters targeting 1,000-5,000 nodes, t3.medium may be undersized for the Karpenter controller and system pods. Karpenter's scheduling decisions become more resource-intensive at scale.

**Action**: Use m5.large or m6i.large for controller nodes at scale.

### 3.6 LOW: No Blue-Green/Canary Deployment Infrastructure

No Argo Rollouts, Flagger, or traffic splitting configuration exists.

---

## 4. Outdated Tools and Techniques

### 4.1 HIGH: Azure Documentation Uses Deprecated Patterns

**Multiple deprecated patterns in `docs/azure.md`**:

| Pattern | Status | Replacement |
|---------|--------|-------------|
| AAD Pod Identity | **Deprecated** | Azure AD Workload Identity |
| `istioctl install` operator method | Legacy | Helm-based Istio install |
| Standard_DS2_v2 VMs | Legacy series | Dv5/Ev5 series |
| AKS 1.28.3 | **Out of support** | AKS 1.33+ |
| `network_policy = "calico"` (commented) | Outdated with Cilium | Cilium native policy |

### 4.2 HIGH: Fluent Bit Image Pin vs Chart Version Mismatch

**Loki stack values** pin Fluent Bit image to `fluent/fluent-bit:3.1.9`, while the Helm chart version is `~0.47.0`. The latest Fluent Bit is **4.x** (with chart `0.55.0`). Running 3.1.9 when 4.x is available means missing significant log processing improvements.

### 4.3 MEDIUM: No Service Mesh Decision

Documentation mentions "optional Istio or Linkerd" with Cilium also providing some mesh features. No clear architectural decision record (ADR) exists. With Cilium already deployed for CNI, Cilium Service Mesh may be the natural choice, eliminating the need for a separate mesh.

### 4.4 MEDIUM: No cert-manager

ACM handles external certificates but no cert-manager exists for:
- Internal mTLS certificates
- Webhook certificates
- Service-to-service TLS

### 4.5 MEDIUM: Missing eBPF Security Tools

Cilium is deployed for networking but security-specific eBPF tools are absent:
- **Tetragon** - runtime security enforcement (same Cilium ecosystem)
- **Falco** with eBPF driver - threat detection
- **KubeArmor** - application-aware security

### 4.6 LOW: `eksctl` in DR Procedures

**File**: `docs/observability-architecture.md:767`
```bash
eksctl create cluster -f cluster.yaml
```

DR documentation references `eksctl` for cluster creation, but the platform uses Terraform/Terragrunt for IaC. DR procedures should use the same tooling as regular operations.

---

## 5. Security Concerns

### 5.1 CRITICAL: EKS Public Endpoint (unchanged from previous review)

`cluster_endpoint_public_access = true` at `terraform/modules/eks/main.tf:7`

### 5.2 CRITICAL: Hardcoded Credentials

`adminPassword = "admin"` at `terraform/modules/monitoring/prometheus.tf:36`

### 5.3 HIGH: Trivy Scanner Severely Outdated

Trivy action v0.12.0 (from 2023) cannot detect CVEs published after its release. The vulnerability database is fetched at runtime, but the scanner engine itself is missing detection capabilities for newer vulnerability classes.

### 5.4 HIGH: No SBOM Generation in CI/CD

No Syft, Grype, or Trivy SBOM generation step in any workflow.

### 5.5 HIGH: example-api Runs as Root

The example-api Dockerfile has no `USER` directive, meaning the container runs as root. Combined with the single-stage build that includes the entire Go toolchain, this is a significant attack surface.

### 5.6 MEDIUM: No WAF Rules Defined

AWS WAF mentioned in architecture docs but no rule definitions, no managed rule groups, no custom rules.

### 5.7 MEDIUM: Incomplete Audit Logging

No EKS audit log configuration. No audit policy for sensitive Kubernetes API operations.

### 5.8 MEDIUM: No Network Encryption Enforcement

While IRSA is configured (good), there's no enforcement of:
- TLS for all inter-service communication
- Encryption in transit for S3/RDS connections
- mTLS between microservices

---

## 6. Documentation Gaps

### 6.1 HIGH: Inconsistent Maintainer Emails

Helm chart maintainers use different email domains:
- `platform@example.com` (prometheus-stack)
- `platform@company.com` (loki-stack, tempo)
- `platform@gaming.com` (otel-collector)
- `platform@gaming-company.com` (pyroscope)

This suggests these are placeholder values, not real contacts.

### 6.2 MEDIUM: Missing ADRs

No Architecture Decision Records for major choices: Karpenter vs CAS, Loki vs Elasticsearch, Cilium vs Calico, PostgreSQL vs Aurora.

### 6.3 MEDIUM: Missing Operational Runbooks

Only DNS-related runbooks and a general SRE runbook exist. Missing:
- Database failover procedures
- Kafka/Redis recovery
- Observability stack failure
- Node drain procedures
- Incident response playbook

---

## 7. Summary of Changes Since Last Review

### Fixed Since 2026-01-28
- EKS version updated to 1.34 (was incorrectly 1.33 in some places)
- Karpenter NodePools use v1 API (not v1beta1)
- VPC module updated to v6.5.0
- EKS module updated to v21.8.0
- Comprehensive Karpenter NodePool configurations added

### Remains Unfixed
- EKS public endpoint still enabled
- Go versions still at 1.21/1.22
- Trivy action still at v0.12.0
- actions/checkout still at v3
- External Secrets still at v0.18.0 with `"^0"` pin
- Hardcoded Grafana password in Terraform
- No Pod Security Standards
- Only 3 network policies
- No DR plan, no secret rotation
- Azure docs still reference AKS 1.28.3

---

## 8. Consolidated Statistics

| Category | Critical | High | Medium | Low | Total |
|----------|----------|------|--------|-----|-------|
| Outdated Software | 3 | 4 | 2 | 1 | 10 |
| Design Gaps | 2 | 5 | 3 | 0 | 10 |
| Architecture Weaknesses | 0 | 3 | 3 | 1 | 7 |
| Outdated Tools/Techniques | 0 | 2 | 3 | 1 | 6 |
| Security Concerns | 2 | 3 | 3 | 0 | 8 |
| Documentation Gaps | 0 | 1 | 2 | 0 | 3 |
| **Total** | **7** | **18** | **16** | **3** | **44** |

---

## 9. Priority Remediation Roadmap

### Immediate (Week 1) - CRITICAL

1. Set `cluster_endpoint_public_access = false` or add CIDR restrictions
2. Remove hardcoded `adminPassword = "admin"` from Terraform
3. Upgrade Go services to 1.25.x (1.21 is EOL)
4. Update External Secrets Operator to v1.x line
5. Update kube-prometheus-stack from ~65.3.0 toward 81.x

### Week 2-3 - HIGH

1. Update `trivy-action` from v0.12.0 to v0.33.1
2. Update `actions/checkout` from v3 to v4
3. Fix example-api Dockerfile (multi-stage, non-root user)
4. Upgrade PostgreSQL from 15 to 16 or 17
5. Align Terraform monitoring module version with Helm chart
6. Add comprehensive network policies
7. Implement Pod Security Admission
8. Add connection pooling (RDS Proxy or PgBouncer)
9. Document DR procedures with RTO/RPO

### Month 2 - MEDIUM

1. Update Loki chart (~6.6.0 to ~6.51.0)
2. Update OTel Collector chart (~0.96.0 to ~0.143.0)
3. Update Fluent Bit chart and image to 4.x
4. Update Thanos chart (~15.7.0 to ~17.3.0)
5. Update Azure documentation (AKS 1.34, Cilium 1.16, remove deprecated patterns)
6. Deploy cert-manager
7. Implement secret rotation with Lambda
8. Deploy Velero for K8s backup
9. Implement WAF rules
10. Create ADRs

### Month 3 - LOW

1. Upgrade EKS to 1.35
2. Evaluate Tetragon/Falco for runtime security
3. Implement Argo Rollouts for canary deployments
4. Deploy OpenCost
5. Fix maintainer emails in Helm charts

---

## 10. Version Reference Table (as of 2026-02-02)

| Component | In Platform | Latest Stable | Gap Severity |
|-----------|------------|---------------|-------------|
| Go | 1.21 / 1.22 | **1.25.6** | CRITICAL |
| EKS | 1.34 | 1.35 | LOW |
| Karpenter | 1.8.1 | 1.8.6 | MEDIUM |
| kube-prometheus-stack | ~65.3.0 | 81.4.2 | CRITICAL |
| Thanos (Bitnami) | ~15.7.0 | 17.3.1 | HIGH |
| Loki | ~6.6.0 | 6.51.0 | MEDIUM |
| Fluent Bit | ~0.47.0 | 0.55.0 | MEDIUM |
| Tempo Distributed | ~1.9.0 | Latest (2.9) | MEDIUM |
| OTel Collector | ~0.96.0 | 0.143.0 | CRITICAL |
| Pyroscope | ~1.7.0 | Latest | MEDIUM |
| External Secrets | 0.18.0 | **1.3.1** | CRITICAL |
| PostgreSQL (RDS) | 15 | 17 | HIGH |
| trivy-action | 0.12.0 | 0.33.1 | HIGH |
| actions/checkout | v3 | v4 | HIGH |
| Terraform EKS module | 21.8.0 | 21.15.1 | LOW |
| kube-prometheus-stack (TF) | 56.0.0 | 81.4.2 | HIGH |

---

*This review should be updated quarterly or when major platform changes occur.*
*Next scheduled review: 2026-05-01*
