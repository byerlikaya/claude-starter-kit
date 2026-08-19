---
name: code-review-csk
description: |
  Code review discipline: severity-ranked, reasoned feedback on whether a change improves the system's overall
  code health. review-agent-csk applies it.
---

# Code Review

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "code-review", "review the code", "review the PR", "review", "do a review"

> **Kit adaptation (local, .claude/):** applied by `review-agent-csk` (read-only). No source name appears in the
> artifact that goes to the repo (§4.2). Comments are severity-ranked; §4 applies.
>
> **Sources, by layer** — three different questions, three different authorities:
> - **Judgement — how to rank what you found:** this kit's own. The two-stage verdict and verifier integrity below
>   exist because the code under review is increasingly written by an agent, and a reviewer that accepts its own
>   say-so is not a reviewer. No external standard covers that yet.
> - **Governance — that review happens at all, and findings survive it:** NIST SP 800-218 (SSDF) **PW.7** and the
>   OpenSSF Scorecard **Code-Review** check. Both are deliberately silent on the rubric: PW.7.2 says to review
>   "based on the organization's secure coding standards", which is what the rest of this file is.
> - **Comment vocabulary:** Conventional Comments (CC BY 3.0).
> - **Rubric heritage:** google/eng-practices (CC BY 3.0) — the priority order and the "code health" bar below are
>   adapted from it, so it is attributed as the licence requires.

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
- Comment on the code, not the person; judge the code, not the individual.
- Note what is good, too; do not just hunt for flaws.

**Label every comment.** An agent writes these, and a human or a tool has to sort them without reading each one —
so the label is a field, not a tone. Format: `<label> [decoration]: <subject>`.

| Label | Use it for | Blocks? |
|---|---|---|
| `issue` | a defect: wrong behaviour, a real risk | yes, unless marked non-blocking |
| `suggestion` | a concrete improvement you are proposing | no by default |
| `nitpick` | trivial preference — always non-blocking | never |
| `question` | you cannot tell whether it is wrong without an answer | yes while unanswered |
| `todo` | a small necessary change, not worth an issue | no |
| `praise` | something worth keeping — say so | no |

Decorations are `(blocking)` / `(non-blocking)`; use them whenever the default would be ambiguous. Mapping to the
severity split this skill reports: **blocker** = `issue (blocking)` or an unanswered `question (blocking)`,
**suggestion** = `suggestion` / `todo`, **nit** = `nitpick`.

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

**"Independent" costs a separate context.** A second pass in the same context has already read the first one's
reasoning, so it cannot be blind to it — and its agreement is the first pass nodding at itself. For a **blocker**,
run the disprove pass as its own subagent, handed the claim and the `file:line` but not your argument. If you did
not isolate it, label the verdict as a single pass rather than calling it independent. The full contract —
isolation, one lens per verifier, and why unanimity for the same reason is a monoculture — lives in
`security-scan/references/verify.md`; it is one discipline, not two.

## Panel mode (high-stakes decisions only)

For hard-to-reverse calls (architecture, public API, security boundary), run several independent adversarial lenses then synthesize. Full method: **`references/panel-mode.md`**.

## Triage — a finding that is only reported is a finding that is lost
Reviewing and *disposing of* what the review found are two acts, and only the first one is habitual. Every finding
that survives the disprove pass leaves the review with an explicit disposition — never an unanswered comment and
never a silent drop:

| Disposition | Means | Where it goes |
|---|---|---|
| **fixed now** | the owning specialist changed the code | the diff; re-review the change |
| **tracked** | real, not for this change | an issue/task with the file:line — cite the id in the review |
| **accepted** | a real cost the team is choosing to carry | an `adr` when it is architectural, a code comment when local |
| **dropped** | did not survive the disprove pass | say so; a candidate that vanishes unexplained reads as an oversight |

Blockers may only be `fixed now` or `tracked`. "Accepted" needs the user's decision — an agent does not grant it to
itself. Close the review by stating the counts per disposition; an unreported finding is indistinguishable from one
that was never made, which is exactly the state a review exists to leave behind.

## DoD (this skill's contribution)
- Findings are severity-ranked (blocker / suggestion / nit), **labelled**, and **reasoned**.
- Scope creep and hidden complexity are flagged.
- Each reported blocker survived an independent disprove pass; any "fixed"/"passes" claim is backed by the real check
  having actually run, not self-assessment.
- **Every finding has a disposition** (fixed / tracked / accepted / dropped) and no blocker is left merely reported.
- For a high-stakes decision, multiple independent lenses were applied and their objections synthesized, not averaged.
