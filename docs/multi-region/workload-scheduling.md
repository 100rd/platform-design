# Multi-Region Workload Scheduling

This document describes the two workload categories for multi-region EKS deployments and how to schedule them across the `eu-west-1` (Ireland) and `eu-central-1` (Frankfurt) clusters.

## Global Services

Global services run in **both clusters** simultaneously. Cilium ClusterMesh makes them discoverable across clusters, and Global Accelerator routes external traffic to the nearest healthy region.

### Configuration

Add Cilium annotations to your Service to enable cross-cluster discovery:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: production
  annotations:
    service.cilium.io/global: "true"
    service.cilium.io/affinity: "local"
spec:
  selector:
    app: api-gateway
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP
```

- `service.cilium.io/global: "true"` -- registers the service in the ClusterMesh global service store so both clusters can discover it.
- `service.cilium.io/affinity: "local"` -- pods prefer local endpoints first. If all local endpoints are unhealthy, traffic fails over to the remote cluster automatically.

### Example Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: api-gateway
      containers:
        - name: api-gateway
          image: registry.example.com/api-gateway:v1.2.3
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 20
```

### Suitable Workloads

- Stateless API services and web frontends
- API gateways and reverse proxies
- Authentication / authorization services
- gRPC services that tolerate failover latency

## Regional Services

Regional services run in a **single cluster** only. They are not registered in ClusterMesh and do not have the global annotation.

### Configuration

```yaml
apiVersion: v1
kind: Service
metadata:
  name: order-processor
  namespace: production
  # No Cilium global annotations -- service stays regional
spec:
  selector:
    app: order-processor
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP
```

### Example Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-processor
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: order-processor
  template:
    metadata:
      labels:
        app: order-processor
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: order-processor
      containers:
        - name: order-processor
          image: registry.example.com/order-processor:v2.0.1
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 1Gi
```

### Suitable Workloads

- Database writers (primary-replica patterns where only one region writes)
- Batch processors and cron jobs
- Region-specific compliance workloads (data residency requirements)
- Stateful services that cannot tolerate split-brain scenarios

## ArgoCD ApplicationSet for Multi-Cluster Deployment

Use an ArgoCD ApplicationSet with the `list` generator to deploy global services to both clusters and regional services to a single cluster.

### Global Service ApplicationSet

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: api-gateway
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: eu-west-1
            url: https://eks-eu-west-1.example.com
          - cluster: eu-central-1
            url: https://eks-eu-central-1.example.com
  template:
    metadata:
      name: "api-gateway-{{cluster}}"
    spec:
      project: production
      source:
        repoURL: https://github.com/100rd/platform-design.git
        targetRevision: main
        path: "apps/workloads/api-gateway/overlays/{{cluster}}"
      destination:
        server: "{{url}}"
        namespace: production
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### Regional Service ApplicationSet

For regional services, include only the target cluster in the generator:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: order-processor
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: eu-west-1
            url: https://eks-eu-west-1.example.com
  template:
    metadata:
      name: "order-processor-{{cluster}}"
    spec:
      project: production
      source:
        repoURL: https://github.com/100rd/platform-design.git
        targetRevision: main
        path: apps/workloads/order-processor
      destination:
        server: "{{url}}"
        namespace: production
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

## Decision Matrix

| Criteria | Global Service | Regional Service |
|---|---|---|
| Stateless | Yes | May be stateful |
| Tolerates cross-region failover latency (~20ms) | Yes | No / N/A |
| Needs active-active availability | Yes | No |
| Data residency constraints | No | Possibly |
| Cilium global annotation | Required | Omit |
| ArgoCD clusters in generator | Both | Single |
