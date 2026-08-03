---
name: ci-pipeline
description: |
  CI pipeline discipline: lint→build→test→quality→security, fail-fast, deterministic build, secret handling, PR gates.
---

# CI Pipeline

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "ci", "pipeline", "github actions", "build pipeline", "pr gate", "workflow"

## Stages (fail-fast — stop if it breaks early)
1. **Lint / format** — style and static analysis
2. **Build** — 0 warnings / 0 errors
3. **Test** — unit + integration, coverage collected
4. **Quality** — `sonarqube-check` quality gate
5. **Security** — `dependency-audit` + `security-scan` (where applicable)
6. **Artifact / packaging** — (deployment is separate, `vps-deploy`)

## Principles
- **Deterministic:** dependencies pinned, cache keyed correctly; no "it worked on my machine".
- **Secret management:** CI secret store; NO plaintext secrets in the repo/logs (overlaps with trace scan).
- **PR gate:** quality gate + tests must pass; a red build is not merged.
- **Branch protection:** direct push to main is disabled; PR + review required.

## DoD
- All stages green; PR gates enforced; no secret leakage; build reproducible.
