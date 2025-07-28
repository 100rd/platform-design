# Kubernetes Network Policies

This directory contains baseline `NetworkPolicy` manifests.

- `default-deny-all.yaml` &ndash; denies all ingress and egress within a namespace.
- `allow-from-same-namespace.yaml` &ndash; permits traffic between pods in the same namespace.
- `allow-dns-egress.yaml` &ndash; allows egress to the `kube-system` DNS service.

Apply the default deny policy first, then layer on namespace‑specific rules.

## Applying with kubectl

```bash
# Apply policies to a namespace
kubectl apply -n <namespace> -f network-policies/default-deny-all.yaml
kubectl apply -n <namespace> -f network-policies/allow-from-same-namespace.yaml
kubectl apply -n <namespace> -f network-policies/allow-dns-egress.yaml
```

## Deploying via ArgoCD

Create an ArgoCD `Application` that points to this directory or include the path
in your existing `ApplicationSet`.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: network-policies
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <repository-url>
    targetRevision: HEAD
    path: network-policies
  destination:
    server: https://kubernetes.default.svc
    namespace: network-policies
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

This ensures the network policies are synchronized across clusters by ArgoCD.
