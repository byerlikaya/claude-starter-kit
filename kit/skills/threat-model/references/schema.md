# THREAT_MODEL.md — parseable contract

A **map, not a bug list.** Fixed sections in this order so `security-scan` and a reviewer can parse it.

## Sections
1. **System** — one paragraph: what it does, who uses it, where it runs.
2. **Assets** — what is worth protecting (data · money · availability · reputation/trust), each with a *why*.
3. **Entry points & trust boundaries** — every place untrusted input crosses into more-trusted code
   (route · API · form · file upload · CLI arg · queue message · webhook · IAM/role boundary). This is the surface.
4. **Threats** — the ranked table (below).
5. **Attack classes** — the 5-8 domain-specific classes derived, each mapped to the entry points it applies to.
6. **Open questions** — owner claims still to verify, each with a "Verify by: <how>".
7. **Mitigations** — class-level controls (table below).
8. **Coverage** — assert every section-3 entry point appears in ≥1 threat's `surface`.

## Threats table
Pipe-separated columns:

`id | threat | actor | surface | asset | impact | likelihood | status | controls | evidence`

Enumerated value sets (keep parseable):
- **actor** ∈ `external-anon · external-auth · insider · supply-chain · operator · automated · physical`
- **impact** ∈ `low · moderate · high · severe · existential`
- **likelihood** ∈ `very_rare · rare · possible · likely · almost_certain`
- **status** ∈ `unmitigated · partial · mitigated · risk_accepted`

Rules:
- Sort by `(impact, likelihood)` descending — worst first.
- **`evidence` raises `likelihood`; it is not the threat.** A row may have empty evidence (a threat with no
  found vulnerability yet is still real). Score the **residual** likelihood *after* current `controls`.
- `risk_accepted` requires a reason recorded verbatim in section 6.

## Scoring guide
| axis | how to score |
|---|---|
| **impact** | realistic worst case for *this* asset. `low`=cosmetic · `moderate`=recoverable loss · `high`=serious breach/outage · `severe`=major data/financial loss · `existential`=business-ending. |
| **likelihood** | *after* current controls (residual). A control the owner *states* but that is not code-verified does **not** lower it — record it as an open question instead. |

## Mitigations table
`mitigation | threat_ids | closes_class (yes/no) | effort`

Prefer a control that **closes a whole class** (`closes_class = yes`) over a one-line patch for the last bug.
