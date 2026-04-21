# Compliance & security

SOC2 Type 2 is the compliance target. PCI-DSS is deliberately out of scope. This doc maps platform controls to SOC2 Trust Services Criteria and explains the scoping decisions.

---

## Why PCI-DSS is out of scope

PCI-DSS applies to any system that stores, processes, or transmits cardholder data (primary account number, cardholder name, expiration date, service code, magnetic stripe data, CVV). Per the per-domain design:

- **HFT**: we ingest trade tape and order-book data. No card numbers.
- **Solana**: we ingest on-chain data — public addresses, token transfers. No card numbers.
- **Insurance exchange**: we ingest contract documents containing **payment confirmations** (the document states "payment received Y/N" or references a transaction id), not cardholder data. Premium flows, card acceptance, and any actual card processing happen in the insurance counterparty's own PCI-DSS-scoped systems — not ours.
- **RTB**: bid requests and campaign performance. No card numbers.

Consequence: we do not need PCI-DSS certification, we do not need the full PCI network segmentation, and we can host our analytical data plane in a single logically-segmented environment.

### Guardrail: PCI-DSS scope-creep prevention

New domain or new data source onboarding requires a written scope-confirmation step: the tenant's data contract is reviewed against PCI-DSS definitions, and if any cardholder data would be in scope, the onboarding is **blocked** pending either removal of that data from the feed or a re-architecture to a PCI-compliant isolated environment.

This check lives in the tenant-onboarding runbook and is a hard gate. See `docs/runbooks/tenant-onboarding.md` (to be written alongside Phase 8).

---

## SOC2 Type 2 — target

We aim for SOC2 Type 2 across the full five Trust Services Categories, with particular emphasis on Security (CC series) and Confidentiality. Below is the mapping between SOC2 controls and our existing platform components and plans.

### Security (CC-series)

| Control area | Our implementation |
|--------------|-----------------------|
| Logical access (CC6.1-6.3) | IAM Identity Center for AWS; OIDC + in-cluster RBAC for k8s; per-tenant credentials with automatic rotation via External Secrets Operator; MFA enforced on all SSO-backed accounts |
| System operations (CC7.1-7.5) | ArgoCD declarative config; Kargo progressive rollout; OPA/Gatekeeper policy enforcement; Checkov in CI; Gitleaks in CI; alert routing via Prometheus Alertmanager |
| Change management (CC8.1) | All production changes through Git → ArgoCD → Kargo; signed commits enforced; Cosign-signed artefacts; full reproducibility chain from label to deployed adapter (see [04-training-pipeline.md](04-training-pipeline.md#reproducibility-invariants)) |
| Risk mitigation (CC9.1-9.2) | Disaster recovery drills quarterly (primary ↔ standby UK DC failover); tenant isolation red-team exercise quarterly; vendor risk register maintained |
| Confidentiality (CC3) | TLS 1.3 in transit everywhere; mTLS between services; Cilium WireGuard transparent encryption inside k8s clusters; per-tenant KMS keys for data at rest |

### Availability (A-series)

- Monitoring and alerting are documented in [`docs/sre-runbook.md`](../sre-runbook.md) and extended in `docs/runbooks/` with per-scenario runbooks
- DR strategy documented in [06-uk-datacenters.md](06-uk-datacenters.md#primary--standby-replication)
- Edge agent graceful degradation documented in [05-edge-deployment.md](05-edge-deployment.md#graceful-degradation) — scoring continues on last-known-good when UK is unreachable

### Processing integrity (PI-series)

- Data flows audited end-to-end: every record in QuestDB / Iceberg carries the Kafka offset it was derived from
- Schema evolution controlled — Iceberg schema changes require a CI-verified compatible-migration Airflow DAG
- Model provenance (see [04-training-pipeline.md](04-training-pipeline.md#reproducibility-invariants)): every deployed adapter id maps to exact training data version, exact training config, exact base model weights

### Confidentiality (C-series)

- Data classification per tenant, per domain; enforced through Iceberg namespace + Kafka ACL + Postgres schema + Qdrant collection + KMS key
- Data retention policies: 30 days hot (QuestDB), long-term (Iceberg) configurable per tenant, labels retained 7 years (training lineage), telemetry 30 days
- Tenant data export on request: tooling to enumerate and export all of a tenant's data across stores (Phase 8 deliverable)
- Tenant offboarding: automated purge procedure, default 30-day grace period before Iceberg cold data actually deleted, all deletions audited

### Privacy (P-series)

Privacy controls apply mainly to the RTB and insurance domains, where human identities may be present in bid streams or documents.

- PII handling: RTB bid requests redact IFA / device-id after retention window; insurance document PII is retained for the contractual term with access scoped to the tenant's own users
- Data subject rights (GDPR, UK GDPR): per-tenant tooling to respond to access / deletion requests — tenant is controller, we are processor
- Cross-border data transfer: all data stays in UK unless the tenant explicitly configures otherwise; DPAs in place with tenants and key sub-processors (MinIO vendor, observability vendors, cloud)

---

## Tenant isolation threat model

### Adversaries we defend against

1. **Confused deputy** — engineer-authored code accidentally queries or exposes tenant X's data while operating in tenant Y's context. This is the dominant risk. Mitigations: per-tenant credentials at every layer, Gatekeeper constraints, code review with mandatory tenant-scoping check, integration tests that verify tenant A cannot read tenant B.
2. **Insider threat** — platform engineer with production access intentionally exfiltrates tenant data. Mitigations: no direct production DB shell access (all queries through audited tooling), least-privilege IAM, session recording on all break-glass access, quarterly access review, separation of duties between training and serving-access.
3. **Supply chain compromise** — malicious dependency slips into a training or serving container. Mitigations: SBOM generation per build, pinned dependency versions, Checkov + Gitleaks + Trivy in CI, Cosign verification at pull, keyless signing with Sigstore's transparency log.
4. **Compromised edge instance** — attacker gains control of an edge agent at a client venue. Mitigations: per-venue short-lived certs (30-day), Kafka ACL narrowly scopes what compromised credentials can do, OPA-style validation on inbound traffic to UK filters anomalous producer behaviour, audit alerts on cert anomalies.

### Adversaries we deliberately do not prioritise

- **Adversarial tenant running malicious container within our cluster** — this is the cluster-per-tenant threat model. We do not accept tenant-authored containers. If we ever start, this moves to the top of the priority list.
- **Nation-state level hardware attack on UK DC** — outside our threat model; mitigated by site physical security, not platform controls.

---

## Audit and evidence

### What is continuously recorded

- All ArgoCD sync events, Kargo promotions, Cosign signings → Loki with 400-day retention
- All Airflow DAG runs and their inputs → Postgres `runs` + Loki
- All kubectl actions (via audit log) in both AWS and UK clusters → Loki
- All tenant-boundary crossings (any cross-tenant query or API call, which should be zero by design) → dedicated alert topic
- All Kafka ACL decisions (allow + deny) → sampling for cost but full capture on any deny

### What is produced for auditors

- Change log per quarter: all production changes with commit → ArgoCD sync → Kargo stage → final destination
- Access review per quarter: IAM + RBAC + Argilla + Kafka ACL matrix, compared to HR system, unauthorised access flagged
- DR drill reports: measured RPO/RTO, deviations from runbook, follow-up actions
- Tenant isolation red-team report: test cases, results, any failed cases and their remediation
- Vendor SOC2 / ISO / other attestations collected for MinIO, Qdrant, Argilla, Talos, LiteLLM, base-model publishers

---

## Specific controls to note

### Keys and secrets

- AWS KMS for AWS-resident state (control-plane configs, S3 artefact storage)
- HashiCorp Vault on UK primary (replicated to standby) for UK-resident secrets and per-tenant data-plane keys
- External Secrets Operator syncs both into k8s for in-cluster consumption
- No secrets in Git, enforced by Gitleaks pre-commit and CI gates
- Cosign key used for edge artefact signing kept in a dedicated KMS slot, accessed only by the CI build workflow, rotation procedure documented

### Network segmentation

- Cilium CNI with L7-aware NetworkPolicy throughout
- Transparent WireGuard encryption between all pods (per `gpu-inference-dod.md` requirement, extended to the UK clusters)
- mTLS between services in addition to network encryption (defence in depth — compromised node does not automatically mean traffic sniffing)
- No plaintext Kafka listener anywhere; no plaintext Postgres listener anywhere

### Supply chain

- Base images pulled from trusted registries with SHA digests, not tags
- SBOMs generated via Syft on every build, published alongside the artefact
- Trivy scans integrated into CI; HIGH / CRITICAL findings block release unless explicitly accepted and documented
- Cosign signatures required on all production OCI images and detached binary bundles; verification enforced at pull

### Logging

- All logs structured (JSON) with consistent tenant / request-id / trace-id fields
- No PII in logs without explicit justification + legal sign-off
- Loki retention tuned per log class: audit 400 days, operational 90 days, debug 14 days
- Log-forwarding integrity verified by cryptographic anchor at the collector (prevents tampering after forwarding)

---

## Scope exclusions, summarised

To make the boundaries explicit:

| Concern | In scope | Out of scope |
|---------|----------|--------------|
| Card payments processing | — | All payment flows — we see confirmations of receipt only |
| Trading execution | — | Clients execute their own trades |
| Insurance policy binding | — | The exchange does the binding; we score inputs |
| Ad auction participation | — | Clients run their own bidders |
| Personal data beyond what comes in transaction payloads | — | We do not collect separate user data; GDPR scope is processor-only |
| Regulatory reporting | — | Client systems file to regulators; we provide analytical inputs |

---

## Compliance ownership

- **Security lead** owns SOC2 control implementation and the quarterly access / DR review cadence
- **SRE lead** owns the runbooks, alert hygiene, and DR drill execution
- **Product / solutions** owns the per-tenant DPA and compliance questionnaires
- **Legal** signs off on data retention lengths, cross-border transfer terms, and any new domain's PCI-DSS-scope assessment

This split is documented in `docs/sre-runbook.md` under the section for escalations and ownership; the transaction analytics layer inherits it unchanged.
