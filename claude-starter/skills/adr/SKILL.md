---
name: adr
description: |
  Architecture Decision Record: context-decision-consequences, for decisions that are expensive to reverse.
  Written under docs/adr/.
---

# Architecture Decision Record (ADR)

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "adr", "architecture decision", "decision record", "why this approach"

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

## Deliberately bypassing a rule is a decision too
A gate the user knowingly overrode — a deferred DoD item, an accepted known gap, a trimmed scope — belongs here
whenever its effect outlives the task. It is not a lesser kind of decision: choosing *not* to apply a rule shapes
the codebase exactly as choosing a database does, and it is the one class of decision that leaves no trace in the
code at all. Six months on, a rule that was weighed and overridden is indistinguishable from one that was never
noticed, and the second is the one you would want to fix.

Record it in the same file as any other decision, with the fields that make it reversible:

```
## Bypassed
- <gate/rule> — why: <reason> — asked by: <who> — revisit: <condition or date>
```

`revisit` is the load-bearing field. A bypass with no condition attached is permanent by default, and nobody
chose permanence. See [[confidence-check]], which is where most bypasses surface.

## DoD
- Decision + rationale + rejected alternatives recorded; status current.
- Any deliberately bypassed rule is recorded with its reason, who asked, and what would reverse it.
