---
name: review
description: Review pass — review + security + quality gates.
---
# /review
Run the change set through the review trio (read-only):
1. **review-agent-csk** (code-review) — "does it improve overall code health"; severity-ranked comments.
2. **security-expert-csk** (security-scan) — auth/IDOR/injection/secret; findings with severity.
3. (if SonarQube is in use) **sonarqube-check** — 0/0/0/0 gate (language-agnostic).

Each agent returns a **short summary** to the main thread; raw output goes to `docs/` if needed. Do NOT modify code;
collect findings in severity order, and leave the fix to the relevant expert.
