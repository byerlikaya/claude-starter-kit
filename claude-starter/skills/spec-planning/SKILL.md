---
name: spec-planning
description: |
  Spec-first planning: task breakdown, measurable acceptance criteria, dependency order, risk priority.
  planner-csk applies it; the plan goes to docs/PLAN.md.
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

## Mark what you do not know — do not fill it in
Where a requirement admits more than one reading, write the marker **`[NEEDS CLARIFICATION: <the question>]`** at
that exact spot in the plan. Do not resolve it with the likeliest interpretation and move on.

This is the difference between a discipline and a hope. "Stop and ask when unsure" (§1) depends on noticing the
uncertainty in the moment; a marker survives into the artifact, where the user, a reviewer and a later session
can all see it. A plausible assumption silently written into a spec is indistinguishable from a decision, and
that is exactly how the wrong feature gets built correctly.

Rules that keep it honest:
- The marker carries the **question**, not the label. `[NEEDS CLARIFICATION: does an expired invite count as
  used, or can it be re-sent?]` is actionable; `[NEEDS CLARIFICATION: invites]` is noise.
- A plan may ship with markers — that is the point. It may **not** ship with a marker inside an acceptance
  criterion: a criterion nobody can evaluate is not a criterion.
- Resolve by asking, never by choosing. When the user answers, replace the marker with the answer *and* record
  which reading was rejected — the alternative is what a future reader needs.
- Zero markers on a genuinely ambiguous brief is a smell, not a win.

## DoD (this skill's contribution)
- Every task's "done" is testable; ordering and dependencies are visible; the riskiest work has been brought to the front.
- Every unresolved ambiguity carries a `[NEEDS CLARIFICATION: …]` marker; no acceptance criterion contains one.
