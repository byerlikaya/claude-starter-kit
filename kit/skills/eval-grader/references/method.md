# Eval grader — architecture & catalogue

## Shape
A **declarative list of graders**; the harness stays grader-agnostic. One grader:

```
{ name, kind: "code" | "judge", description,
  grade(context) -> number | string,
  scale?: { min, max, good: "high" | "low" } }
```
- `scale.good` drives red→yellow→green heat-coloring of a cell (so a scorecard is scannable).
- Build a **`GraderContext` once per task** (the parsed artifact + a rendered form + any client), and pass it to
  every grader — graders are pure functions of the context.

## Layer 1 — code graders (deterministic; adapt to your artifact)
- `produced` → `ok` / `missing` / `invalid` — did it produce a valid artifact at all? The cheapest, first gate.
- structural counts (sections · items · length), `too_long` / `cluttered` flags (`good: "low"`), schema validity.
- **Compute expected values from the seed/source, not by hand** — reproducible, and it catches "right narrative,
  wrong number" (a `numeric_tolerance` grader with a `must_mention` guard).

## Layer 2 — judge graders (semantic)
- **One call per dimension** (clarity, correctness-vs-source, completeness, tone…), integer **0-5** on an explicit
  rubric. Do **not** blend dimensions into one holistic score.
- **Structured output** (a typed schema) so the score lands parsed, not regex'd; retry on schema mismatch.
- **Memoize shared judge calls**: if four dimensions read the same rendered output, make **one** batched call and
  read four fields from it — not four calls.
- Add an **anti-hallucination** dimension: does the output say "I don't know / the source doesn't cover this"
  rather than inventing? Reward the honest gap.

## Judge-bias checklist (an LLM judge is biased — correct for it)
- **Position bias** → randomize A/B order across calls.
- **Verbosity bias** → a longer answer is not a better one; rubric on substance.
- **Self-preference** → judge with a **different model family** than the one under test.
- **Label deference** → don't show the judge the "expected" answer as gospel; ask it to reason first.
- Calibrate against a few human labels; test the judge on **known-negatives** (does it catch a deliberately-bad output?).

## The measured-iteration loop
- Pin the baseline once (`baseline.score.json`); later runs print **signed deltas vs the baseline**, not vs the
  previous run.
- One task's failure must not abort the scorecard (grade each independently, collect all results).
- A run over the whole suite is **one command**. If you want a structural regression to *block*, wire the Layer-1
  code graders into a Stop / PostToolUse hook (they're deterministic and fast — a natural gate).

## pass-slow / efficiency grader
Wrap a correctness grader: if it passes but `turns > budget_turns` or `tokens_out > budget`, return **`pass-slow`**
instead of `pass`. Score = (pass + ½·pass-slow) / N — "correct but too expensive" is a distinct, visible verdict.

## Cost/quality sweep (optional — picking a model/params for a task)
Sweep the grid (model × thinking × effort), hold everything else constant, and rank on
`cost_per_success = total_cost / passes` and `seconds_per_success` — a model 3× cheaper per call but passing half as
often is **not** cheaper. Always state the noise floor next to the winner.
