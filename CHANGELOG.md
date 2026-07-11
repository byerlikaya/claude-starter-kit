# Changelog

Notable changes to this project are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/),
versioning follows [SemVer](https://semver.org/).

## [1.1.11] - 2026-07-11

### Changed
- **On takeover, `adopt` imports a taken-over agent's domain into an active project skill instead of only
  archiving it.** Before, the overlapping project agent was moved to `.claude/superseded/agents/` (inert), so its
  domain knowledge dropped out of the working setup. Now each taken-over agent is converted to a draft skill
  `skills/<name>-local` — its description and body carried over, a Trigger-phrases line added — which the kit's
  `-csk` agent applies (agent = who/when, skill = the how). The raw original is still backed up under
  `superseded/agents/`. The generated skill is a draft to refine.
- **The always-on byte budget now gates only the kit's payload, not an installed project.** In a project your own
  agents/skills (including the ones adopt imports) legitimately add to the always-on cost, so `smoke-test.sh`
  reports the numbers there instead of failing; it still fails in the kit repo. A CI e2e now runs the adopted
  project's own smoke-test to catch a malformed import.

## [1.1.10] - 2026-07-11

### Fixed
- **`adopt` could fail to open its handover branch when run twice in the same repo within one second.** The branch
  is named `kit-adopt-<timestamp>` at one-second resolution, so a second adopt in the same second collided with the
  first and `git checkout -b` failed. It now appends a counter until the name is free. This also surfaced as a flaky
  CI adopt e2e (the refresh scenario runs adopt twice); the fix makes it deterministic.

## [1.1.9] - 2026-07-11

### Changed
- **The "ask with options at a decision point" rule now demands a structured form.** The discipline already asked
  for options with a recommendation, but the wording ("present explicit options") let a model satisfy it with a
  prose "X, or Y?" question. It now reads "ask with numbered options (never an open-ended either/or), each with a
  recommendation" — so a decision is put as a clear multiple choice, not an open question. This is model discipline,
  not a tool-level gate (asking a question is plain text with no call to intercept), so it raises adherence rather
  than enforcing it.

## [1.1.8] - 2026-07-11

### Fixed
- **`adopt` can correct a stale `generic` stack on refresh.** A project adopted before the deeper stack detection
  (1.1.7) may carry `stack=generic` in `kit.conf` even though it is clearly DevArchitecture. A refresh trusts the
  recorded stack by design, so that stale value used to stick — keeping `devarch-module` pruned and the generic
  backend agent in place. adopt now notices the mismatch (recorded `generic` + a `Business/Handlers` + `.sln`
  layout), surfaces it, and offers to correct it to `dotnet`, which restores `devarch-module` and the .NET backend
  agent. It never flips silently; a CI e2e covers the correction.

## [1.1.7] - 2026-07-11

### Fixed
- **`adopt` misread a .NET project as generic when the solution lived under `./backend`.** The stack sniff only
  looked at the repo root (`ls ./*.sln`), so a DevArchitecture project with its `.sln` under `./backend` fell back
  to the generic backend and dropped the `devarch-module` pattern skill. It now searches a few levels deep, detects
  the DevArchitecture `Business/Handlers` layout, and on an interactive fresh adopt confirms the choice. The generic
  prune of `devarch-module` also applies to a fresh adopt now, so a generic project no longer carries a .NET pattern
  skill it never uses.

### Added
- **`adopt` resolves same-domain agent overlaps instead of only noting them.** When a project already has an agent
  covering the same job as a kit agent (e.g. `backend-expert` vs `backend-expert-csk`), the router had two candidates
  and usually picked the project's older one — so the kit's agent sat idle. adopt now detects the overlap and offers
  **takeover** (the kit's `-csk` wins; your agent is moved to `.claude/superseded/agents/`, preserved so you can fold
  its domain into a project skill), **keepmine** (your agent wins; the kit's overlapping `-csk` is not installed), or
  **coexist** (keep both, documented). A non-interactive adopt defaults to takeover. A CI e2e test locks down both the
  deeper stack detection and the overlap takeover.

## [1.1.6] - 2026-07-11

### Added
- **A skill catalogue in the README, generated from the skills themselves.** Readers can now see all 28 skills
  with a one-line summary of each — in a collapsible *Full catalogue* block — instead of a vague "and more".
  `packaging/build-readme-catalog.sh` builds the table from every `SKILL.md` frontmatter (the single source)
  and its `--check` mode fails CI and the release if the README drifts from the skills, so the count can never
  go stale again the way 27-vs-28 did. The table is English in both READMEs (skill names are English identifiers).

## [1.1.5] - 2026-07-11

### Changed
- **The backend expert is now pattern-neutral; DevArchitecture is the default, not the identity.**
  `backend-expert-csk` was branded "owner of the DevArchitecture pattern" with its layout, result types, and
  AOP order hardcoded — and the `--generic` stack shipped that same DevArch-branded agent, just without its
  skill. The agent now applies the project's **backend-pattern skill** — `devarch-module` (MediatR CQRS /
  IResult / AOP) by default; a project on another pattern (Clean Architecture, Vertical Slice, Minimal API,
  plain layered) declares its own pattern skill under `.claude/skills/` and the agent follows that instead.
  This restores the kit's own rule (agent = who/when, skill = how) and gives a coherent story for a backend
  that is not .NET/DevArchitecture. Nothing forces DevArch.
- `adopt.sh` infers a legacy project's stack from the presence of the `devarch-module` skill instead of
  grepping the agent text (no longer a reliable signal). The template `CLAUDE.md`, the `devarch-module` skill,
  and the `start.sh` generic wizard now document the pluggable-pattern story.

## [1.1.4] - 2026-07-11

### Added
- **`iterate` skill — a bounded refine-to-Done loop.** Names the discipline the kit already leaned on:
  don't stop at the first attempt, repeat change → verify → check until the acceptance criterion is
  objectively met (tests green, review clean, nothing deferred), reporting the gap each round and stopping
  after two rounds with no progress. Distinct from the harness `/loop` (which schedules a prompt on an
  interval); it never commits, pushes, or deploys on its own — §4.4 approval still gates the commit — and it
  keeps to the token discipline. Reaches full installs and the plugin edition (both ship `skills/`).

## [1.1.3] - 2026-07-11

### Changed
- **`review-agent-csk` is now named in the Definition of Done, not only in the Close flow.** The Close phase
  already gated a commit on a clean review, but the DoD checklist the model measures "am I done?" against did
  not list it — so on a logic-bearing change "commit directly" could surface as a peer option to reviewing. It
  now sits on the Done line beside tests-green and the triggered skills. (Reaches full installs via
  `start.sh` / `adopt.sh`; the plugin-lite edition ships no discipline, so it is unaffected.)

## [1.1.2] - 2026-07-11

### Fixed
- **The session-fill hook timed out on Windows, so the measured `🔋 Session` line never reached the model.**
  `context-usage.sh` scanned the whole transcript on every turn, though the only record it needs — the last
  main-context turn's usage — sits 1–3 lines from the end of the file (43 at worst across 71 real transcripts).
  Stock Git Bash on Windows ships no `jq`, so the slower `awk` path runs: on a 180 MB transcript it took ~4.7 s,
  and with MSYS fork cost and a cold Defender scan it blew the hook's 10 s ceiling. The hook was killed and its
  output discarded, so context fill could not be measured. It now reads the tail (`tail -n 200`, widening to
  `2000`, then the whole file only as a fallback); a window too small to contain the record can only come back
  empty, never stale. Same number as before — measured byte-identical across 71 transcripts on both engines — at
  ~40 ms instead of 4.7 s.
- **On the `jq`-less path a returning subagent's usage was read as the session's own fill.** When a subagent
  returns, its result lands in the main context as a `type:"user"` record whose `toolUseResult.usage` is raw,
  unescaped JSON. The `awk` text-scan matched it and reported the *subagent's* tokens: a 92%-full context showed
  0.9% → "continue", so the 75%/90% handoff gate stayed silent exactly when it mattered — reachable by
  interrupting a subagent. Both engines now require `"type":"assistant"`, which the raw sub-record cannot satisfy;
  `jq` was already anchored at `.message.usage` and unaffected. Verified against a reproduction of the exact bug.
- **The three hook timeouts move from 10 s to 30 s** — Claude Code's own documented default for a
  `UserPromptSubmit` hook, which the kit had set *below*. On the success path the tailed script returns in well
  under 100 ms; the raised ceiling only absorbs a cold-disk worst case, and a timeout never blocks the prompt
  itself. `smoke-test.sh` §6i locks down the tail ladder, the anchor, and the poison case on both engines.

## [1.1.1] - 2026-07-10

### Fixed
- **The `pre-commit` scanners went blind on a large staged diff.** Both scanners fed the added lines to `grep -q`
  through a pipe. `grep -q` exits on its first match, the pipe closes, `printf` dies of `SIGPIPE` (141), and
  `set -o pipefail` turns that into a failed `if` — so a match counted as no match. Small commits were scanned;
  large ones were not, and an AI-authorship trace or a live secret sailed through silently. Reproduced: a JWT in a
  20,000-line staged diff was committed with no warning. The added lines now go to a temp file and every pattern
  greps that file, so no pipe can close early. `smoke-test.sh` locks it down.
- **A project that shares `.claude/` could not commit it.** `adopt.sh` offers to track `.claude/` so a team shares the
  kit, but the trace scan then found the tool's name inside the kit's own scripts and blocked the commit — the kit
  failed its own rule. The trace scan now skips `.claude/`: that tree configures the assistant, legitimately names
  the tool it configures, and an update overwrites it. **The secret scan still covers `.claude/`** — a token pasted
  into `settings.json` is still a token. §4.3 no longer claims `.claude/` is always local.
- **An update that lands while a session is running is now announced.** `CLAUDE.md` and the discipline it imports are
  read once, at session start. Updating the kit mid-session replaced every file on disk while the rules already in the
  model's context stayed at the previous version — so the assistant kept quoting rules that no longer existed (for
  example, telling you to set `CLAUDE_GIT_OK=1` long after the commit gate had learned to ask you directly), and
  nothing said otherwise. `context-usage.sh` now stamps `.claude/VERSION` on the session's first turn, compares it on
  every later turn, and injects `⚠️ kit updated X → Y mid-session` until the session is restarted. It fails open: no
  stdin, no `session_id` or no `VERSION` means silence, and it never fires on the `Stop` payload `session-guard.sh`
  pipes through the same script.
- `start.sh` and `adopt.sh` close by telling you to restart Claude Code if it is already open in the project.

## [1.1.0] - 2026-07-10

### Added
- **In-session commit approval.** `guard-bash.sh` answers `PreToolUse` with `permissionDecision: "ask"`, so you approve
  `git commit` / `git push` at a prompt only you can answer and the assistant then runs it — instead of the gate
  handing you a command to paste into your own terminal. Verified honoured in `default`, `acceptEdits`, `auto` and
  `dontAsk`; `bypassPermissions` and any unrecognised mode **fail closed**. `CLAUDE_GIT_OK` remains a headless/CI
  pre-authorisation and never substitutes for approval. §4.5 destructive operations stay a hard block in every mode.
- **`.claude/kit.conf`** records the profile, backend stack and installer. The updater refreshes a project in the shape
  it was installed in, and derives that shape from the installed files when the stamp is absent.
- **`claude-starter/profiles.conf`** — one source for the profile → pruned agents/skills map, read by both installers.
- **`.claude/DISCIPLINE.md` + `@import`.** `start.sh` now installs the discipline as a separate kit-owned file, joined
  to your `CLAUDE.md` by one import line, so discipline updates reach installed projects. `adopt.sh` detects an inline
  (pre-`DISCIPLINE.md`) layout, shows which lines it occupies, and offers to migrate it after writing a backup.
- **Second session warning at 90%**, on top of the one at 75%.
- **Always-on token budget gate.** `smoke-test.sh` fails when the discipline or the agent/skill descriptions exceed
  their byte budget, and asserts every agent and skill still declares its trigger phrases.
- **`context-usage.sh --verbose`** for the long form with raw token counts.

### Changed
- The `Stop` hook no longer blocks with `exit 2`. It emits a `systemMessage` once per threshold, so it neither renders
  as `Stop hook error` nor forces an extra assistant turn on every reply past 75%.
- The line injected into context each turn is compact; `--verbose` keeps the long form.
- Discipline and agent/skill descriptions trimmed from 11,205 to 9,198 tokens (measured on a real turn). Rules and
  trigger phrases are untouched; only explanations of rules a hook already enforces were compressed.
- §4.4 in `CLAUDE.md` corrected: the hook does receive `permission_mode`, and `settings.json` carries no `deny` rule
  for git — the gate is the hook.

### Fixed
- `adopt.sh` split `CLAUDE.md` on `<PROJE ADI>`, a marker that stopped matching once the payload was translated to
  English, so `DISCIPLINE.md` swallowed the whole file including the project template. The split now uses an anchored
  `KIT:DISCIPLINE-END` sentinel and both installers abort if it is missing.
- The `@import` check matched the path anywhere in the file, including prose, so a `CLAUDE.md` that merely mentioned
  `.claude/DISCIPLINE.md` never got the import — and never loaded the discipline.
- Refreshing a `--backend` project re-added the frontend agents (10/24 → 11/27), and a `--dotnet` project had its
  DevArchitecture backend expert replaced by the generic variant.
- `context-usage.sh`'s no-jq fallback counted sidechain (subagent) records and summed only `cache_read`, producing a
  percentage that was both understated and polluted.
- Every `awk` is pinned to `LC_ALL=C`; a `tr_TR` locale emitted `%77,2` into the threshold comparison.
- The installers strip `CR`, so a CRLF checkout of `profiles.conf` or `kit.conf` can no longer silently disable
  profile pruning.

## [1.0.9] - 2026-07-08

### Changed
- **Surfaced `FIRST_PROMPT.md`:** `start.sh`'s closing message and the README now point to `.claude/FIRST_PROMPT.md`
  — the optional first-message kickoff that verifies the agents/skills and plans the first sprint. It was installed
  but never referenced anywhere, so it looked like an unexplained stray file.

## [1.0.8] - 2026-07-08

### Fixed
- **Windows launch made robust (Git Bash + WSL):** the `npx` runner now (a) prefers **Git Bash** if installed —
  it accepts `C:/…` paths natively and avoids WSL's `/mnt/c` and 8.3-name pitfalls; (b) expands 8.3 short paths
  (`…\BB358~1.YER\…`) before staging; and (c) under WSL translates the Windows path to `/mnt/c/…` inside bash,
  dispatched by shell flavour. If the staged script still can't be read it now fails with an actionable message
  instead of a cryptic "No such file or directory". macOS/Linux run unchanged (no path rewriting).
- Shell scripts pinned to LF via `.gitattributes` so a Windows checkout can't flip them to CRLF.

## [1.0.7] - 2026-07-08

### Fixed
- **Windows (Git Bash) launch:** `npx` passed a native Windows path (`C:\Users\…\start.sh`) to bash, which treats
  `\` as an escape — so the path separators were lost and the script wasn't found ("No such file or directory").
  The runner now hands bash a forward-slash path (`C:/Users/…/start.sh`), which Git Bash resolves. macOS/Linux unaffected.

## [1.0.6] - 2026-07-08

### Added
- **Secret-scan gate:** `pre-commit` now also blocks staged **API keys / tokens / private keys** (AWS, GitHub,
  Google, Slack, Stripe, OpenAI/Anthropic, npm, SendGrid, JWT, and PEM private keys) — the same
  diff → pattern → block machinery as the trace scanner, with a repo-root `.secret-allowlist.txt` for exceptions
  and a smoke-test proof that a staged key is blocked. Prints the matched pattern, never the secret value.

## [1.0.5] - 2026-07-08

### Changed
- **Agent namespace `-cck` → `-csk`** (Claude Starter Kit) to match the project name — all 11 agents and every
  reference across the kit, plugin, and diagrams.
- **`update.sh` renamed to `adopt.sh`** so the tarball's entry point matches the `adopt` command that npx and Homebrew already use.
- **README refresh:** the title is now "Claude Starter Kit"; "Why this kit?" leads with standout features (a team,
  not a prompt · security & privacy gates); the agents table and the handover diagram were clarified; attribution
  was folded into the README (the four-principles source credited) and `ATTRIBUTION.md` removed.

## [1.0.4] - 2026-07-08

### Changed
- **`adopt.sh` (adopt) leaves the change set STAGED, not committed:** the kit files land on the handover branch
  staged-but-uncommitted, so every added/changed file is visible in your editor's Source Control / Changes panel
  for review. You commit to accept (`git commit`) or discard with one reset — nothing is buried in an auto-commit.
  (Previously everything was auto-committed on the branch, so a developer saw nothing in the Changes view.)

### Fixed
- **Trace scanner no longer trips over its own pattern list:** `pre-commit` excludes `.claude/hooks/trace-blocklist.txt`
  from the scan (it definitionally contains every pattern), so a shared/tracked `.claude` can be committed without
  the scanner blocking on its own blocklist. Real AI traces in project files are still caught.

## [1.0.3] - 2026-07-08

### Fixed
- **`adopt.sh` (adopt) re-run was unsafe:** running adopt on an already-adopted project made the git-shim
  reference itself → infinite recursion on every commit. Adopt now detects a prior install (**REFRESH mode**),
  never shims its own hooks, refreshes kit-owned files, and excludes the kit's `-csk` agents/skills from the
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
- **Confirmation prompt rejected `yes`:** `ask_yes` (`start.sh`/`adopt.sh`) only accepted `evet/e/y`, so typing
  `yes` at the English `[yes/no]` prompt cancelled the install. Now accepts `yes/y/evet/e`.
- **`adopt.sh` decision keys were Turkish:** the Stage-B override labels and internal keys (koru/gevset/gizle…)
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

[1.0.9]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.9
[1.0.8]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.8
[1.0.7]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.7
[1.0.6]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.6
[1.0.5]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.5
[1.0.4]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.4
[1.0.3]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.3
[1.0.2]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.2
[1.0.1]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.1
[1.0.0]: https://github.com/byerlikaya/claude-starter-kit/releases/tag/v1.0.0
