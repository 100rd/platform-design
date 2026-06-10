# On-Call Rotation & Escalation

> **Scope (WS-E):** formalizes the on-call **rotation**, **escalation policy**, and
> **tabletop validation** for the platform, with an **ML on-call** track for the GKE
> ML platform. It builds on the escalation paths already documented in the
> [SRE runbook](../sre-runbook.md#on-call-procedures); this doc is the
> authoritative rotation/escalation reference and is the CC1.4 / CC7.4 evidence
> anchor in the [SOC2 control matrix](../compliance/soc2-control-matrix.md).
>
> **Owner (ADR-0028):** `platform.owner = team-sec` (security/compliance posture);
> the ML track is co-owned with `team-ml-platform`.

## Rotations

The platform runs **two PagerDuty rotations** plus the pre-existing observability
services (`observability-platform`, `application-monitoring` — see SRE runbook).

| Rotation | PagerDuty service | Covers | Primary owner |
|---|---|---|---|
| **Platform on-call** | `platform-oncall` | Infra: clusters, networking, IAM/org-policy, GCP + AWS control plane, gateways, DR/failover | team-sec + SRE |
| **ML on-call** | `ml-platform-oncall` | ML drift/accuracy, training pipelines (Airflow/MLflow), model serving — see [ML incident runbook](ml-incident-runbook.md) | team-ml-platform |

> The `ml-platform-oncall` service is the **WS-E formalization** of the dedicated ML
> PagerDuty routing key that ADR-0038 D3 flagged as a follow-up. Until it is
> provisioned, ML drift alerts fall back to the existing `alertmanager-pagerduty-secret`
> receiver shared with the platform rotation.

### Rotation mechanics

- **Cadence:** weekly, handed over at a fixed weekday/time; each rotation has a
  **primary** and a **secondary** (backup) responder.
- **Schedule source of truth:** PagerDuty (not this doc). This doc defines the
  *policy*; PagerDuty holds the *who and when*.
- **Handover:** outgoing primary posts an open-incidents + watch-items summary to
  `#oncall-handover` at the start of each rotation.
- **Coverage:** 24×7 for SEV1; business-hours-best-effort for SEV3.

## Escalation policy

Aligned with the SRE-runbook L1→L3 model, with explicit timers per severity.

| Level | Who | Engages when |
|---|---|---|
| **L1** | On-call primary (platform or ML) | Page fires; ACK within the severity SLA |
| **L2** | On-call secondary + domain expert (Senior SRE / Senior ML Eng + Platform Team) | L1 has not ACKed within SLA, **or** L1 requests help, **or** unresolved after 30 min |
| **L3** | Engineering leadership / incident commander | User-impacting > 1 h, **or** cross-team coordination, **or** any SEV1 declared a major incident |

### Per-severity timers

| Severity | ACK SLA | Auto-escalate L1→L2 | Declare major incident (L3) |
|---|---|---|---|
| **SEV1** | 5 min | 10 min no-ACK | At declaration (serving down / data loss) |
| **SEV2** | 15 min | 30 min no-ACK | > 1 h unresolved + user impact |
| **SEV3** | 1 h (Slack) | next business day | n/a |

PagerDuty enforces the no-ACK auto-escalation; this table is the policy PagerDuty is
configured against. Severity definitions for ML incidents are in the
[ML incident runbook](ml-incident-runbook.md#severity-definitions-ml); infra
severities follow the SRE runbook.

## Alerting → paging wiring

```
Prometheus rule  ──▶  Alertmanager route (platform_system label)  ──▶  PagerDuty service
  (ADR-0038)            (apps/infra/ml-monitoring/...routes)            (platform / ml)
                                   │
                                   ├─ severity=critical  ──▶ page (5-min SLA)
                                   ├─ severity=warning   ──▶ Slack #incidents (1-h)
                                   └─ platform_system=ml-monitoring + critical
                                                          ──▶ ml-retrain-webhook (bounded 6h)
```

- Routing-key + receiver secrets are sourced via **ESO** (ADR-0008), mirroring the
  existing `alertmanager-slack-secret` / `alertmanager-pagerduty-secret` pattern — no
  static tokens (CC6.1 evidence; consistent with the org-policy SA-key-creation deny).

## Incident communication templates

Reuse the SRE-runbook Slack templates. ML incidents additionally tag the model /
tenant / domain:

```
🚨 ML INCIDENT [SEVn]: <brief description>
━━━━━━━━━━━━━━━━━━━━━━━━━━━
Service: ml-platform-oncall
Model:   <name>@<version>  Tenant: <tenant>  Domain: <domain>
Alert:   <alertname>  (platform_system=ml-monitoring|ml-platform)
Impact:  <serving error rate / accuracy delta / pipeline blocked>
Status:  Investigating
Assigned: @ml-oncall
```

Status updates every 30 min (SEV1/SEV2) until resolved; final update links the
postmortem.

## Tabletop exercise (WS-E acceptance)

The plan's acceptance criterion is that the rotation + ML runbooks are **tested in a
tabletop**. Run a **quarterly** tabletop covering one scenario from each ML class:

1. **Drift** — "model X accuracy dropped 8% after an upstream schema change."
2. **Pipeline** — "nightly retrain DAG fails on GPU `Pending` for 2 h."
3. **Serving** — "model Y serving returns 30% 5xx after a version bump."

For each: walk the [ML incident runbook](ml-incident-runbook.md) decision tree, name
the responder at each escalation level, identify the mitigation (silence / rollback /
failover), and the evidence the incident would produce.

**Record (CC1.4 / CC7.4 / A1.3 evidence):**

| Field | Value |
|---|---|
| Date | _<YYYY-MM-DD>_ |
| Facilitator | _<name>_ |
| Participants | _<platform + ML on-call, leadership observer>_ |
| Scenarios exercised | drift / pipeline / serving |
| Gaps found | _<e.g. ml-platform-oncall service not yet provisioned>_ |
| Action items | _<owner + due>_ |

> The first tabletop is expected to surface the `ml-platform-oncall` PagerDuty
> service provisioning as an action item — that is the intended outcome (it confirms
> the fallback path works and the dedicated service is the next step).

## References

- [SRE runbook — On-Call Procedures](../sre-runbook.md#on-call-procedures)
- [ML incident runbook](ml-incident-runbook.md)
- [SOC2 control matrix](../compliance/soc2-control-matrix.md) (CC1.4, CC7.3, CC7.4, A1.3)
- [ADR-0038](../adrs/0038-ml-observability-drift.md) — drift→Alertmanager→PagerDuty route
- [ADR-0040](../adrs/0040-soc-posture-and-oncall.md) — SOC posture & on-call decision
