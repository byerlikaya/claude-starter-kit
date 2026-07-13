# Panel mode — adversarial expert panel

For a **consequential, hard-to-reverse** decision (an architecture choice, a public API contract, a security
boundary) a single-lens review under-covers. Run an **adversarial expert panel**: evaluate the change from
**several independent lenses in parallel**, each arguing on its own terms, then synthesize.
- **Distinct lenses, not repetition:** e.g. *correctness/edge cases · security & privacy · maintainability &
  altitude (YAGNI) · operational cost/perf*. Give each lens a real advocate whose job is to find where the
  change fails on *that* axis — diversity catches failure modes redundancy can't.
- **Adversarial by default:** each lens tries to refute "this is the right change", not to bless it. A concern
  raised by one lens isn't overruled by the others' approval — it's recorded and weighed.
- **Synthesize, don't average:** collect every lens's findings, keep the sharpest objection from each, and
  reach one decision (proceed / proceed-with-changes / reject) with the reasoning. This is the distilled
  judge-panel pattern — reserve it for high stakes; routine diffs get the single-lens review above (don't
  burn a panel on a one-liner).
