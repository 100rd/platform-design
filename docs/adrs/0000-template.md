# ADR-0000: Template

- Status: **TEMPLATE** (replace with `Proposed` / `Accepted` / `Superseded by ADR-NNNN` / `Deprecated`)
- Date: YYYY-MM-DD
- Authors: @handle, @handle
- Related issues: #N, #M
- Supersedes: (none)
- Superseded by: (none)

## Context

What is the problem we're solving? What constraints, conventions, or prior
decisions do we have to fit within? Provide enough background that someone
new to the team can understand why this decision is being made.

## Decision

State the decision in one or two declarative sentences. Should be testable
in code review (i.e., a reviewer can check whether new work conforms).

## Alternatives considered

Each alternative gets a short paragraph describing what it is, why it was
considered, and why it was rejected. **Always include "do nothing" / status
quo as an alternative** — sometimes the best decision is no change.

### Alternative A: <name>
Description.
Rejected because: <reason>.

### Alternative B: <name>
Description.
Rejected because: <reason>.

### Alternative C: Status quo
Description of the current behaviour.
Rejected because: <reason>.

## Consequences

### Positive
- ...
- ...

### Negative
- ... (e.g., extra cognitive load, migration cost)
- ...

### Risks
- ... (with mitigations)

## Implementation notes

- Files / modules touched: `path/to/file`, `terraform/modules/<name>`
- Migration steps (if any).
- Rollback procedure (if implementation fails).
- CI/test coverage that locks the decision in.

## References

- Source repo / external link
- Related ADRs
- AWS / vendor documentation
