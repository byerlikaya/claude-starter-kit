---
name: eval-grader
description: |
  Measure output quality, don't vibe it: score a generative task with a two-layer grader — deterministic code
  metrics + per-dimension LLM-as-judge — over a fixed task set, as signed deltas vs a pinned baseline. Grades
  cost alongside correctness (pass-slow).
  Trigger phrases: "eval", "grader", "measure output quality", "LLM-as-judge", "score the output"
---

# Eval Grader

**Measure every change; don't vibe it.** When you iterate on a prompt, an agent, or any generative output (docs,
slides, UI, a summary, an extraction), a two-layer grader over a fixed task set turns "feels better" into a signed
number you can trust.

This is the **external, machine-grounded verifier** the `iterate` skill asks for — a model grading its *own* output
inflates; a separate grader on a fixed suite does not.

> **Kit adaptation (local, .claude/):** use when tuning a generative task; the scorecard goes to `docs/EVAL.md`
> (§4.3). Stack-agnostic — graders are ordinary code + judge calls. §4 Prohibitions apply.

## Two layers
- **Layer 1 — code graders** (deterministic, near-free, run every time): structural metrics over the artifact —
  *did it produce a valid result?* plus counts, sizes, schema validity, "wall-of-text" / clutter flags. They catch
  gross regressions a judge shouldn't be spent on. Ground truth is **computed from the source**, not hand-authored.
- **Layer 2 — LLM-as-judge graders** (semantic): **one call per dimension** (clarity · correctness-vs-source ·
  completeness…), scored on an explicit rubric. Steer against leniency — "use the full 0-5 range, not only 3-5";
  judge with a **different model family** to avoid self-preference; **randomize A/B order** to kill position bias.

Each grader is one **scorecard column**; adding a metric = appending one grader.

## pass-slow — grade cost alongside correctness
A result is not just right/wrong. An **efficiency grader** downgrades a correct output that ran **over a
turn/token budget** to `pass-slow` — so "correct but too expensive" is visible, not hidden inside a green pass.

## The loop
1. A **fixed task set** (`tasks`), each with an input and a measurable expectation.
2. Run all graders over each task's output → a scorecard.
3. **Pin a baseline** once; every later run shows **signed deltas vs that baseline**, not vs the previous run — so
   re-running the same round shows real movement, not noise.
4. Change one thing, re-run, read the deltas. Keep what moves the number up.

## Noise floor
State it. At n=20 tasks, one task ≈ 5 points — deltas smaller than that are not meaningful. If the cheapest option
already hits the ceiling, say so plainly instead of chasing a fractional gain.

The grader architecture, a starter grader catalogue, and the judge-bias checklist live in **`references/method.md`**.

## DoD
- A fixed task set + a two-layer grader; a pinned baseline; every change reported as a signed delta with the noise floor stated.
