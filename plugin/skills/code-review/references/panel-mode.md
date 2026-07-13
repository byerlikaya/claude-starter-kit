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

## The lenses (named, first-class)

Pick the lenses that fit the change — not all six every time. Each is a distinct advocate; assign one concern per
lens so they don't collapse into the same review twice.

| Lens | Asks | Fails the change when |
|---|---|---|
| **Correctness** | Does it do the right thing on every path? | An edge case, race, off-by-one, or error path is unhandled |
| **Security & privacy** | Can it be abused; does data leak? | Injection, missing authz, secret exposure, PII beyond purpose (→ `security-scan`, `privacy-compliance`) |
| **Simplicity & altitude** | Is it more than the problem needs? | Over-engineering, speculative generality, YAGNI, wrong abstraction level |
| **Contract & compatibility** | What breaks downstream? | A public API / schema / event shape changes without a migration or version (→ `api-design`) |
| **Operability** | What happens at 3am in prod? | No logs/metrics on the new path, silent failure, no rollback (→ `observability`, `incident-runbook`) |
| **Verifier integrity** | Is the *check* still honest? | A test/assertion/threshold was weakened to pass, instead of the behavior being fixed |

**Adversarial pairing:** the strongest panel pits lenses that pull against each other — Simplicity vs. Contract
(don't over-build, but don't break callers), Correctness vs. Operability (handle every case, but stay debuggable).
When two lenses conflict, that tension IS the decision to surface — resolve it explicitly, don't let one silently win.
