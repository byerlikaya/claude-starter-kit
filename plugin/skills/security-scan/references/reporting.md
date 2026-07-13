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

## Fix presentation
```
How shall we proceed?
  1. Fix everything        2. CRITICAL+HIGH only
  3. Approve one by one    4. Manual (no changes)
```
For each fix: preview the diff → wait for approval → (if a dependency) upgrade command + breaking-change note → re-run the relevant check.
