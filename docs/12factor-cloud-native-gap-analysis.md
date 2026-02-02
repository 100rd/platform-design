# 12-Factor & Cloud-Native Gap Analysis

Gap analysis of the current platform design against 12-factor methodology and
cloud-native requirements for Go applications running on EKS.

---

## Summary

| Area | Gaps Found |
|------|-----------|
| Helm App Chart | 10 (critical) |
| Container Build Pipeline | 4 |
| Backing Services | 3 |
| Cluster-Level Resilience | 3 |
| Observability Integration | 2 |
| Admin Processes | 2 |
| Dockerfile Standards | 2 |
| GOMAXPROCS Automation | 1 |

---

## 1. Helm App Chart (`helm/app/`) - Critical Gaps

The generic application Helm chart is missing most cloud-native primitives.
Applications deploying through this chart will lack the following capabilities
unless teams manually add them.

### 1.1 No Health Probes

**12-Factor**: Disposability (fast startup detection)
**Cloud-Native**: `/healthz`, `/readyz` endpoints

The deployment template has no `livenessProbe` or `readinessProbe` defined.
Kubernetes cannot determine if a pod is alive or ready to accept traffic.

**Impact**: Pods that crash or hang will continue receiving traffic. Rolling
updates cannot verify new pods are healthy before terminating old ones.

**Fix**: Add configurable probes to `deployment.yaml`:

```yaml
livenessProbe:
  httpGet:
    path: {{ .Values.probes.liveness.path | default "/healthz" }}
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: {{ .Values.probes.readiness.path | default "/readyz" }}
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
```

### 1.2 No Resource Requests/Limits

**12-Factor**: Concurrency (proper scaling signals)
**Cloud-Native**: Resource limits required by Gatekeeper

The deployment template has no `resources` block. While Gatekeeper enforces
resource limits via policy, the Helm chart itself provides no defaults or
configuration surface.

**Impact**: Pods scheduled without requests will get best-effort QoS class.
Karpenter cannot accurately right-size nodes. HPA CPU-based scaling will not
function without resource requests.

**Fix**: Add resources to `values.yaml` and `deployment.yaml`:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

### 1.3 No Security Context

**12-Factor**: N/A
**Cloud-Native**: Run as non-root, read-only filesystem

No `securityContext` at pod or container level. Gatekeeper's `restricted` PSA
will reject pods without proper security context, meaning every team must add
this manually.

**Impact**: Deployments will be rejected by admission control in namespaces with
`restricted` Pod Security Admission labels unless teams add security context
per-service.

**Fix**: Add pod and container security context with sane defaults:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 65534
  fsGroup: 65534
  seccompProfile:
    type: RuntimeDefault
containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```

### 1.4 No Graceful Shutdown Configuration

**12-Factor**: Disposability (graceful shutdown on SIGTERM)
**Cloud-Native**: Drain connections before termination

The deployment template has no `terminationGracePeriodSeconds` (defaults to 30s
which may be acceptable) and critically no `preStop` lifecycle hook. On
Kubernetes, SIGTERM and endpoint removal happen simultaneously, causing
in-flight requests to fail during rolling updates.

**Impact**: Active requests will be dropped during deployments and scale-down
events. This is particularly critical with ALB target groups where
deregistration delay must align with pod termination.

**Fix**: Add lifecycle hook to allow load balancer deregistration:

```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 5"]
terminationGracePeriodSeconds: 35
```

### 1.5 No ServiceAccount Configuration

**12-Factor**: Backing services (AWS access via IRSA)
**Cloud-Native**: Least-privilege identity per workload

The deployment template has no `serviceAccountName` field. Applications
requiring AWS access (S3, SQS, DynamoDB, Secrets Manager) have no way to use
IRSA through the standard chart.

**Impact**: Teams must either create custom deployment manifests or use node-level
IAM roles, violating least-privilege principles.

**Fix**: Add ServiceAccount template and IRSA annotation support:

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: ""
```

### 1.6 No PodDisruptionBudget

**12-Factor**: Disposability
**Cloud-Native**: Availability during voluntary disruptions

No PDB template exists. Node drains, cluster upgrades, and Karpenter
consolidation can terminate all replicas of a service simultaneously.

**Impact**: Complete service outage during node maintenance, Karpenter
consolidation, or Kubernetes version upgrades.

**Fix**: Add `pdb.yaml` template:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 1  # or maxUnavailable: 25%
```

### 1.7 No Topology Spread / Anti-Affinity

**12-Factor**: Concurrency (scale across failure domains)
**Cloud-Native**: AZ distribution, node spreading

No `topologySpreadConstraints` or `affinity` configuration. All replicas can
land on the same node or AZ.

**Impact**: Single node or AZ failure takes down all replicas. Defeats the
purpose of running multiple replicas.

**Fix**: Add default topology spread:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels: ...
```

### 1.8 No ServiceMonitor / PodMonitor

**12-Factor**: Logs (observable processes)
**Cloud-Native**: `/metrics` scraping via Prometheus

The Prometheus stack is deployed with ServiceMonitor discovery enabled across
all namespaces, but the app Helm chart provides no ServiceMonitor template.
Each team must create their own.

**Impact**: Application metrics are not collected unless teams manually create
ServiceMonitor resources. Prometheus cannot auto-discover application metrics.

**Fix**: Add `servicemonitor.yaml` template:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
spec:
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

### 1.9 No HorizontalPodAutoscaler

**12-Factor**: Concurrency (scale via process count)
**Cloud-Native**: Auto-scale on load

KEDA and HPA infrastructure exist at cluster level, but the app chart has no
HPA template. Applications cannot auto-scale without custom manifests.

**Impact**: Applications remain at static replica count regardless of load.
Manual scaling only.

**Fix**: Add `hpa.yaml` template with CPU/memory and custom metric support.

### 1.10 No NetworkPolicy

**12-Factor**: Backing services (explicit service communication)
**Cloud-Native**: Zero-trust networking

Default-deny NetworkPolicies exist at cluster level (`kubernetes/network-policies/`),
but the app chart has no per-application NetworkPolicy template. Applications
are denied all traffic by default with no way to open required paths through the
standard chart.

**Impact**: Applications deployed via this chart will have no network connectivity
due to default-deny policies, unless teams create NetworkPolicy resources
manually.

**Fix**: Add `networkpolicy.yaml` template allowing ingress on service port and
configurable egress rules.

---

## 2. Container Build Pipeline Gaps

### 2.1 No ECR Repository Terraform Module

There is no Terraform module for creating ECR repositories. Teams have no
standardized way to provision container registries with:
- Image scanning on push
- Lifecycle policies for image retention
- Cross-account pull permissions
- Immutable image tags enforcement

**Fix**: Create `terraform/modules/ecr/` module with scanning, lifecycle rules,
and immutability enabled by default.

### 2.2 No Container Image Scanning

No Trivy, Grype, or ECR native scanning is configured in CI pipelines. The
`go-ci.yml` workflow builds Go binaries but does not build or scan container
images.

**Impact**: Vulnerable base images and dependencies ship to production
undetected.

**Fix**: Add image scanning to CI pipeline (Trivy action or ECR scan-on-push).

### 2.3 No Standardized Dockerfile Template

Existing Dockerfiles are inconsistent:
- `services/example-api/Dockerfile`: Single-stage, runs as root, uses `golang:1.21-alpine`
- `services/hello-world/Dockerfile`: Multi-stage but final stage is `alpine` running as `root`

Neither follows the container best practices from the requirements (distroless/
scratch base, non-root user, specific tags).

**Impact**: Containers run as root, include unnecessary OS packages, and have
larger attack surface.

**Fix**: Provide a reference Dockerfile:

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /app/server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

### 2.4 No Container Build Workflow

The GitHub Actions CI (`go-ci.yml`) runs `go build` and `go test` but does not
build container images, push to ECR, or trigger Kargo warehouses. The full
build-release-run separation (12-factor #5) is incomplete.

**Fix**: Add a container build workflow that builds, scans, tags with git SHA,
and pushes to ECR.

---

## 3. Backing Services Gaps

### 3.1 No Redis/ElastiCache Module

**12-Factor**: Backing services (cache as attached resource), Processes (external state)

The requirements specify Redis for stateless process state, but no ElastiCache
Terraform module exists. Applications needing caching or session storage have no
standardized infrastructure.

**Fix**: Create `terraform/modules/elasticache/` module.

### 3.2 No SQS/SNS Module

**12-Factor**: Backing services (queues as attached resources)

KEDA is configured with SQS trigger support, but there is no Terraform module
to provision SQS queues or SNS topics. Teams cannot provision message queues
through the platform.

**Fix**: Create `terraform/modules/sqs/` module with DLQ, encryption, and IRSA
policy outputs.

### 3.3 No S3 Bucket Module for Application Use

S3 is used by platform components (Thanos, Loki, Velero) but no reusable
module exists for application teams to provision S3 buckets with encryption,
versioning, and IRSA-scoped access policies.

**Fix**: Create `terraform/modules/s3-app/` module.

---

## 4. Cluster-Level Resilience Gaps

### 4.1 No Service Mesh or Sidecar Proxy

**Cloud-Native**: Circuit breakers, retries with backoff, mTLS

The requirements list circuit breakers and retries for downstream services. The
platform has no service mesh (Istio, Linkerd) or Envoy sidecar injection. All
resilience patterns (timeouts, retries, circuit breaking) must be implemented
in application code.

This is an architectural decision rather than a strict gap — implementing
resilience in-code with Go libraries (e.g., `sony/gobreaker`,
`hashicorp/go-retryablehttp`) is valid. However, it means:
- No mutual TLS between services (unless Cilium network encryption is enabled)
- No centralized traffic policy management
- Each team must implement resilience correctly

**Recommendation**: Evaluate whether Cilium service mesh (already noted in the
stack) or a lightweight proxy like Linkerd would reduce per-team burden.

### 4.2 No Rate Limiting / Traffic Shaping

No ingress-level rate limiting is configured. The AWS LB Controller is deployed
but no default rate limiting, WAF integration, or traffic shaping policies
exist.

**Fix**: Add AWS WAF integration with ALB controller or deploy an API gateway
for rate limiting.

### 4.3 No Pod Priority Classes

No PriorityClass resources are defined. During resource contention, Kubernetes
cannot make informed preemption decisions. Platform components (monitoring,
ingress) should have higher priority than application workloads.

**Fix**: Create PriorityClass resources:
- `system-critical` (1000000) for platform components
- `high-priority` (100000) for production workloads
- `default` (0) for general workloads
- `batch` (-100) for batch/admin jobs

---

## 5. Observability Integration Gaps

### 5.1 No OpenTelemetry Auto-Instrumentation

The OTEL Collector is deployed, but there is no auto-instrumentation webhook
for Go applications. Each application must manually integrate the OTEL SDK.

**Fix**: Deploy the OpenTelemetry Operator with `Instrumentation` CRDs for
automatic trace/metric injection via pod annotations.

### 5.2 No Grafana Dashboard Templates for Applications

Grafana dashboards exist for platform components, but no template dashboard is
provided for application teams. Standard RED metrics (Rate, Errors, Duration)
dashboards should be provided as part of the app Helm chart or as a
ConfigMap-based dashboard.

**Fix**: Add a standard Go application Grafana dashboard JSON as a ConfigMap in
the app Helm chart.

---

## 6. Admin Process Gaps

### 6.1 No Job/CronJob Template

**12-Factor**: Admin processes (run as one-off containers)

The Helm chart has no Job or CronJob template. Database migrations, data
backups, and one-off admin tasks have no standardized deployment path.

**Fix**: Add `job.yaml` and `cronjob.yaml` templates to the app Helm chart.

### 6.2 No Database Migration Strategy

The RDS module provisions PostgreSQL, but there is no migration Job template
or init-container pattern for running schema migrations. Migrations should run
as Kubernetes Jobs before deployment, not as part of application startup.

**Fix**: Add migration Job template with `helm.sh/hook: pre-install,pre-upgrade`
annotation or an init-container pattern in the deployment.

---

## 7. GOMAXPROCS Automation

### 7.1 No `automaxprocs` Enforcement

**Cloud-Native**: Set GOMAXPROCS to match CPU limits

Go's runtime defaults `GOMAXPROCS` to the host CPU count, not the container's
CPU limit. On nodes with 16+ cores where a pod is limited to 500m CPU, this
causes excessive goroutine scheduling overhead.

The platform provides no mechanism to enforce this — it must be done per-app
by importing `go.uber.org/automaxprocs` or setting `GOMAXPROCS` env var.

**Recommendation**: Document as a required dependency for all Go services, or
inject `GOMAXPROCS` via a mutating webhook based on resource limits.

---

## 8. Gap Priority Matrix

| Priority | Gap | Effort |
|----------|-----|--------|
| P0 | Health probes in Helm chart | Low |
| P0 | Resource requests/limits in Helm chart | Low |
| P0 | Security context in Helm chart | Low |
| P0 | ServiceAccount + IRSA in Helm chart | Low |
| P0 | Graceful shutdown (preStop + terminationGrace) | Low |
| P1 | PodDisruptionBudget template | Low |
| P1 | Topology spread constraints | Low |
| P1 | NetworkPolicy template | Medium |
| P1 | Fix existing Dockerfiles (non-root, distroless) | Low |
| P1 | ECR module with scanning | Medium |
| P1 | Container build CI workflow | Medium |
| P1 | ServiceMonitor template | Low |
| P2 | HPA template | Low |
| P2 | Job/CronJob templates | Low |
| P2 | PriorityClass resources | Low |
| P2 | ElastiCache module | Medium |
| P2 | SQS module | Medium |
| P2 | S3 app module | Medium |
| P3 | OTEL auto-instrumentation operator | Medium |
| P3 | Grafana app dashboard template | Medium |
| P3 | Service mesh evaluation | High |
| P3 | WAF / rate limiting | Medium |
| P3 | Database migration pattern | Medium |
| P3 | GOMAXPROCS automation | Low |

---

## 9. What Already Works Well

The platform has strong foundations in several areas:

- **Config (Factor #3)**: External Secrets Operator + env var injection via Helm
- **Build/Release/Run (Factor #5)**: ArgoCD + Kargo progressive delivery pipeline
- **Concurrency (Factor #8)**: Karpenter + KEDA + HPA infrastructure at cluster level
- **Dev/Prod Parity (Factor #10)**: Multi-env Terragrunt with per-env values
- **Logs (Factor #11)**: Loki + Fluent Bit collecting from stdout/stderr
- **Observability stack**: Prometheus, Grafana, Loki, Tempo, OTEL Collector all deployed
- **Security policies**: Gatekeeper + PSA + default-deny NetworkPolicies
- **Node provisioning**: Karpenter with x86, ARM64, spot, and compute-intensive pools
- **Multi-region/multi-account**: Full org structure with proper isolation
