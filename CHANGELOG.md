# Changelog

Notable changes to this project are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/),
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Added
- **`devops-expert` agent (11th)** — ops/devops specialist; owns the `ci-pipeline` · `vps-deploy` · `incident-runbook`
  skills (these skills are no longer orchestration-only). Core (in all profiles). Produced with a design panel plus
  4-lens adversarial verification.
- **Deploy tool-level gates:** `ssh`/`scp`/`rsync`/`docker` added to `permissions.ask` in `settings.json` —
  outward-facing deploy verbs now hit approval at the tool level (not just at the LLM behavior level).

### Fixed
- **Auto-rollback conflict:** `vps-deploy` rollback uses an atomic `rsync --delete` instead of `rm -rf`,
  so `guard-bash` (its local `rm -rf` block) no longer blocks automatic rollback (local rm -rf protection remains).

### Changed
- `privacy-agent` and `privacy-compliance`: the official KVKK (kvkk.gov.tr) and GDPR (gdpr-info.eu) sources
  were added as authoritative references; rule interpretation always follows these channels, and the article relied upon is stated in the finding.
- **Skill ownership clarified:** domain skills were explicitly bound to their owning specialist agents (backend-expert →
  api-design/observability/performance/dependency-audit/i18n-integrity; frontend-expert → a11y/i18n/observability/
  performance/dependency-audit; security-expert → red-team; review-agent → docs-writer; planner → adr;
  commit-agent → release; session-manager → token-budget). `i18n-integrity` was made **core** (the backend also
  produces user-facing text). Only the hook/ops skills (trace-scan, ci-pipeline, vps-deploy,
  incident-runbook) were deliberately kept orchestration-owned.

## [1.0.0] - 2026-07-03

First stable release. A Turkish, opinionated-but-backend-optional agent/skill scaffold.

### Added
- **10 agents** (thin triggers) + **27 skills** (the discipline layer: code review, security, database,
  deployment, observability, documentation, accessibility, api design, performance, incident response,
  red-team, i18n, privacy, release, and more).
- **Profiled setup wizard** (`start.sh`): `--backend/--frontend/--mobile/--fullstack` +
  backend stack `--dotnet` (full DevArchitecture) / `--generic` (stack-agnostic). Interactive when no flag is given.
- **DevArchitecture backend foundation**: included verbatim behind an approval gate in a from-scratch project; a warning in an existing project.
- **Rule→gate**: trace scan (`pre-commit`/`commit-msg` + repo-specific `.trace-allowlist.txt`), `guard-bash.sh`
  destructive block, `settings.json` permission gates.
- **Real context measurement**: `context-usage.sh` reads the actual fill from the transcript; the `UserPromptSubmit`
  hook injects it every turn — session health rests on measurement, not guesswork.
- **Verification**: static `smoke-test.sh` + behavioral `routing-eval.sh` (golden routing + conflicts).
- **CI**: GitHub Actions runs syntax + smoke + routing + 6-profile e2e rehearsal on every push/PR.

### Notes
- The discipline layer and the frontend are stack-agnostic; the backend is opinionated (.NET/DevArchitecture) or generic.
- Language is Turkish. No AI trace / third-party template name leaks into the artifacts (§4).

[1.0.0]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.0
