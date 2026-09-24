---
name: review-crew
description: Review pass — review + security + quality gates.
---
# /review-crew
Run the change set through the review trio (read-only). **The audits go out in parallel; the reviewer closes.**
1. **At once, in ONE message** — several `Agent` calls, because none of these writes code and so there is
   nothing to serialise:
   - @agent-security-expert-crew (security-scan) — auth/IDOR/injection/secret; findings with severity.
   - @agent-performance-expert-crew (`performance`) — hot path, query/loop, render, payload. Reports
     **candidates** (reasoned) and **findings** (measured) separately; an unmeasured claim is never a verdict.
   - @agent-privacy-agent-crew (`privacy-compliance`) — **when the diff touches personal data**: legal basis,
     minimisation, retention, transfer.
2. (if SonarQube is in use) **sonarqube-check** — 0/0/0/0 gate (language-agnostic).
3. **Last, and only once 1-2 are clean:** @agent-review-agent-crew (code-review) — "does it improve overall code
   health"; severity-ranked comments. It is the closing reviewer in every writing agent's Coordination ("at
   closure, report findings to review-agent-crew"), so it reads a diff the audits have already cleared — not the
   other way round.

Each agent returns a **short summary** to the main thread; raw output goes to `docs/` if needed. Do NOT modify code;
collect findings in severity order, and leave the fix to the relevant expert.
