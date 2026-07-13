---
name: code-review
description: |
  Code review discipline: severity-ranked, reasoned feedback on whether a change improves the system's overall
  code health. review-agent-csk applies it.
  Trigger phrases: "code-review", "review the code", "review the PR", "review", "do a review"
---

# Code Review

> **Kit adaptation (local, .claude/):** applied by `review-agent-csk` (read-only). Sources (alignment):
> google/eng-practices — its name does not appear in the artifact that goes to the repo (§4.2). Comments are severity-ranked; §4 applies.

## Core standard (senior principle)
A change is approved once it reaches the point of **improving the overall code health** of the system —
**it does not have to be perfect.** Avoid two mistakes:
- **Blocking:** a perfectionist, subjective fixation that halts progress. If there is no progress, the code never improves.
- **Laxity:** small concessions each time erode code health over time.
The approval criterion is "is it better", not "is it flawless". If it is an unwanted feature, it can be rejected even when the design is good.

## What to review (priority order)
1. **Design:** do the pieces fit together; does this change belong here; should it be added now.
2. **Functionality:** does it do what is intended; is it right for the user/developer; edge cases, concurrency.
3. **Complexity:** is it more complex than necessary; is there over-engineering / design for a future assumption (YAGNI).
4. **Tests:** are there correct, meaningful, sufficient tests; real behavior, not tests for tests' sake.
   **Verifier integrity:** flag any change that makes a check pass by *weakening the check* — deleting or loosening
   an assertion, lowering a threshold, skipping a test, editing the test instead of the code — rather than fixing
   the behavior. A test or gate that grades itself lax is worse than none; a verifier must stay external and grounded.
5. **Naming:** names that carry intent, neither too long nor cryptic.
6. **Comments:** do they explain the **"why"** rather than the "what"; no dead/unnecessary comments.
7. **Style & consistency:** conforms to the project guide; consistent with the existing conventions.
8. **Documentation:** if behavior changed, was the relevant document updated.
9. **Every line:** look at every human-written line; do not skip code you do not understand as "it's probably correct".

## Writing comments
- **Kind and reasoned:** what should change + **why**. In the language of suggestion, not command.
- Separate small/non-mandatory notes with a **"Nit:"** label — these do not block.
- Comment on the code, not the person; judge the code, not the individual.
- Note what is good, too; do not just hunt for flaws.

## Speed & disagreement
- **Turn it around fast:** a pending review lowers productivity; look at it at the first opportunity.
- In a disagreement, **technical fact + data** speak, not personal preference. If no agreement is reached, take it face-to-face / escalate to a higher authority — not passive blocking.

## Two-stage verdict (verify before you report)
Finding a problem and confirming it are two acts. A first-pass "this looks wrong" is a **candidate**, not a verdict.
Before a finding is reported — especially a **blocker** — run a second, independent pass that tries to *disprove* it:
- Does it actually hold on the real code, or did the first read miss context (a guard upstream, a caller that never
  reaches this path, a framework default)? Re-read the surrounding code, don't rank on the snippet alone.
- Is the severity honest, or is it a nit dressed as a blocker?
- For any **"fixed" / "passes" claim**: the *real* check ran and passed — test exit code, build, lint/quality gate —
  not "I re-read it and it looks fixed". A verifier that is the model's own say-so is not a verifier (see §4 Tests,
  Verifier integrity). Cite the evidence (which check, what result).

A finding that survives the disprove pass is a verdict; one that doesn't is dropped or downgraded. This is what kills
false-positive blockers that stall progress while keeping the review's authority.

## Panel mode (high-stakes decisions only)

For hard-to-reverse calls (architecture, public API, security boundary), run several independent adversarial lenses then synthesize. Full method: **`references/panel-mode.md`**.

## DoD (this skill's contribution)
- Findings are severity-ranked (blocker / suggestion / nit) and **reasoned**.
- Scope creep and hidden complexity are flagged.
- Each reported blocker survived an independent disprove pass; any "fixed"/"passes" claim is backed by the real check
  having actually run, not self-assessment.
- For a high-stakes decision, multiple independent lenses were applied and their objections synthesized, not averaged.
