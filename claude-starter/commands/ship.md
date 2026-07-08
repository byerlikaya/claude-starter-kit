---
name: ship
description: DoD gate + commit proposal (waits for approval).
---
# /ship
Closure flow — in order:
1. **DoD gate:** was `/simplify` applied · are tests green (test-expert-csk) · (if SonarQube is used) `sonarqube-check` 0/0/0/0.
   If any one is red, **STOP**, report what is missing; no deferral.
2. If clean, **commit-agent-csk** (commit-message) **proposes** an atomic Conventional Commit from the staged diff.
3. Commit runs ONLY if the user says "commit" (§4.4). "Done" is not approval.

No destructive operations (§4.5). No AI trace / vendor name in the message (§4.1/§4.2 — the hook already scans).
