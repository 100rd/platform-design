# Topology Spread Constraints for Multi-Region AZ Distribution

This document describes the recommended `topologySpreadConstraints` for distributing pods across Availability Zones within each region. These constraints apply **within a single cluster** -- cross-region distribution is handled by deploying to both clusters via ArgoCD ApplicationSets (see [workload-scheduling.md](workload-scheduling.md)).

## Recommended Defaults

### Deployment (Stateless Workloads)

For stateless services, use `DoNotSchedule` to enforce even AZ distribution. This prevents a single AZ failure from taking down more than ~1/3 of your pods (in a 3-AZ region).

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
  namespace: production
spec:
  replicas: 6
  selector:
    matchLabels:
      app: web-frontend
  template:
    metadata:
      labels:
        app: web-frontend
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: web-frontend
      containers:
        - name: web-frontend
          image: registry.example.com/web-frontend:v3.1.0
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 512Mi
```

With 6 replicas across 3 AZs, each AZ gets exactly 2 pods. If one AZ goes down, 4 pods remain.

### StatefulSet (Stateful Workloads)

For StatefulSets, use `ScheduleAnyway` to prefer even distribution but avoid blocking pod scheduling when AZ capacity is constrained. Stateful workloads often have volume affinity that limits AZ placement.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cache-cluster
  namespace: production
spec:
  serviceName: cache-cluster
  replicas: 3
  selector:
    matchLabels:
      app: cache-cluster
  template:
    metadata:
      labels:
        app: cache-cluster
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: cache-cluster
      containers:
        - name: cache
          image: registry.example.com/cache:v2.0.0
          ports:
            - containerPort: 6379
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: "2"
              memory: 2Gi
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3-encrypted
        resources:
          requests:
            storage: 50Gi
```

### Combined: AZ Spread + Host Anti-Affinity

For critical services, combine AZ spread with host-level anti-affinity to prevent two pods of the same service running on the same node:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: payment-service
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: payment-service
```

The first constraint enforces AZ balance (hard). The second prefers unique hosts within each AZ (soft).

## When to Use DoNotSchedule vs ScheduleAnyway

| Constraint | Use When | Trade-off |
|---|---|---|
| `DoNotSchedule` | Even AZ distribution is critical for HA; the service is stateless and can scale freely | Pods may stay Pending if an AZ has no capacity |
| `ScheduleAnyway` | Availability is more important than perfect balance; StatefulSets with PVC affinity; during scale-up bursts | Pods may cluster in one AZ temporarily |

### Guidelines

- **Production stateless services**: `DoNotSchedule` -- you want hard guarantees.
- **StatefulSets**: `ScheduleAnyway` -- PVCs are AZ-bound and may prevent placement.
- **Dev/staging**: `ScheduleAnyway` -- availability over balance, fewer nodes.
- **Batch jobs**: No spread constraint needed -- they run to completion and terminate.

## maxSkew Values

- **maxSkew: 1** (recommended) -- at most 1 pod difference between the most-loaded and least-loaded AZ. Gives tight balance.
- **maxSkew: 2** -- allows more flexibility during rolling updates or scale-up. Use when `maxSkew: 1` causes excessive Pending pods.

## Interaction with Karpenter

Karpenter v1.8.1 respects `topologySpreadConstraints` when provisioning new nodes. When a pod is Pending due to a `DoNotSchedule` constraint, Karpenter will launch a node in the required AZ. Ensure your Karpenter NodePool allows all AZs:

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: topology.kubernetes.io/zone
          operator: In
          values:
            - eu-west-1a
            - eu-west-1b
            - eu-west-1c
```
