---
name: adr
description: |
  Architecture Decision Record (ADR): documents decisions that are expensive to reverse or permanent,
  in context-decision-consequences format. Runs on a permanent architectural decision; written under docs/adr/.
  Trigger phrases: "adr", "architecture decision", "decision record", "why this approach", "architecture decision"
---

# Architecture Decision Record (ADR)

## When
On an architecture/technology choice that is expensive to reverse, long-lived, or contested
(database selection, auth strategy, critical pattern). Small/reversible decisions do not require an ADR.

## Format (docs/adr/NNNN-short-title.md, ~1 page)
```
# NNNN. <Decision title>
Status: proposed | accepted | rejected | superseded (by NNNN)
## Context
Which problem/constraint requires this decision?
## Decision
What was decided (clear, one sentence + rationale)?
## Consequences
Pros / cons / accepted trade-offs.
## Alternatives considered
Why were they not chosen?
```

## Principles
- **Invariant:** a new decision marks the old ADR as `superseded`; an ADR is **never deleted** (decision history is preserved).
- Numbered and dated; keep it short.

## DoD
- Decision + rationale + rejected alternatives recorded; status current.
