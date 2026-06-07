# Tetragon Runtime Security

Cilium Tetragon eBPF runtime security for the platform.

**Provenance**: ADR-0019 (Runtime Security)

## Decision Summary

Tetragon was chosen over Falco because:

- Shares the same eBPF kernel stack as Cilium — no duplicate kernel hooks or module conflicts.
- Supports in-kernel enforcement via BPF programs (Sigkill, Override, etc.) when policies graduate to enforce-mode.
- Native process-to-pod identity enrichment using Cilium's existing identity model.
- Hubble integration: Tetragon events are surfaced alongside network flows in Hubble UI.

Falco was not selected: it runs outside the Cilium data-plane and requires a separate kernel driver (eBPF or kmod), adding integration complexity.

## Deployment Mode

Observe-mode only. All three starter TracingPolicies have `tetragon.io/observe-only: "true"` and no `matchActions` configured. Events are written to stdout (JSON Lines) and forwarded to the SIEM via the node-local log collector.

To graduate any policy to enforce-mode, follow the in-file instructions in each TracingPolicy template.

## TracingPolicies

| File | Purpose |
|------|---------|
| `tracing-policy-exec.yaml` | Trace all process executions (execve/execveat) |
| `tracing-policy-sensitive-files.yaml` | Observe opens of /etc/shadow, /etc/passwd, SSH host keys, SA tokens |
| `tracing-policy-privileged-syscalls.yaml` | Observe ptrace, setuid, setgid, mount |

## Hubble UI

Hubble UI (`hubble.ui.enabled: true` in `apps/infra/cilium/values.yaml`) was explicitly confirmed as part of this ADR-0019 slice to provide a visual network-flow and security-event overlay in the same interface.

Access: port-forward to the `hubble-ui` Service in the `kube-system` namespace, or expose via an HTTPRoute referencing the `cilium` GatewayClass.

## ArgoCD

This chart is auto-discovered by the `infra` ApplicationSet (`argocd/bootstrap/applicationsets/infra-appset.yaml`, path glob `apps/infra/*`). No separate Application manifest is required. ArgoCD deploys this as `tetragon-<cluster-name>` in namespace `tetragon` with `CreateNamespace=true`.
