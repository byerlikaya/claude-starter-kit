---
name: spec-planning
description: |
  Spec-first planning method: task breakdown, measurable acceptance criteria, dependency ordering,
  risk prioritization. planner-cck applies this; the plan is written to docs/PLAN.md.
  Trigger phrases: "plan", "spec", "task breakdown", "acceptance criteria", "roadmap", "how do we split this"
---

# Spec-First Planning

Before writing code: what will be done, how it counts as "done", and in what order to proceed become clear.

## Steps
1. **Purpose & scope:** the problem being solved in a single sentence; also write the out-of-scope explicitly (prevent scope creep).
2. **Split into vertical slices:** the smallest end-to-end working pieces (not horizontal layers). Each slice delivers value on its own.
3. **A contract for every task:** input · output · **measurable acceptance criterion** (testable) · estimated risk.
4. **Dependency graph:** which task waits on what; no cycles. **Bring the riskiest/most-unknown to the front** (fail-fast).
5. **Uncertainties:** assumption list + open questions; do not fill ambiguous spots with a guess, ask with explicit options.

## Output (docs/PLAN.md)
```
# <Feature> — Plan
## Acceptance criteria
- [ ] <measurable outcome>
## Tasks (order)
1. <task> — criterion: <...> — dependency: <none/#n> — risk: <low/medium/high>
## Assumptions / Open questions
- ...
```

## DoD (this skill's contribution)
- Every task's "done" is testable; ordering and dependencies are visible; the riskiest work has been brought to the front.
