# Standard Specification: Observability Platform (SPEC-OBSERVABILITY)

- **ID:** `SPEC-OBSERVABILITY`
- **Name:** Observability Platform
- **Status:** **Ready**
- **Dependencies:** `SPEC-GITOPS-ARGOCD`

---

## 1. Purpose

This specification describes the standard for the unified observability system. The platform provides a comprehensive solution for monitoring, investigating, and debugging the performance and health of the platform and its applications, built on the "four pillars of observability".

## 2. Technologies

| Signal | Collection | Storage & Processing | Visualization/Query |
| :--- | :--- | :--- | :--- |
| **Metrics** | Prometheus | Thanos | Grafana (PromQL) |
| **Logs** | Fluent Bit | Loki | Grafana (LogQL) |
| **Traces** | OpenTelemetry Collector| Tempo | Grafana (TraceQL) |
| **Profiles**| Pyroscope | Pyroscope | Grafana (Flame graphs)|

The architecture is centered on **Grafana** as the unified query interface and **AWS S3** as the cost-effective, long-term storage backend.

## 3. Architecture and Strategy

The system is designed to be cloud-native, vendor-neutral, and highly scalable. The canonical architecture is detailed in `docs/observability-architecture.md`.

### 3.1. Key Patterns

- **Single Pane of Glass:** All telemetry signals (metrics, logs, traces, profiles) are accessible and correlated within Grafana, simplifying analysis and debugging workflows.
- **S3 as a Universal Backend:** All components (Thanos, Loki, Tempo, Pyroscope) leverage S3 for long-term storage, separating "hot" query tiers on local SSDs from "cold" storage in the cloud.
- **Exhaustive Documentation:** The architecture document contains diagrams, data flow descriptions, cost estimations, resource sizing guides, and disaster recovery procedures.
- **Security by Design:** Component access to S3 is secured using IAM Roles for Service Accounts (IRSA). Network Policies restrict traffic between components. All data is encrypted in transit and at rest.

### 3.2. Data Flows

- **Metrics:** `Prometheus` scrapes metrics within clusters (2-hour retention). A `Thanos Sidecar` uploads data blocks to S3. `Thanos Query` provides a global query view over all local and S3 data.
- **Logs:** `Fluent Bit` runs as a DaemonSet on each node, collecting container logs and forwarding them to `Loki`. Loki indexes the metadata and stores the log chunks in S3.
- **Traces:** Applications instrumented with the `OpenTelemetry SDK` send traces to a local `OpenTelemetry Collector`. The collector performs intelligent tail-based sampling (retaining 100% of errors) and forwards traces to `Tempo`, which stores them in S3.
- **Profiles:** A `Pyroscope Agent` scrapes performance profiling data (CPU, memory) from applications and sends it to `Pyroscope` for storage, also backed by S3.

### 3.3. Data Correlation

The system is designed for seamless correlation. For example, logs are automatically enriched with a `trace_id`, enabling one-click navigation in Grafana from a slow span in a trace directly to its corresponding log entries.

## 4. Deployment Sequence

The entire observability stack is deployed via GitOps after ArgoCD is operational.

```mermaid
graph TD;
    A[ArgoCD is operational<br/>(from SPEC-GITOPS-ARGOCD)] --> B[1. <b>Deploy Observability ApplicationSet</b><br/>ArgoCD syncs the 'observability' ApplicationSet];
    B --> C[2. <b>Agents & Collectors Deploy</b><br/>DaemonSets like Fluent Bit and OTel Collector are deployed to all nodes];
    C --> D[3. <b>Backend Services Deploy</b><br/>Stateful components like Prometheus, Loki, and Tempo are deployed];
    D --> E[4. <b>Frontend Deploys</b><br/>Grafana is deployed and automatically configured with datasources pointing to the backends];
    E --> F{Fully observable cluster};
```

### Sequence Description:

1.  **Deploy ApplicationSet:** ArgoCD reconciles the main ApplicationSet responsible for the observability stack.
2.  **Deploy Agents:** This first wave includes the node-level collection agents (Fluent Bit, OTel Collector) to ensure telemetry is captured immediately as applications start.
3.  **Deploy Backends:** The core storage and processing components (Prometheus, Loki, Thanos, etc.) are deployed. They are often StatefulSets with persistent storage claims.
4.  **Deploy Frontend:** Finally, Grafana is deployed. Its configuration (datasources, dashboards) is managed as code and automatically provisioned, pointing to the backend services that are now ready.
