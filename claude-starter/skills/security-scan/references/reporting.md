# Reporting & fix presentation

## Report

**Severity scale:**

| Level | Meaning |
|---|---|
| CRITICAL | Directly exploitable — urgent (SQL injection, hardcoded secret in prod) |
| HIGH | Serious — close before deploy (XSS, command injection, known CVE) |
| MEDIUM | Defense gap — soon (missing CSRF, loose CORS) |
| LOW | Best-practice violation — when convenient (debug mode, missing header) |
| INFO | Observation — no immediate risk |

**Finding format** (ranked by severity):
```
[CRITICAL] SQL Injection — src/api/users.ts:42
  Vuln  : Input concatenated directly into the SQL query
  Impact: DB can be read / modified / deleted
  Fix   : Use a parameterized query
```

**Summary line:**
```
=== Security Scan Summary ===
  CRITICAL: X · HIGH: X · MEDIUM: X · LOW: X · INFO: X · Total: X
```

## Coverage — say what you did NOT look at

A report with no findings is read as "nothing is wrong". It can equally mean "that surface was never opened",
and the two are indistinguishable to the person acting on it — who then ships believing an audit happened. The
`CANNOT_VERIFY` verdict already handles this for an individual finding; coverage handles it for the audit.

Every report ends with a coverage ledger, one row per surface from the threat model ([[threat-model]]):

```
=== Coverage ===
  complete  auth/session handling        — read every route + middleware
  complete  SQL data access              — grepped all query construction sites
  partial   file upload                  — read the handler; storage backend config not available
  unknown   payment webhook              — third-party signature logic, no source access
  unknown   admin client (Blazor)        — out of scope this pass, agreed with the user
```

Rules:
- **`complete` is a claim, not a hope.** Use it only where you can name what you read or ran. If you sampled,
  it is `partial`.
- Every `partial` and `unknown` carries **why** — no access, out of scope, no time, third-party. A bare
  `unknown` is the same silence the ledger exists to remove.
- `unknown` on a surface the threat model calls high-risk is itself a finding: report it at the severity that
  surface would carry, not as a footnote.
- The ledger is written **before** the fixes are proposed. Written afterwards, it gets trimmed to match the
  work that happened to be done.
- "Zero findings, coverage complete" is a strong claim and rare. "Zero findings, half the surface unknown" is
  an honest and much more common one.

## Fix presentation
```
How shall we proceed?
  1. Fix everything        2. CRITICAL+HIGH only
  3. Approve one by one    4. Manual (no changes)
```
For each fix: preview the diff → wait for approval → (if a dependency) upgrade command + breaking-change note → re-run the relevant check.
