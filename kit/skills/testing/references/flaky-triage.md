# Flaky test triage

Loaded on demand — SKILL.md holds the rule (`Flaky = bug`); this is the decision procedure for one that has already
failed intermittently. A test that passes and fails on the same commit gates nothing, and every red run it produces
teaches the team to ignore red runs. Triage it the day it is seen and record the outcome.

## 1 · Classify first: infrastructure or product
The two kinds get opposite treatment, so this call comes before the outcome.

- **Infrastructure flake** — fails the same way regardless of the test's logic, and clusters in time. Signals:
  identical error text across unrelated tests (connection refused, image pull, no disk, name resolution); a whole
  run or one machine fails and the next run passes with no code change; the assertion is never reached.
- **Product flake** — follows the data or the ordering. Signals: it tracks one case, fixture or seed; it appears
  only under randomized order or parallel execution; it reproduces in a loop on one machine; the assertion *is*
  reached and the value is wrong.
- Cannot tell yet → treat it as a product flake. Guessing "infrastructure" is how a real race gets a retry put
  around it.

## 2 · Retry policy follows that classification
- **Infrastructure: a bounded retry is allowed** — a fixed cap decided once and written down, applied where the
  resource is owned (readiness wait, fixture setup, the job step), never around an assertion. Log every retry that
  fires: a retry nobody can see is a failure nobody counts, and a rising count means the label was wrong.
- **Product: never retry.** A retry there turns a real bug into a slower green — the defect ships and the suite
  reports success. Widening a timeout and sleeping until it passes are the same move under another name.

## 3 · Three outcomes — pick exactly one, in writing
| Outcome | Use when | What it requires |
|---|---|---|
| **Fix** | the test or the code under it is genuinely wrong: unfrozen clock, unseeded randomness, shared state, order dependence, an assertion on something unordered | the change, plus a run that reproduced the old failure (loop, shuffle, parallel) and now holds |
| **Quarantine** | the failure is real but not yet understood, and blocking every other change on it costs more than the coverage it holds | a named owner, a date, a linked issue — and the test still executing |
| **Escalate** | the flake is a symptom, not a test defect: a race, a leak, a resource limit, an unsafe ordering in the code under test | hand it over as a product defect and root-cause it (`systematic-debugging`) |

Escalate means the change lands in product code. Rewriting the test to step around the race deletes the only
evidence that the race exists, and it resurfaces in production instead of in CI.

## 4 · Quarantine has a shape, or it is deletion
- **Scoped, not removed.** The test leaves the *gating* lane, not the suite: it keeps running in a non-gating or
  scheduled job, so its failure rate stays visible and the fix can be proven.
- **Owner and date, always** — both stored next to the test (marker, tag, or an explicit list the gating job filters
  on) and re-read on that date. If nobody will own it and no date fits, the honest outcome was Fix or Escalate.
- **Re-decide on the date**, choosing again from the three. A quarantined test nobody returns to is worse than a
  deleted one: it reports coverage that is not being checked.
- Deleting the test deliberately, with the reason recorded, is a legitimate end state. Silent expiry is not.
- Quarantine is not a way to go green for a release; an escalate-class flake blocks the release it belongs to.

## Boundary with the rest of the discipline
- Disabling or skipping a red test to finish a task is masking, not quarantine: masking removes the signal,
  quarantine relocates it and puts a date on it.
- Making an intermittent failure reproduce on demand — loop the case, randomize order, add stress, widen the timing
  window — is `systematic-debugging/references/techniques.md`. Triage without a repro is a guess.
- The quarantine list is a debt list. If it only grows, nothing is being fixed: report the count and the oldest entry.