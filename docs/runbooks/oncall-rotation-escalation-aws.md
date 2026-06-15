# On-Call Rotation & Escalation — AWS EKS GPU ML Platform (WS-E)

> **Scope:** the on-call rotation, escalation policy, and quarterly tabletop for the
> **greenfield AWS EKS GPU ML platform** (ADRs 0044–0048). AWS-side companion to
> [`oncall-rotation-escalation.md`](oncall-rotation-escalation.md) (the GKE/ADR-0040 D4
> doc). It **ties into the existing PagerDuty + Alertmanager wiring** (ADR-0026/0038), not
> a new one — it formalizes the dedicated **ML** rotation that ADR-0038 D3 deferred to
> WS-E.
>
> **System / owner (ADR-0028):** `platform.system = ml-platform`,
> `platform.owner = team-ml-platform`. The escalation policy itself is `system = security`
> / `component = oncall`.

## Rotations

Two PagerDuty rotations, both 1-week, primary + secondary:

| Rotation | PagerDuty service | Covers | Routing |
|---|---|---|---|
| `platform-oncall` | existing platform service | cluster/infra, network, supply chain, non-ML SEV | existing Alertmanager `pagerduty` receiver |
| `ml-platform-oncall` | **`ml-platform-oncall`** (WS-E formalization) | ML drift/accuracy, training pipeline, GPU serving, DCGM/EFA GPU-node health | ADR-0038 `ml-drift-pagerduty` receiver + the `MLServing*`/`GPUNode*` routes |

> **Provisioning status:** the `ml-platform-oncall` PagerDuty **service + routing key** is
> the dedicated key ADR-0038 D3 deferred. Until it is provisioned (the **first tabletop
> action item**; tracked as a `partial` row in the
> [SOC2 matrix CC1.4](../compliance/soc2-control-matrix-aws-ml.md)), ML alerts fall back to
> the shared `platform-oncall` receiver. The routing key is sourced via ESO
> (`alertmanager-pagerduty-secret`, ADR-0008) — **never** committed.

## Escalation policy (L1 → L3)

| Level | Who | Trigger / timer |
|---|---|---|
| **L1** | primary on-call for the rotation | paged on the SEV; ACK within the SEV's ACK SLA (SEV1 5 min / SEV2 15 min / SEV3 1 h, per the [ML runbook](ml-incident-runbook-aws.md)) |
| **L2** | secondary on-call | auto-escalate if L1 has not ACKed within the ACK SLA, or on L1 request |
| **L3** | team lead + (SEV1) the platform/ML eng manager | SEV1 not mitigated within 30 min, or any incident crossing two domains (e.g. GPU-node failure cascading into a serving outage) |

Cross-domain incidents (an ML serving outage rooted in a cluster/network fault) page
**both** rotations; the SEV1 commander coordinates. A regional GPU outage that triggers
Route 53 failover (ADR-0044 D5) is automatically L3.

## Severity → action quick map

| SEV | Page | Mitigation entry point |
|---|---|---|
| SEV1 serving down | `ml-platform-oncall` immediately | [ML runbook Scenario 3](ml-incident-runbook-aws.md#scenario-3--serving-outage-envoy--gateway-api-inference-extension--aws-waf) |
| SEV2 drift/accuracy/training | `ml-platform-oncall` | [Scenario 1](ml-incident-runbook-aws.md#scenario-1--model-drift--accuracy-regression) / [Scenario 2](ml-incident-runbook-aws.md#scenario-2--training-pipeline-failure-airflow-on-eks) |
| SEV3 trend/staging | Slack `#ml-incidents` | triage during business hours |

## Comms templates

- **Internal (Slack `#ml-incidents`):** `SEV{n} — {model/$system} — {one-line impact} —
  commander @{name} — status: investigating/mitigating/recovered`.
- **Stakeholder (SEV1/SEV2):** model affected, user-facing impact, current mitigation, ETA,
  next update time. Posted by the commander, not the responder.
- **Status page:** only for SEV1 user-facing serving impact, owned by the commander.

## Quarterly tabletop

A quarterly tabletop exercise (the SOC2 CC1.4 evidence signal) walks one scenario from each
domain (drift, training, serving) end-to-end against this doc + the
[ML runbook](ml-incident-runbook-aws.md). **Output:** a dated exercise record + an action
list. The **standing first action item** is provisioning the `ml-platform-oncall` PagerDuty
service so ML pages stop falling back to the shared receiver.

| Tabletop date | Scenario rehearsed | Action items | Status |
|---|---|---|---|
| _(pending first run)_ | drift → retrain; serving 5xx + WAF; training GPU-quota stall | provision `ml-platform-oncall` service | open |

## Cross-references

- [ML-incident runbook (AWS)](ml-incident-runbook-aws.md)
- [SOC2 control matrix (AWS ML)](../compliance/soc2-control-matrix-aws-ml.md) — CC1.4 / CC2.2 / CC7.3
- [ADR-0038](../adrs/0038-ml-observability-drift.md) — drift → PagerDuty (ML key deferred to WS-E)
- [ADR-0026](../adrs/0026-observability-target-architecture.md) — Alertmanager → PagerDuty wiring
- [ADR-0008](../adrs/0008-external-secrets-operator.md) — ESO-sourced PagerDuty routing key
