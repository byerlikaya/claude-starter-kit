---
name: code-review
description: |
  Code review discipline: severity-ranked, reasoned feedback focused on whether a change
  improves the overall code health of the system. review-agent-cck applies the `code-review` skill.
  Trigger phrases: "code-review", "review the code", "review the PR", "review", "do a review"
---

# Code Review

> **Kit adaptation (local, .claude/):** applied by `review-agent-cck` (read-only). Sources (alignment):
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

## DoD (this skill's contribution)
- Findings are severity-ranked (blocker / suggestion / nit) and **reasoned**.
- Scope creep and hidden complexity are flagged.
