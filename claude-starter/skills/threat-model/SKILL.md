---
name: threat-model
description: |
  Scope a security audit BEFORE scanning, to cut false positives: map assets, entry points, trust boundaries
  and 5-8 domain-specific attack classes into a parseable THREAT_MODEL.md. A threat survives a patch; a
  vulnerability is only evidence for one. Feeds security-scan.
  Trigger phrases: "threat model", "attack surface", "scope the audit", "trust boundary"
---

# Threat Model

Scope first, scan second. A security scan with no map produces noise; a threat model tells the scanner (and
`security-scan`) **where to look and what matters** — the single biggest lever on false positives.

The one idea to keep — the litmus test: **if patching one line of code makes an entry disappear, it was a
vulnerability, not a threat.** Threats survive patching (they name *what an attacker wants and the surface they
arrive through*); a vulnerability is only **evidence** that raises a threat's likelihood.

> **Kit adaptation (local, .claude/):** `security-expert-csk` runs this to scope before `security-scan`. Output
> `docs/THREAT_MODEL.md` is internal (§4.3). Stack-agnostic. §4 Prohibitions apply.

## When
- Before a first `security-scan` of a system, or when scan output is noisy / unscoped.
- After a significant new surface — a new API, a new integration, a new trust boundary.

## Two modes
- **interview** — the owner is available: ask the four questions below, one at a time.
- **bootstrap** — no owner: derive the model from code + past advisories, then flag what only the owner can confirm.

## Method — the four questions (Shostack), one at a time
Never dump a questionnaire; ask, capture into the schema, move on. Mirror the user's language.
1. **What are we building?** system context, assets worth protecting, entry points and trust boundaries.
2. **What can go wrong?** open-ended first; then, per entry point, fall back to **STRIDE**; derive **5-8
   domain-specific attack classes** at the right granularity — "IDOR on dataset rows", "integer overflow on
   length fields" — not "web vulnerabilities".
3. **What are we doing about it?** impact · residual likelihood · status · controls per threat; "accept the
   risk, with a written reason" (`risk_accepted`) is a valid answer.
4. **Did we do a good job?** read the ranked table back; coverage-check that every entry point appears.

Tag every fact **`[Code-verified]`** or **`[Owner-states]`**; each owner claim that moves a score becomes an
open question with a "Verify by:" note.

## Output
Write `docs/THREAT_MODEL.md` to the parseable contract in **`references/schema.md`** (fixed sections; a threats
table with enumerated columns; residual-likelihood scoring; class-level mitigations). The interview flow, the
STRIDE table, and the bootstrap steps live in **`references/interview.md`**.

## Principles
- **Evidence raises likelihood; it is not the threat.** Score the *residual* likelihood after current controls;
  a stated-but-unverified control does not lower it — it becomes an open question.
- **Prefer a control that survives the next bug** over a patch for the last one (class-level mitigations).
- **Feeds forward:** `security-scan` reads `THREAT_MODEL.md` to scope its fronts and bias severity.

## DoD
- `docs/THREAT_MODEL.md` exists; every entry point covered; each threat scored; provenance tagged; scope handed to `security-scan`.
