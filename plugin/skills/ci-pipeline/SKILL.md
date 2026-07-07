---
name: ci-pipeline
description: |
  CI pipeline discipline: lint→build→test→quality→security stages, fail-fast,
  deterministic build, secret management, PR gates. Runs when the CI configuration changes.
  Trigger phrases: "ci", "pipeline", "github actions", "build pipeline", "pr gate", "workflow"
---

# CI Pipeline

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
