# Verify before you report — the adversarial pass

Discovery and verification want opposite things. **Discovery is recall-biased** — when unsure whether something is
real, surface it (a low-confidence finding beats a missed bug). **Verification is precision-biased** — a separate,
adversarial pass that tries to *disprove* each finding. Keeping them separate is the single biggest lever on false
positives. (This is the same two-stage-verdict discipline `code-review` uses — reused here for security findings.)

Run this pass on every candidate before it reaches the report.

## The verifier stance
For each finding, run **N independent verifiers** (default **3**; 1 for a quick scan, 5 for a release/high-stakes
audit). Each verifier:
- **Starts from the code at the cited `file:line`, not the finding's summary.** If you start from the summary you
  inherit its misreading.
- Is stanced **"find any reason this finding is wrong."** Actively hunt for why it is *not* exploitable.
- Is **blind to the other verifiers' reasoning** — shared context propagates the same blind spot.

## The 4-step verify procedure (each step kills a specific false-positive class)
1. **Read the cited code yourself** — do not trust the description.
2. **Trace reachability backward from the sink.** Can untrusted input actually reach it? **Quote the first
   call-site `file:line`** as evidence. *Unreachable code is the single largest source of false positives* — a
   plausible-sounding chain is not enough.
3. **Hunt for protections** on every path: validation, parameterization, auto-escaping, type/length bounds, an
   auth/scope gate, or the code being dead/test-only.
4. **Stress-test each protection on every path** — a guard that holds on one route but not another is not a guard.

## Verdict — three outcomes, never a forced binary
- **TRUE_POSITIVE** — requires ALL of: reachable + protections insufficient + exploitation feasible.
- **FALSE_POSITIVE** — fails one of the above, or matches an exclusion rule below.
- **CANNOT_VERIFY** — static reasoning hit its limit (needs a running system / data you don't have). Report it
  honestly as `needs_manual_test`; never inflate uncertainty into a confident verdict.

"I couldn't write a working PoC" is **weak** evidence of non-exploitability — do not downgrade on that alone.

## Exclusion rules — FALSE_POSITIVE even if technically accurate
1. Volumetric/rate DoS with no amplification (just "many requests").
2. Test, fixture, example, or provably dead/unreachable code.
3. Intended, documented design (a stated, accepted risk).
4. Memory-safety issue in a memory-safe language/runtime.
5. Input that only a trusted operator controls (a local CLI flag, an ops-only env var).
6. "Outdated dependency" with no reachable vulnerable call path.
7. Weak randomness used somewhere non-security (a cache key, a test seed).
8. XSS auto-neutralised by the framework's default escaping.
9. Traversal blocked one layer up (a gateway/service the reasoning didn't read).
10. A theoretical-only TOCTOU with no realistic race window.
11. "Missing hardening" with no concrete exploit (a nice-to-have header).
12. Low-impact nuisance with no security consequence.

Add project-specific rules as you confirm them.

## Structured verdict block (one per finding, parseable)
```
VERDICT: TRUE_POSITIVE | FALSE_POSITIVE | CANNOT_VERIFY
CONFIDENCE: 0-10
REACHABILITY: <first untrusted call-site file:line, or "unreachable">
EXCLUSION_RULE: <number, or none>
RATIONALE: <cites concrete file:line, not prose>
```

## Tally
Verdict = majority of the N verifiers; confidence = mean of the agreeing votes. **Tie → the operator's noise
tolerance:** precision → drop; recall → keep as `needs_manual_test`; ask → one batched question. Never silently
drop a finding — a dropped finding is recorded (with its verdict) in the report's "Ruled out" section.

## Severity is a SEPARATE judgment from verification
"This is real" must not inflate into "this is critical." Derive severity from **preconditions × access level**, not
from the vulnerability category:

| access ↓ / preconditions → | 0 preconditions | 1–2 | 3+ |
|---|---|---|---|
| **unauthenticated / remote** | CRITICAL–HIGH | MEDIUM | LOW |
| **authenticated** | MEDIUM | MEDIUM | LOW |
| **local / operator** | LOW | LOW | INFO |

- Take the **lower** of the two axes. If the precondition list has **3+ items, HIGH is almost certainly wrong.**
- A `threat-model` match may raise severity by **at most one step** — never two (a stated threat can't re-inflate a LOW to HIGH).
- Record `severity_alignment` (**-5..+5**): judged from the stance of a reviewer who has seen two hundred inflated
  scanner findings this week — how over- or under-stated is the raw claim? Negative = deflate it.
