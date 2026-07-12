---
name: reflect
description: |
  Retrospective self-audit after nontrivial work: unverified assumptions, skipped items, is-this-the-right-
  approach — findings, not code. The step-back counterpart to iterate's refine-to-done loop.
  Trigger phrases: "reflect", "retro", "retrospective", "what did we miss", "step back", "introspect"
---

# Reflect — step back and audit the work, not just the code

## When
A nontrivial chunk of work just finished (a feature, a plan, a debugging session) and it's worth a deliberate
step back **before** committing or moving on. This is the meta-cognitive counterpart to [[iterate]]: iterate
drives a change *to* its exit test; reflect asks whether the exit test — and the approach behind it — was even
the right one. Skip it for a one-line, unambiguous change; there's nothing to reflect on.

## The pass
Ask each question honestly and write the answer, not a reassurance:
1. **Unverified assumptions** — what did I take for granted that I never checked? Name each one and whether it
   was actually confirmed (read the code / ran the flow) or just assumed.
2. **What got skipped** — an edge case, an error path, a test, a doc update, a security/privacy angle. What was
   silently dropped, and was that a conscious trade-off or an oversight?
3. **Right approach?** — with hindsight, is this the direction we'd still pick? Did scope creep in? Is there a
   simpler path we walked past ([[code-review]] altitude: could 200 lines be 50)?
4. **Evidence gap** — which claims of "done" / "works" rest on having *observed* behavior vs. on inference?
   An unobserved "it works" is a finding (see [[iterate]] / verify: drive the real flow).
5. **What I'd tell the next session** — the one thing a fresh context most needs to know (feeds [[handoff]]).

## Guardrails
- **Findings, not code.** Reflect surfaces gaps; the relevant specialist fixes them (a found gap re-enters
  [[iterate]] or the author agent). It changes nothing itself.
- **Honest, not performative.** A retro that only confirms good work is a failed retro. If nothing is found,
  say specifically *why* you're confident (what was verified), don't just assert it.
- **Bounded.** One pass, concrete findings, then act or close — not an open rumination loop.
- **Token discipline** ([[token-budget]]): a short ranked findings list to the main thread; detail to a file.

## DoD (this skill's contribution)
- Assumptions are labeled verified vs. assumed; unverified ones are flagged, not buried.
- Skipped items and any scope creep are named explicitly.
- Every "done/works" claim is traced to observed evidence or marked as inference.
- Findings are actionable (each maps to a fix, a follow-up, or an accepted trade-off).
