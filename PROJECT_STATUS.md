# Platform Design — Project Status

**Last Updated**: 2026-04-05
**Status**: Active Development
**Remote**: https://github.com/100rd/platform-design

---

## Summary

Production-grade, multi-account AWS platform with EKS, Karpenter autoscaling, ArgoCD+Kargo GitOps delivery, and full observability. Multi-region (4 EU regions: eu-central-1, eu-west-1, eu-west-2, eu-west-3).

## Tech Stack

| Layer | Component | Version |
|-------|-----------|---------|
| IaC | Terraform + Terragrunt | Latest |
| Compute | EKS | 1.34 |
| Autoscaling | Karpenter | 1.8.1 |
| Networking | Cilium CNI | 1.17.1 |
| GitOps | ArgoCD + Kargo | 3.x + 1.2.0 |
| Observability | kube-prometheus-stack | 81.2.0 |
| Logging | Loki | 6.51.0 |
| Tracing | Tempo | 1.24.0 |
| Telemetry | OpenTelemetry Collector | 0.143.0 |
| Profiling | Pyroscope | 1.18.0 |
| Policy | OPA/Gatekeeper + Kyverno | 3.18.2 / 1.13.4 |
| Secrets | External Secrets Operator | 0.14.1 |
| Backups | Velero | 1.15.0 |
| DNS | External DNS + custom controllers | 0.15.1 |

## AWS Account Structure

```
Management (_org)
├── Security OU
├── Infrastructure OU → Network (Transit Gateway, Route53)
├── Workloads OU → NonProd (Dev, Staging)
└── Prod OU → Prod + DR
```

## Completed Work

- [x] Foundation: VPC, EKS modules updated to latest
- [x] Karpenter: IAM, controller, node pools (x86, ARM64/Graviton, spot/on-demand)
- [x] Security: OPA/Gatekeeper policies, secrets removed, External Secrets templates
- [x] Observability: Full stack with versions updated (16–47 version gaps closed)
- [x] ArgoCD ApplicationSets + Kargo progressive delivery
- [x] DNS failover controllers (Go)
- [x] Automation scripts: deploy.sh, validate.sh, cleanup.sh, preflight-check.sh
- [x] 85 Checkov/audit findings remediated (PR #48)

## Pending Work

- [ ] AWS provider version compatibility audit across all modules
- [ ] IAM/IRSA validation post EKS module upgrade
- [ ] Phase 2 Karpenter Terraform module (see TODO.md)

## Recent PRs

| PR | Title | Status |
|----|-------|--------|
| #49 | feature/codebase-remediation | Merged |
| #48 | feature/blockchain-chains-and-listeners | Merged |

## Orchestration

- **Agent Team**: `/infra-team` or `/design-system` for infrastructure work
- **History**: `project/PROJECT_HISTORY.md`
- **Locks**: `project/.locks/`
