# Changelog

Notable changes to this project are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/),
versioning follows [SemVer](https://semver.org/).

## [1.0.4] - 2026-07-08

### Changed
- **`update.sh` (adopt) leaves the change set STAGED, not committed:** the kit files land on the handover branch
  staged-but-uncommitted, so every added/changed file is visible in your editor's Source Control / Changes panel
  for review. You commit to accept (`git commit`) or discard with one reset — nothing is buried in an auto-commit.
  (Previously everything was auto-committed on the branch, so a developer saw nothing in the Changes view.)

### Fixed
- **Trace scanner no longer trips over its own pattern list:** `pre-commit` excludes `.claude/hooks/trace-blocklist.txt`
  from the scan (it definitionally contains every pattern), so a shared/tracked `.claude` can be committed without
  the scanner blocking on its own blocklist. Real AI traces in project files are still caught.

## [1.0.3] - 2026-07-08

### Fixed
- **`update.sh` (adopt) re-run was unsafe:** running adopt on an already-adopted project made the git-shim
  reference itself → infinite recursion on every commit. Adopt now detects a prior install (**REFRESH mode**),
  never shims its own hooks, refreshes kit-owned files, and excludes the kit's `-cck` agents/skills from the
  "project" counts (the earlier "N custom agents" over-count).
- **Confusing decision override:** the number-picker (`[1-4,6,7]`) that silently rejected lists like `1,2,3`
  and swallowed invalid answers is replaced by "Accept all suggestions? [yes/no]" then a per-decision walk that
  shows the current value, treats ENTER as keep, and re-asks on invalid input.
- **`#4 hide` broke review/rollback:** it gitignored `.claude` before the branch commit, so the payload was
  absent from the diff and survived rollback. The payload is now always committed to the review branch; hide
  becomes a documented post-merge step in HANDOVER.
- Precedence (`#2`) is fixed to project-wins (no longer a no-op that could write a contradictory HANDOVER);
  the non-.NET backend swap no longer clobbers a preserved file; PROOF-1 measures the scanner (not the
  project's allowlist) and matches the current hook output; HANDOVER/ADR use the real base branch, not literal `main`.
- **Remaining Turkish removed from public surfaces:** the CI workflow's job/step names and the generated ADR
  filename (now `docs/adr/0001-agentic-kit-adoption.md`) are English.

## [1.0.2] - 2026-07-08

### Changed
- **Fullstack layout:** on `--fullstack` + `--dotnet`, the DevArchitecture backend is now placed in `./backend`
  (was the project root) and `./frontend` is reserved for the frontend — the root no longer looks like a bare
  backend project. The solution file is renamed to the project's name (taken from the directory); the full
  namespace rename stays the agent's first task (§4.2).

## [1.0.1] - 2026-07-08

### Added
- **`devops-expert` agent (11th)** — ops/devops specialist; owns the `ci-pipeline` · `vps-deploy` · `incident-runbook`
  skills (these skills are no longer orchestration-only). Core (in all profiles). Produced with a design panel plus
  4-lens adversarial verification.
- **Deploy tool-level gates:** `ssh`/`scp`/`rsync`/`docker` added to `permissions.ask` in `settings.json` —
  outward-facing deploy verbs now hit approval at the tool level (not just at the LLM behavior level).

### Fixed
- **Confirmation prompt rejected `yes`:** `ask_yes` (`start.sh`/`update.sh`) only accepted `evet/e/y`, so typing
  `yes` at the English `[yes/no]` prompt cancelled the install. Now accepts `yes/y/evet/e`.
- **`update.sh` decision keys were Turkish:** the Stage-B override labels and internal keys (koru/gevset/gizle…)
  are now English (keep/loosen/hide…), with matching input letters.
- **Auto-rollback conflict:** `vps-deploy` rollback uses an atomic `rsync --delete` instead of `rm -rf`,
  so `guard-bash` (its local `rm -rf` block) no longer blocks automatic rollback (local rm -rf protection remains).

### Changed
- **Distribution + English:** the kit was fully translated to English (with a `README.tr.md` mirror) and is now
  distributed via npm (`@byerlikaya/claude-starter-kit`), Homebrew (`byerlikaya/tap/claude-starter-kit`), and a
  Claude Code plugin; a tagged release publishes to all three automatically.
- npm `bin` exposes only `claude-starter-kit` (dropped the `claude-kit` alias) for name consistency.
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

[1.0.4]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.4
[1.0.3]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.3
[1.0.2]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.2
[1.0.1]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.1
[1.0.0]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.0
