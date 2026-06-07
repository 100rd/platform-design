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

**Wave 3 — enforce-mode active** (`enforce.enabled=true` by default).

Two of the three TracingPolicies now carry `matchActions` that block hostile behaviour
in-kernel. `exec-tracing` stays observe-only permanently (it records all execve events
for SIEM correlation; blocking arbitrary exec would be too broad).

## TracingPolicies

| File | Policy name | Mode |
|------|-------------|------|
| `tracing-policy-exec.yaml` | `exec-tracing` | observe (permanent) |
| `tracing-policy-privileged-syscalls.yaml` | `privileged-syscall-tracing` | **enforce** (Wave 3) |
| `tracing-policy-sensitive-files.yaml` | `sensitive-file-access` | **enforce** (Wave 3) |

### privileged-syscall-tracing (enforce)

| Syscall | Action | Scope |
|---------|--------|-------|
| `ptrace` | **Sigkill** caller | Binaries not in allowlist, inside containers (Mnt ns != host) |
| `setuid` | **Override -EPERM** | Binaries not in allowlist, inside containers |
| `setgid` | **Override -EPERM** | Binaries not in allowlist, inside containers |
| `mount` | observe only | All callers (needs dedicated soak before enforcement) |

ptrace allowlist: `/usr/bin/strace`, `/usr/bin/gdb`, `/usr/local/bin/dlv`

setuid/setgid allowlist: `/usr/bin/sudo`, `/usr/bin/su`, `/usr/sbin/sshd`, `/usr/lib/openssh/sftp-server`

### sensitive-file-access (enforce)

| Syscall | Paths enforced | Action | Scope |
|---------|----------------|--------|-------|
| `openat` / `open` | `/etc/{shadow,gshadow,passwd,group}` | **Override -EPERM** | Write-intent opens by binaries not in allowlist |

Reads are not blocked. SSH host keys and the SA token remain observe-only on
writes; they require a dedicated node-type soak cycle before enforcement is safe.

Allowlist: `/usr/bin/passwd`, `/sbin/unix_chkpwd`, `/usr/sbin/{useradd,usermod,userdel,groupadd,groupmod}`, `/usr/bin/chage`

## Enforcement Gate

The `enforce.enabled` value (default `true`) toggles enforcement across all policies at once.
Both enforced policies render `matchActions` only when `enforce.enabled=true`; at `false` they
are observe-only event emitters. The flag controls the `tetragon.io/policy-mode` label and the
`tetragon.io/observe-only` annotation on each TracingPolicy CRD.

```yaml
# values.yaml default
enforce:
  enabled: true
```

## Observe-to-Enforce History

| Wave | PR | Date | Change |
|------|----|------|--------|
| Initial | PR #263 | 2026-06-07 | All three policies deployed in observe-mode (ADR-0019) |
| Wave 3 | PR #252 | 2026-06-07 | 72 h soak complete; privileged-syscall + sensitive-file graduated to enforce |

Soak baseline: 72 h on staging cluster (namespaces: kube-system, tetragon, cilium).
No false-positive events from the binary allowlists were observed in that window.

## Rollback

Enforcement can be hot-rolled back without restarting any DaemonSet:

```bash
helm upgrade tetragon . --set enforce.enabled=false
```

Tetragon operator reconciles the TracingPolicy CRDs in under 30 s.
Policies immediately drop to observe-only. No pod restarts occur.

To re-enable after confirming the issue:

```bash
helm upgrade tetragon . --set enforce.enabled=true
```

## Hubble UI

Hubble UI (`hubble.ui.enabled: true` in `apps/infra/cilium/values.yaml`) was explicitly
confirmed as part of ADR-0019 to provide a visual network-flow and security-event overlay.

Access: port-forward to the `hubble-ui` Service in the `kube-system` namespace, or expose
via an HTTPRoute referencing the `cilium` GatewayClass.

## ArgoCD

This chart is auto-discovered by the `infra` ApplicationSet
(`argocd/bootstrap/applicationsets/infra-appset.yaml`, path glob `apps/infra/*`).
No separate Application manifest is required. ArgoCD deploys this as
`tetragon-<cluster-name>` in namespace `tetragon` with `CreateNamespace=true`.
