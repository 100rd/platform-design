# ADR-0056: Machine-readable platform contracts for organizational automation

- Status: **Accepted**
- Date: 2026-07-13
- Authors: platform-team
- Related issues: 100rd/omnius#11; genai-enablement ADR-0011 and ADR-0012
- Supersedes: (none)
- Superseded by: (none)

## Context

Platform paths currently exist as documentation, templates, and implementation-specific
delivery configuration. That is sufficient for a human operator, but it is not a safe
authority for an organizational executor. Omnius needs a closed, versioned contract that
separates the product promise, reusable entity classes, Realm constraints, executable
workflow, Conditions of Done, evidence, and compensation.

The first consumer is the Omnius P0 vertical `standard-http-service/v1`. Its scope is
deliberately narrow: modify one existing Go service repository, deliver it into a disposable
preview namespace through a Draft PR and the existing GitOps path, run deterministic HTTP
probes, and remove or revert the preview instance. Omnius may prepare the change, but a human
must merge it. Production, shared state, data mutation, secrets, arbitrary environment
variables, free-form scripts, and direct apply/deploy are outside this contract.

## Decision

1. `platform-contracts/` is the authoritative machine-contract root owned by the platform
   team. It contains closed JSON Schemas, indexed instances, fixtures, and documentation.
2. Git is the v1 publication mechanism. A consumer pins an exact 40-character commit and the
   bundle SHA-256 recorded in `platform-contracts/index.yaml`; mutable branches are not an
   execution authority.
3. The bundle digest is calculated over the authoritative files listed in the index, in
   lexical path order, as `path + NUL + bytes`. The index itself is excluded to avoid a
   self-referential digest. Every listed file also has an individual SHA-256.
4. Platform products, entity classes, Realms, delivery profiles, paths, and requests remain distinct artifacts.
   JSON Schema Draft 2020-12 with stable `urn:darkfactory:platform-contract:*` identifiers is
   the compatibility boundary. No schema service or GitHub Pages publication is introduced.
5. `standard-http-service/v1` enters in `experimental` state and is admitted only to the
   `preview/v1` Realm class. Lower-environment evidence is required before any later promotion.
6. Omnius receives only registered action, policy, and probe identifiers. The path cannot
   contain raw commands or implementation-specific apply authority.
7. Each executable path references one indexed `PlatformDeliveryProfile`. The platform owner uses
   that closed artifact to fix trusted source bindings, GitOps naming and topology references,
   resource envelopes, observation rules, and compensation. Omnius resolves logical endpoint
   references through separately governed adapter configuration and never accepts delivery targets
   from a request or model.
8. Adding the mandatory delivery-profile reference creates `platform/path/v2` and a new immutable
   `standard-service/v2` → `standard-http-service/v2` → `preview/v2` graph. The complete v1 graph
   and schema remain byte-compatible with their original contract. The initial delivery profile
   also requires an authenticated repository-ownership policy decision and binds its sole Namespace
   and compensation targets to the WorkOrder identity.

## Alternatives considered

### Alternative A: Put the contracts in Omnius

This would make the executor own the platform offer it executes.
Rejected because: platform ownership and execution authority would collapse into one trust
boundary, and other consumers could not share the same contract independently.

### Alternative B: Publish through a schema service

Operate an API and database as the contract authority.
Rejected because: it adds availability, identity, migration, and reconciliation failure modes
before there is evidence that Git publication is insufficient.

### Alternative C: Keep documentation and templates as the contract

Let agents infer the workflow from ADRs, Markdown, Helm values, and repository structure.
Rejected because: inference cannot prove closed inputs, immutable versions, compensation, or
referential integrity and therefore cannot safely authorize mutation.

## Consequences

### Positive

- Humans and agents submit one bounded request shape.
- Contract drift, unknown fields, broken references, and digest changes fail in CI.
- Platform ownership remains separate from Omnius execution and evidence.
- The first path can collect preview evidence without claiming production readiness.

### Negative

- Contract changes require coordinated schema/version maintenance.
- The first path is intentionally less flexible than the existing raw implementation surface.
- Git revision pinning is completed by the consumer after merge, not embedded recursively in
  the bundle.

### Risks

- **Contract and implementation diverge.** Mitigation: the path remains experimental until
  Omnius runs the real delivery and compensation probes against the pinned bundle.
- **A permissive schema becomes a command channel.** Mitigation: all authority-bearing schemas
  are closed and the request exposes no shell, arbitrary environment, secret, Helm, or policy
  fields.
- **Digest ambiguity.** Mitigation: the byte-level digest algorithm and indexed file set are
  fixed here and enforced by one repository validator.

## Implementation notes

- Authority: `platform-contracts/index.yaml` and the files it indexes.
- CI: `scripts/validate-platform-contracts.py` validates schemas, instances, hashes,
  references, fixtures, and semantic bindings.
- Rollback: revert the contract PR. Existing WorkOrders continue to use their pinned commit
  and digest; removing a published version does not retarget them.
- Promotion requires a new ADR or an amendment with lower-Realm evidence and a new immutable
  path version when compatibility changes.

## References

- `platform-contracts/README.md`
- `specs/SPEC-04-delivery-gitops.md`
- `specs/SPEC-05-security.md`
- `specs/SPEC-06-cicd-quality.md`
- ADR-0006, ADR-0014, ADR-0016, ADR-0020, ADR-0024, ADR-0028, ADR-0041
