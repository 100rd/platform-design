# RabbitMQ Cluster Operator

Deploys the [RabbitMQ Cluster Operator](https://www.rabbitmq.com/kubernetes/operator/operator-overview) via the Bitnami Helm chart, providing Kubernetes-native lifecycle management for RabbitMQ clusters.

## What's Included

- **Cluster Operator** — watches `RabbitmqCluster` CRs and manages RabbitMQ StatefulSets, Services, ConfigMaps, and Secrets
- **Messaging Topology Operator** — watches topology CRs (`Queue`, `Exchange`, `Binding`, `Policy`, `User`, `Vhost`, etc.) and configures RabbitMQ server-side objects declaratively

## CRDs Installed

| CRD | Purpose |
|-----|---------|
| `rabbitmqclusters.rabbitmq.com` | Declare a RabbitMQ cluster |
| `queues.rabbitmq.com` | Declare queues |
| `exchanges.rabbitmq.com` | Declare exchanges |
| `bindings.rabbitmq.com` | Declare bindings |
| `policies.rabbitmq.com` | Declare policies |
| `users.rabbitmq.com` | Declare users |
| `vhosts.rabbitmq.com` | Declare virtual hosts |
| `permissions.rabbitmq.com` | Declare permissions |
| `shovels.rabbitmq.com` | Declare shovels |
| `federations.rabbitmq.com` | Declare federation upstreams |

## Example Usage

Create a 3-node RabbitMQ cluster:

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: my-rabbitmq
  namespace: my-app
spec:
  replicas: 3
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: "2"
      memory: 2Gi
  rabbitmq:
    additionalPlugins:
      - rabbitmq_management
      - rabbitmq_prometheus
      - rabbitmq_shovel
      - rabbitmq_shovel_management
  persistence:
    storageClassName: gp3
    storage: 20Gi
```

Declare a queue via the Topology Operator:

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: Queue
metadata:
  name: orders
  namespace: my-app
spec:
  name: orders
  durable: true
  rabbitmqClusterReference:
    name: my-rabbitmq
```

## Environment Overrides

| Environment | Operator Replicas | Notes |
|-------------|-------------------|-------|
| dev | 1 | Lower resources |
| integration | 1 | Lower resources |
| staging | 2 | Production-like |
| prod | 2 | Full resources |

## Troubleshooting

Check operator logs:
```bash
kubectl logs -n rabbitmq-operator -l app.kubernetes.io/name=rabbitmq-cluster-operator -f
```

Check CRD status:
```bash
kubectl get rabbitmqclusters -A
kubectl describe rabbitmqcluster <name> -n <namespace>
```

Check topology operator:
```bash
kubectl logs -n rabbitmq-operator -l app.kubernetes.io/name=messaging-topology-operator -f
kubectl get queues,exchanges,bindings -A
```
