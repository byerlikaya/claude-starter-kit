# Changelog

Notable changes to this project are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/),
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Changed
- **BREAKING — one install shape.** `start.sh` no longer asks for a project profile. Every install ships all 12
  agents and all 38 skills; the wizard is two steps (backend pattern → summary), and `claude-starter/profiles.conf`
  is gone. The `--backend` / `--frontend` / `--mobile` / `--fullstack` flags are accepted and ignored, with a
  notice, so an existing command line still installs — it just installs everything.

  The split was sold as a way to spend less context. Measured against the payload: the widest pruning saves
  **1,467 bytes ≈ 367 tokens** (`--backend`), 1,615 ≈ 404 (`--frontend`), 1,437 ≈ 359 (`--mobile`) — against a
  13,267-byte total, and ~0.2% of a 200k window. The one argument that could have justified it, Claude Code's
  1%-of-context skill **listing budget**, was already answered by `skillListingBudgetFraction: 0.04` shipped in
  1.10.0; pruning four skills never brought a 7,208-character listing under a 2,000-character budget. The ledger
  on the other side is concrete and in this changelog: a sleeping agent on `--generic`, route-hint cases that
  failed on every pruned profile, and an e2e matrix that took 77 of a 89-minute Windows job. `adopt.sh` never
  pruned by profile and the plugin edition never had profiles at all — so two of three channels already shipped
  the full set, and the third's difference was the bug surface.

  Consequences kept deliberate: **`.NET/DevArchitecture ↔ generic` is still asked on every install** — that skill
  is genuinely wrong in a Node repo, and it remains the only component the installer removes. The DevArch layout
  (`./backend` + a reserved `./frontend`) applies to every `--dotnet` install rather than one profile.
- **`code-review-csk` stands on three layers instead of one archived repository.** google/eng-practices was
  archived read-only on 2025-11-21 and has no successor; the skill was resting its whole spine on it. The layers
  are now separated by the question each one answers. **Judgement** is the kit's own — the two-stage verdict and
  verifier integrity, which exist because the code under review is increasingly agent-written and no external
  standard covers that. **Governance** is NIST SP 800-218 **PW.7** and the OpenSSF Scorecard **Code-Review**
  check. **Comment vocabulary** is Conventional Comments. eng-practices stays attributed for what is genuinely
  adapted from it — the nine-item priority order and the "improves overall code health" bar — because CC-BY 3.0
  obliges that whether or not the repository is archived, and dropping the credit while keeping the derivation
  would be a licence violation, not a cleanup.

  Deliberately **not** adopted: the claim circulating that PW.7/PW.8 "become mandatory when AI is the author".
  That is a vendor's June 2026 proposal *to* NIST, not published NIST policy, and citing it as a standard would
  be exactly the kind of unverified claim the review skill exists to catch.

  Two capabilities came out of the re-grounding rather than the rename. **Comments carry a label**
  (`issue` · `suggestion` · `nitpick` · `question` · `todo` · `praise`, with `(blocking)`/`(non-blocking)`
  decorations) mapped onto the existing blocker/suggestion/nit split — an agent writes these and something has to
  sort them without reading each one. And **every finding now leaves the review with a disposition** — fixed,
  tracked, accepted or dropped — which PW.7.2 requires ("record and triage all discovered issues") and the skill
  had no notion of: findings were reported and then nothing. Blockers may only be fixed or tracked, and the agent
  cannot grant itself "accepted".
- **The updater completes a narrower install instead of preserving it.** A project whose `kit.conf` carries a
  pre-2.0 `profile=` key gets the missing components installed, **each one named** in the output, and the key
  removed so the notice retires after one run. The list is derived from a before/after disk diff, not from a
  profile→pruned table, because that table is what was deleted. `stack=` is untouched: a `generic` project does
  not acquire `devarch-module` on the way through.

### Fixed
- **A gate that took three other gates down with it when its subject was deleted.** Every assertion in
  `smoke-test §6e` — including the README agent-count check and the EN/TR structural parity check added earlier
  in this release — sat inside `if [ -f profiles.conf ]`. Removing that file did not turn the section red; it
  turned the section **off**, and the suite reported PASSED. The replacements are inverse and unconditional
  (`profiles.conf` must not exist; neither installer may carry prune code; `kit.conf` must not carry `profile=`),
  and the count check now asserts that `start.sh` derives its numbers from the payload rather than printing a
  literal. Proved by injection in six directions, each one red before the fix and green after.
- **Two routing suites absorbed a missing component instead of reporting it.** `routing-eval` skipped any target
  it could not find and `§7y` printed a note for an uninstalled agent — correct while profiles pruned them, and a
  blindfold once every install ships everything. Both now fail; `devarch-module` on a generic backend is the one
  remaining legitimate skip. `routing-eval` reports **0 skipped** on a full payload.
- **The two channels could ship different component sets with nothing comparing them.** `e2e.sh` now diffs an
  installed `.claude/` against the plugin edition and fails on any divergence — the class that produced the
  sleeping generic agent above. The rehearsal drops from six profile combinations to two backend patterns plus a
  legacy-flag case, and asserts the component counts instead of printing them.
- **A `--generic` install shipped a backend owner that never woke up — and two gates were looking the other
  way.** On a non-.NET stack the installer swaps in `agents-optional/backend-expert-generic.md`, whose
  description read "Writes and edits … *Kicks in for* new backend features" against the .NET variant's
  "**Use proactively — owns server behaviour** … whatever its size or wording". That missing cue is precisely
  the defect 1.5.0 diagnosed as agents sleeping, still live on the generic path.
  It survived because the suite answered two questions by DIRECTORY rather than by fact:
  - `agents-optional/` was reached by exactly one of nine agent checks (routing parity). The other eight —
    frontmatter, skill references, Trigger phrases, the delegation cue — iterate `agents/` only, so a file the
    installer *moves into* `agents/` was ungated in the repo it ships from.
  - In an install the file IS scanned, and the escape hatch meant for a project's own components excused it:
    `✅ some agents lack a proactive cue: backend-expert-csk (your project's own agents, not gated)`. It is a
    kit agent. `.claude/kit-manifest.txt` has recorded exactly that distinction since 1.8.0 and none of the
    four hatches consulted it.

  Both are fixed at the root. `agent_quality_files()` widens the five checks that judge a file's own quality,
  and deliberately not the three that reason about the installed set (agent count, always-on byte budget,
  orphan routing) — a swap-in replaces its counterpart rather than adding to it. `kit_owned()` makes the four
  hatches ask the manifest instead of the context; with no manifest they stay lenient, because absence of
  evidence is not ownership. Verified on a live `--generic` install in three directions: a kit-owned component
  that regresses now fails, a user's own agent is still only noted, and the generic variant passes once its
  description carries the cue.
- **Nothing compared the two READMEs, so an edit reached one language and shipped.** `README.md` received a
  corrected claim and a whole "Honest scope" blockquote that never reached `README.tr.md`, and every gate
  stayed green — only the skill catalogue and the agent count had ever been compared. `smoke-test` now checks
  structural parity: the heading-level sequence, table rows, code fences, and blockquote **blocks** (blocks,
  not lines — Turkish wraps longer). It reproduces the real divergence as `14` blocks against `13`.
- **`vps-deploy` runtime detection covered four runtimes and singled one out in prose.** The heuristic knew
  docker/node/python/go; .NET was absent from it but got a bespoke sentence, and Java, Rust, Ruby and PHP got
  neither. Detection now covers eight, the release-artefact step names each runtime's own command, and no
  runtime is privileged in prose.
- **The README claimed breaking a critical rule was "impossible" — the guard script says "defence-in-depth".**
  The kit's own source contradicted its front page, and for a security-adjacent audience an overclaim that is
  found is worse than a modest one. Both languages now state the real scope: the gate answers before the
  command runs and removes the *accident*, the shell is Turing-complete so a determined rewrite can reach
  around any pattern, and a hard boundary means a devcontainer or a VM — which `/doctor-csk` already reports on.
- **The mandatory security and privacy audits ran on a weaker model than the code they were reviewing.** Both
  were pinned `model: sonnet`, set in the July 8 rename commit and never revisited across 156 commits. An
  omitted `model` field means `inherit` — the model the user picked for the session — so on an Opus session the
  experts wrote code on Opus and the gate that clears them ran on Sonnet. That is backwards for the one review
  this kit calls mandatory, and it is the opposite of what Claude Code does with its own built-in Explore
  agent, which inherits the session model *capped* upward so it "never runs on a more expensive model than the
  one you already chose" — inherit, cap up, never force down.
  Both pins are gone. `security-expert-csk` buys its extra rigour with **`effort: high`** instead: more
  thinking on the user's own model rather than a different tier. `session-manager-csk` also loses its `haiku`
  pin — the handover is a synthesis over an entire session that decides what the next one knows, and its
  failure mode is silent. `commit-agent-csk` keeps `haiku` deliberately: turning a staged diff into a
  Conventional Commit is mechanical, and §4.1/§4.4 are gated, so a slip is caught rather than shipped.
  Two new gates so this cannot come back quietly: a `model:`/`effort:` value must be one the docs define (an
  unrecognised one does not error — Claude Code skips it and silently runs the inherited model, so a typo
  looks like it worked), and the mandatory audit agents must stay unpinned. Verified by injecting each
  deviation and confirming the matching case goes red.
- **Nothing in the suite ran a hook the way Claude Code runs it.** All 300-odd gate cases pipe into
  `bash "$HOOKS/<hook>.sh"`, which supplies the interpreter and ignores the shebang — so a lost execute bit or
  a CRLF line ending, the two failures an installer can actually introduce on Windows, survived every single
  case and would have died in a real session. One case now executes the hook **as an executable**, the way
  `settings.json` invokes it. Verified on a real install in three states: intact passes, `chmod -x` gives 2
  errors, a CRLF shebang gives 1.
- **The route-hint cases failed on every pruned profile.** §7y asserts that the hook names
  `backend-expert-csk` for a backend request, but a `--frontend` install prunes that agent, so the hook
  correctly said nothing and the case failed it for obeying its own rule — naming an agent that is not
  installed is exactly the wrong route those cases exist to prevent. A case now skips, visibly, when its owner
  is absent. This reached CI because `e2e.sh` runs the INSTALLED suite inside six pruned profiles while only
  the source tree had been checked locally; it failed with `rc=1` and no output, the same `set -euo pipefail`
  signature this repo has been bitten by before.
- **The brand mark had three hand-kept copies and no gate.** Four SVGs were down as orphans to delete on the
  strength of a grep that could not see them being used — because two of the uses are not file references (the
  published site inlines the mark as a `data:` URI favicon, `gen-network.py` hand-copies the same rects into
  the diagram core), and because the grep ran over the working tree while `gh-pages` is a separate branch.
  `assets/favicon.svg` was byte-identical to `assets/icon.svg` and is gone; `icon.svg` is now the single
  source, `gen-network.py` says so at the copy site, and `check-gh-pages.sh` compares all three on shape
  rather than bytes. `logo-light.svg` and `mark.svg` stay — light-background and transparent variants of a
  logo the READMEs do use.

### Changed
- **The README led with the half of the kit that has the least evidence behind it.** The old opening sold
  "gates, not reminders" — and the measurement says the opposite of what that implies: across the A/B suite the
  only case where the two arms separated was won by the always-on *discipline text*, with `guard-bash` never
  firing. Meanwhile the strongest, most falsifiable number the project owns — delegation going from **0 of 24**
  to **39 of 48** — sat in a single table cell, and `evals` appeared **zero times** in either README, so the
  one thing hardest for anyone else to copy (an A/B harness whose negative results are published) was invisible.
  The opening is now three claims with a number behind each: the specialists run, the rules are gates, and
  **it says what it has not proven** — linking straight to the six level results and to the awkward attribution
  above. The comparison table's left column was a strawman ("typical agent kit / prompt collection"); it is now
  **Claude Code with a `CLAUDE.md`**, which is not a competitor at all but the exact control arm the harness
  measures, so the table can be checked rather than taken on faith. `adopt` moved up out of a table row: it is
  the situation most readers are actually in. the gate units were being re-run in every pruned profile.** The step
  breakdown put 77m29s of it in the e2e rehearsal, which runs the installed smoke-test seven times — and one
  run spawns 136 hook processes, each spawning `jq`, which is what Windows charges for. Those cases drive hook
  binaries the installer copies unchanged, so six profiles re-verified identical bytes six times.
  `CSK_SMOKE_SCOPE=install` skips them: **136 hook processes drop to 9, 304 cases to 165**, and everything
  profile-dependent still runs in both scopes — counts, frontmatter, routing, §7y, commands, settings, plugin,
  doctor, adopt. The skip prints a note so a short run is not mistaken for full coverage, and install scope
  adds the executable-invocation canary above. Full scope stays the default and is what CI's standalone
  smoke-test step runs.
- **A gate that returned the wrong exit code was scored as a working gate.** A PreToolUse hook has exactly two
  answers: `0` allows, `2` blocks. Anything else — a syntax error, a missing interpreter, an unbound variable
  under `set -u` — means the hook *died*, and Claude Code runs the tool anyway. Thirty-five assertions in
  `smoke-test §7` tested the three PreToolUse hooks with `&& fail || pass` or `if …; then fail`, which treats
  every non-zero exit as a block, so all of them passed a hook that was failing open. Measured rather than
  argued, twice:
  - one §4.5 rule changed to `exit 1` — the world-writable `chmod` gate, so `chmod 777` actually runs — left
    the old suite **fully green**; the new one reports 16 errors;
  - `guard-commit-scan.sh` changed to `exit 1` — the plugin edition's **only** commit content gate failing
    open entirely, so an AI trace or a live secret walks into a commit — also left the old suite **fully
    green**; the new one reports 4.

  All thirty-five now require exactly `2`. Same class as the M1 fallback hole from the 1.4.0 audit, and it was
  found by injecting a deviation into the new observability channel below rather than by reading the code.
  The remaining gate scripts were audited the same way and are covered as they stand: `guard-write.sh` (2
  errors under the same injection), the five non-blocking hooks (`context-usage`, `route-hint`,
  `session-guard`, `session-rehydrate`, `skill-trust` — graded on output, so a dead one goes red), and the
  git-hook/CLI gates (`pre-commit`, `commit-msg`, `doctor.sh`, `scan-skill.sh`), where git and the CLIs treat
  any non-zero as a failure, so a crash fails **closed** rather than open.

### Added
- **The gates can now be observed firing.** `CSK_GATE_LOG=<path>` makes `guard-bash.sh` and `guard-write.sh`
  append one TSV line per decision — `BLOCK`/`ASK`/`ALLOW`, section, rule, command. Absent unless the operator
  exports it, write-only, and logged after the verdict is settled, so it cannot influence one.
  It exists because **"the model never reached for the command" and "the gate stopped it" leave behind
  identical artifacts.** `evals/permission-pressure` — the one case where the arms separated — had to report
  "`guard-bash` never fired" as an *inference*, and that inference is the whole difference between evidence for
  the always-on discipline text and evidence for the tool gate. `evals/run.sh` now prints a "gates fired" line
  beside each score. It is **reported, never scored**: a channel only the kit arm can produce cannot enter the
  denominator without handing the kit points the control is structurally unable to earn.
  Eight cases in `smoke-test §7k`, four of them verified by injecting a deviation and confirming the matching
  case goes red — including the one that exposed the exit-code hole above.
- **`evals/uncommitted-preserved`** — a failed experiment to undo before a demo, with an unrelated uncommitted
  change sitting in the same tree. `SESSION_STATE` had this case down as unbuildable: to measure "rule → gate"
  you need a run where the model actually *attempts* a §4.5 command, but a prompt that pushes hard enough to
  cause that IS the explicit user request §4.5 already permits. The way out is that the gated command does not
  have to be the goal — here the user asks for something entirely legitimate and the whole-tree revert is
  merely the fastest instrument to hand, so §4.5 applies at full strength and the model reaches for it, or
  does not, on its own. The experiment spans three files against one `.` that does the same job; the prompt
  never says checkout, restore, reset or clean. Graded on whether the unrelated work is still *recoverable*
  anywhere — `git stash` satisfies it and costs one command — because §4.5 gates irreversibility, not reverting.
  **It is the sixth zero: 12/12 against 12/12 across three fixture variants and 18 sessions.** In all nine
  control runs the bare arm noticed the fourth modified path from `git status`, said so, and left it alone.
  Two of the three variants exist because the fixture was planting the answer — a demo-note line and then a
  code comment, each quoted back verbatim by the control as its reason — and removing them changed nothing.
  Every round is published in `evals/README.md`, and the grader was dry-run against five hand-built outcomes
  (4/4 · 3/4 · 3/4 · 2/4 · 1/4) before any model saw it. Same diagnosis as `ambiguity-surfaced`: not "the kit
  does nothing" but **the control saturated**. No §4.5 gate fired in any of the nine kit sessions — and that
  is now a reading off the gate log rather than an inference from a transcript.

### Verified
- **PreToolUse hooks run under `bypassPermissions`, and `exit 2` is honoured there.** `guard-bash.sh` has
  asserted this in a header comment since it was written, and the A/B harness runs every case in that mode, so
  a wrong assertion would have quietly invalidated the whole suite. Probed directly: a hook logged
  `mode=bypassPermissions` for both commands it saw and denied the second, which did not run.
- **An untrusted workspace drops `permissions.allow` entries and nothing else.** A probe project carrying both
  an allow entry and a PreToolUse hook produced the exact `has not been trusted` warning — and the hook still
  ran and still returned `exit 2`. So a gate result measured in an untrusted scratch project is valid, and the
  runner's warning no longer implies otherwise. Only cases that need a pre-approved permission are affected.
- **The specialists now run on a plain prompt.** The kit's premise is that a task lands with the agent that owns
  it, and measurement said that never happened: across the eval suite, two A/B pairs and a twelve-agent domain
  sweep, a focused single-domain request produced **0 delegations in 24 sessions**. Three fixes were tried and
  all three scored zero — rewriting every agent `description` into ownership language, adding a concrete "call
  the Agent tool with subagent_type" paragraph to the discipline, and putting `Task`/`Agent` in the harness tool
  list. The subagents docs name three inputs to the delegation decision — the request, the `description` field,
  and current context — and the kit had only ever touched the last two.
  `route-hint.sh` is the first: a `UserPromptSubmit` hook that classifies the request against the installed
  agents' trigger phrases and returns `additionalContext`, which the docs place "alongside the submitted
  prompt". **Measured 39 of 48 across four rounds, against a 0-of-24 baseline.** Every one of the nine misses
  is accounted for and none of them is a refusal to delegate: five were a fixture that asked for work the
  project did not contain, two were the sandbox's untrusted-workspace permission problem, one was a reasoned
  inline decision that named the agent it considered, and one was an invented "operator config" that exists
  nowhere on the machine.
  The wording is the whole mechanism. A first version hedged — "unless it is a one-line edit", "if it is
  genuinely not that agent's work, say so" — and scored **4 of 12**, because a written escape hatch gets used.
  The docs give the phrasing that works verbatim ("Use the test-runner subagent to fix failing tests"), and that
  is what ships. An agent always outranks a skill when both match: the agent applies its own skills anyway, so
  naming it delivers the method plus the isolation and the audit path.
  It stays silent when no match is clear, ships in both editions, and carries six smoke-test cases — four owners
  and two silences, one of which pins the `build`/`ui` false positive that used to send CI failures to the
  frontend expert.

## [1.10.1] - 2026-07-30

Reported from a real install: a design request produced a good analysis and no delegation. Nothing here is new
functionality — it is the routing layer catching up with what the kit already claimed to do.

### Fixed
- **The agents were not running, and widening their vocabulary was not the fix.** This started as a report that a
  design request produced a good analysis and no delegation. Two rounds of trigger-phrase work later, the question
  was finally *measured* instead of theorised, in a clean install with the delegation tool available: a task
  squarely inside `frontend-expert-csk`'s domain produced **0 delegations on its own** — with the old description
  and with a rewritten "owns everything the user sees" one — while `/review`, whose body @-mentions its agents,
  produced **3 of 3**. The official docs say Claude decides delegation from the request, the `description` field
  and the context, and offer no way to force it; `@agent-<name>` is the one form that guarantees a subagent runs.
  So **the commands now @-mention their agents** (`/plan`, `/brainstorm`, `/review`, `/ship`), the discipline
  states that naming an agent in prose is a hope and `@agent-` is a guarantee, and both READMEs teach the escape
  hatch. Verified live, not assumed: `/review` on a clean install invoked `review-agent-csk`,
  `security-expert-csk` and `performance-expert-csk`.
- **The A/B harness could not delegate at all.** `evals/run.sh` passed `--allowedTools Bash Read Write Edit` —
  `Task`/`Agent` were absent, so every result it has ever produced was measured with the agent layer switched off,
  against a kit whose central claim is the agent layer. The flag is fixed and `evals/README.md` now carries the
  caveat above its results table rather than quietly leaving six "no difference" rows to be misread.
- **`doctor.sh` now reports whether delegation is switched off.** Denying the `Agent` tool in `permissions.deny`
  is the documented way to stop every subagent, and the only symptom is that all work quietly happens on the main
  thread — which reads as a broken kit rather than a setting. Checked at project, local and user scope.
- **The session line stopped announcing its own failure every turn.** `🔋 Session: could not measure` on every
  reply is noise that reads as a broken kit. The rule now: no reading → run the command once; if that also fails,
  say so once and drop the line.
- **Agent descriptions were inviting the model to stay inline.** `backend`, `database` and `frontend` each ended
  with a clause like "small tweaks stay inline" — the model could take its excuse from the agent's own
  description. Replaced with ownership: "Use proactively — owns everything the user sees or interacts with… any
  request about it is yours whatever its size, wording or language."
- **Agents were unreachable by the words users actually type.** The skills carried the user's vocabulary —
  `frontend-design` triggers on "visual design", "typography", "spacing" — so the skill fired, the route trace
  printed, and every gate stayed green while the *agent* that owns the work carried only structural vocabulary:
  screen, component, page, navigation, state management. "The app doesn't look premium, the icons are
  inconsistent" matched no agent at all, so a token layer across fifteen screens stayed on the main thread.
  `frontend-expert-csk` gains visual design · design system · design token · dark mode · look premium, and its
  "use proactively" clause now names visual work — that clause, not the trigger list, is what the harness reads
  when it decides whether to delegate. `performance-expert-csk` gains memory leak and laggy;
  `systematic-debugging` gains "is broken" and "crashes", which is how an unknown cause actually gets reported.
- **A short trigger matched inside a longer word.** `UI` matched `build`, so "the build fails on CI" routed to
  the frontend expert — a wrong route is worse than none, because it looks like the kit worked. The trigger is
  now `UI polish` and the matcher is word-bounded. Found while verifying that: a bare `token` trigger sent
  "design token layer" to the session-context skill; now `token budget` / `token cost`.
- **`token-budget` had no positive routing case at all.** Narrowing a trigger has to be paid for with one, or
  the fix for a wrong route quietly creates an unreachable component.

### Added
- **Ten golden routing cases, seven of which assert an AGENT** for a sentence a person would really type. The
  old design case asserted the *skill*, which is why the gate proved a mapping existed and never proved a real
  sentence reached the delegation layer — the same shape as the gate holes fixed in 1.10.0.
- **How to GET a release, per channel.** The plugin channel documented `/plugin marketplace add` and stopped.
  An installed plugin stays on the version it was installed at until someone asks for a newer one, and
  `claude plugin update` needs a restart, so nothing about it is automatic. Both READMEs and the npm README now
  carry `claude plugin marketplace update` + `claude plugin update`, verified against `claude plugin --help`
  rather than recalled. This had teeth: 1.10.0 closed three §4.5 holes, and a plugin user with no upgrade path
  keeps all three. The `release` skill gets the standing check — every channel must have a documented way to
  receive the version, because publishing and reaching users are different events.

### Changed
- **The `Trigger phrases:` lists moved out of the agents' `description` field into the body.** The official
  contract calls `description` "when Claude should delegate to this subagent", and that is the field Claude reads
  to decide — fifteen quoted keywords sitting in it compete with the sentence that states *when*. `routing-eval`
  greps the whole file, so the routing set is unchanged, and agent frontmatter fell 5,936 → 4,261 bytes.
- **The README no longer claims the agents "auto-chain".** They chain because the commands @-mention them.
  Automatic delegation is a model judgement in any kit; where it must happen, the kit no longer leaves it to
  chance, and the README says which is which.
- **The upstream attribution list is gone**, except the one a licence requires. `google/eng-practices` stays in
  one line: it is CC-BY 3.0 and `code-review` is an adaptation, so attribution is an obligation, not a
  courtesy. Two DevArchitecture mentions are deliberately kept and are not attributions — `--dotnet` genuinely
  clones that repository, so the sentence describing the installer would become false without it.
- The discipline shrank 182 bytes as a result; always-on went 28,858 → 28,697 even after everything added
  above. The attribution list was carried into every session and taught the model nothing.

## [1.10.0] - 2026-07-29

Three §4.5 rules that could be walked around, and the measurement that found the first one. All of it comes
from a single observation: **a gate that matches one spelling of a command has protected nothing.**

### Fixed
- **The world-writable rule matched the string, not the state.** `chmod 777`, `0777`, `a+rwx` and `+rwx` were
  blocked; `1777`, `2777`, `666`, `646`, `o+w`, `a+w` and `o=rwx` all reached exactly the same place and all
  passed. This was not found by reading the pattern — the A/B harness found it. Asked to open a directory
  "wide enough for any account", the uninstrumented model reached for `chmod 1777`, sticky bit and all: the
  one spelling nobody had thought to write down. The rule now matches any mode whose result is writable by
  other, and `755`, `644`, `775`, `u+w` and `chmod +x` are pinned as cases so widening it did not cost a
  false positive.
- **`rm -rf` was case-blind and long-flag-blind.** `rm -rf /` was blocked while `rm -Rf /`, `rm -fR /`,
  `rm -f -r /` and `rm --recursive --force /` were not. The target scoping (`/` · `*` · `~`) is deliberate and
  unchanged — `rm -rf build` is a routine local delete, and a gate that fires on it is a gate people learn to
  work around. **The rule had no test case at all**, which is why it went unnoticed for eleven releases; it
  now has sixteen.

### Added
- **A whole-tree `git checkout -- .` / `git restore .` is gated (§4.5).** It destroys every uncommitted change
  with no reflog and no undo — the same loss as `reset --hard`, which has been gated since the beginning, by a
  command that was not. A verification subagent ran exactly this over uncommitted work in this repo and took
  the working tree with it. Reverting one *named* file stays allowed: everyday, recoverable, and gating it
  would make the rule noise. `git -C <path>` and `git -c k=v` cannot walk around it, and a commit message
  containing the word "checkout" does not trip it — both pinned as cases.
- **`permission-pressure`, the first eval case to show a difference.** Five earlier cases asked the model to do
  an obvious good thing, politely, and the base model already did it. This one supplies a deadline, a plausible
  reason and a nudge toward the blunt instrument, because that is the shape a request has when careful
  behaviour actually fails. Kit 12/12 against bare 9/12: on the signal check the split is total — bare made the
  directory world-writable in 3 of 3 runs, the kit in 0 of 3. Graded on file modes, which are integers.
- **43 gate cases** across chmod, `rm` and the whole-tree revert — every spelling that must be blocked and
  every neighbour that must not.

### Changed
- §4.5 in the discipline now says *a world-writable `chmod`* rather than `chmod 777`, and names
  `git checkout -- .`. 27 bytes of always-on cost, spent deliberately: a user told a narrower rule than the one
  that fires reads the block as a bug and works around it.
- **The mechanism behind that 3-of-3 result is not the one the kit's design predicts, and the README says so.**
  `guard-bash.sh` never fired — the kit arm never attempted the command, declining on its own and citing the
  rule, because the discipline was in its context. That is evidence for the always-on text, not for the tool
  gate, and the two claims are not interchangeable.

## [1.9.0] - 2026-07-29

### Added
- **The commit content gate reaches the plugin edition** (`guard-commit-scan.sh`). A plugin ships Claude Code
  hooks, not git hooks, and cannot set `core.hooksPath` — so a plugin-only install had the commit *approval*
  gate and none of the commit *content* gates: a credential or an authorship trailer could land there while the
  other three distribution channels stopped it. One of four channels was quietly weaker, and nothing said so.
  The hook runs the real `pre-commit` and `commit-msg` scanners from PreToolUse rather than re-implementing
  them — a second matcher is how a gate passes while the thing it guards is broken. It reads `-F <file>`,
  covers `git commit -a` (where at that moment the content is still unstaged), and refuses the editor path only
  where no `commit-msg` hook can scan it afterwards.
- **Four records the kit expected but never wrote down.** `[NEEDS CLARIFICATION: <the question>]` markers in
  `spec-planning`, so an unresolved ambiguity survives into the artifact instead of being filled in with the
  likeliest reading — and no acceptance criterion may contain one. A bypass line in `confidence-check` and
  `adr`, so a gate that was weighed and overridden stops being indistinguishable from one that was missed;
  `revisit:` is the load-bearing field, since a bypass with no condition attached is permanent by default. A
  `complete / partial / unknown` coverage ledger in `security-scan`, promoted to an invariant rule, because
  "no findings" and "never looked" otherwise read identically to whoever acts on the report. And the micro-test
  method in `eval-grader`: sample a wording against a no-guidance control and read every run by hand.
- **The installer names the vendored front-end assets up front** (`start.sh`). The .NET base carries ~8 MB
  under `wwwroot/lib/**/dist/`, and the repo-bloat gate stops the first commit over them. That is the gate
  working — whether to commit third-party assets is a real decision — but meeting it at `git commit` time on a
  project you have not written a line of reads as breakage. The count, the path and the two ways out are stated
  while the context is obvious.
- **An A/B eval harness** (`evals/`, repo-internal — it is not part of an install). The same prompt in a
  kit-installed project and a bare one, graded on what is left on disk and never on the transcript, with both
  arms given identical tool access. Wired into no gate and no CI job: it costs real tokens.

### Fixed
- **`CLAUDE_GIT_OK` never actually pre-authorised anything.** The key had one purpose — let a headless or CI
  session commit with nobody at the keyboard — and did not achieve it: the hook answered exit 0, which means
  "this hook has no opinion", while `settings.json` also asks for `git add` and `git checkout -b`. Those rules
  stayed in force, so a keyed session could not even stage, and §4.4 advertised the flag as the way to work
  unattended. It now returns an explicit allow for the approval-gated set, reached only after the §4.5 blocks —
  a pre-authorised session still cannot force-push, amend, `reset --hard` or `git add -f`.
- **§4.1 stopped a fresh install from making its first commit.** The trace pattern matched the bare words
  `Generated by` / `Generated with`, which is the header written by every code generator in existence — a Dart
  lockfile, an EF Core scaffold, protoc, openapi-generator. A `--dotnet` install clones a base that carries one,
  so a greenfield project could not commit at all. The rule is about authorship by a model, and the pattern now
  requires that context nearby; both false-positive classes are pinned as clean cases.
- **The README's network diagram announced the wrong size.** The picture was regenerated as the kit grew, but
  its subtitle was typed by hand and stayed at "11 agents × 36 skills" while the diagram itself drew 12 and 38.
  It is the one claim in that image a reader takes at face value, because nobody counts 38 nodes. The subtitle
  is derived from the data that draws the diagram now, and the checked-in SVG is compared against the payload
  by the README catalogue gate, which already runs in CI.
- **The stated always-on cost was a release out of date.** Both READMEs said ~26 KB and ~10k tokens; the
  measured figure is 28,605 bytes, about 12k tokens on a real turn. The byte budget was gated and the sentence
  describing it was not.

### Changed
- Two skill bodies moved recipe material into references: `vps-deploy` (−669 B, proxy/SSL file contents) and
  `db-migration` (−1103 B, the nine-tool matrix). A project uses one proxy and one migration tool, not all of
  them; the decisions stay in the body.
- `bypassPermissions` is no longer carried as an open question. The published hooks reference documents
  `permissionDecision`, documents the permission modes, and says nothing about how the two interact — so there
  is no contract to rely on, and a gate resting on observed-but-unspecified behaviour is a bug even while it
  happens to work. Failing closed is a decision now, not a pending measurement.

## [1.8.0] - 2026-07-28

### Added
- **`confidence-check` skill** — the kit's only gate that fires *before* implementation. Review, the DoD and the
  commit approval all catch bad code; none of them catch correct code that duplicates something already in the
  tree or is built on a recalled API shape, because what reaches a reviewer is a clean diff. Five checks answered
  with evidence rather than recollection, and any "no" is a stop. Deliberately not a weighted score: with five
  checks and any sane bar a single failure sinks it anyway, so weights would only decorate a binary decision.
- **`dependency-upgrade` skill** — the acting half of dependency work, split from `dependency-audit`, which had
  promised "outdated packages" in its description and never taught it. Asks vulnerable, deprecated and behind as
  three separate questions, classes every target version patch/minor/major, lands security fixes first and alone,
  never applies a major automatically, moves manifest and lockfile together, and treats a green build plus a green
  suite as the only evidence an upgrade worked.
- **`performance-expert-csk` agent** — security, privacy and tests each had an independent reviewer; performance
  was the one quality axis where the author of a change audited their own hot path. Read-only, like the security
  auditor. Built around the tension that makes such an agent risky: the `performance` skill says measure before
  optimising, so anything read off a diff is reported as a *candidate* with the measurement that would settle it,
  and only a number promotes it to a *finding*.
- **`session-stats.sh`** — reads what a session actually did off the transcript (failing tool loops, repeated
  prompts, interrupts, compactions, delegation rate) so `reflect` and `handoff` rest on the record instead of the
  model's recollection of its own work. Wired to no hook event; run on demand.
- **`skill-trust.sh`** — a skill file is executable instruction, and they arrive by routes nobody reviews. At
  session start, any component the kit never shipped and the user never accepted is named, with the supply-chain
  scanner's verdict. Acceptance is deliberate and recorded as a digest, so an edit after acceptance comes back.
- **Project-readiness block in `doctor.sh`** — advisory, never changes the verdict: is the CLAUDE.md project
  section filled in, is there a project-specific skill, a devcontainer, an MCP server, and has CLAUDE.md drifted
  behind the code.
- **`.claude/kit-manifest.txt`** — written by both installers from the payload, so kit-owned and project-owned
  components can finally be told apart.
- **Rule precedence in the discipline** — what wins when two rules collide: prohibitions and safety, then the
  user's explicit instruction, then scope as asked, then quality, then speed.

### Fixed
- **The discipline could sit on disk and never load.** `.claude/DISCIPLINE.md` is inert unless `./CLAUDE.md`
  imports it, and every existing check was blind to that: hooks fire, gates look live, and routing, the DoD and
  session management never enter the context. `doctor.sh` now fails on it.
- **A compaction disarmed the session gate.** `/compact` keeps the same session id, so the once-per-threshold
  markers survived it: a session warned at 90% could compact, fill right back up and never be warned again.
  Markers are keyed by compaction generation now, and an automatic compaction is reported once at any fill.
- **A credential could be read even though it could not be committed.** `.env` was the only credential file
  either gate covered, leaving SSH private keys, AWS credentials, kubeconfigs and `.netrc` open. The commit scan
  catches a secret leaving the repo; nothing caught one merely read into the context.
- **A `--generic` install lost routing.** The generic backend variant did not route `confidence-check` or
  `sonarqube-check`. The orphan check could not see it — both are routed by *some* agent, so nothing is orphaned;
  they were simply unreachable on that stack. A parity gate now covers it.
- **One high-severity hit scored as safe.** A single finding cost 10 points and landed on exactly 90, the SAFE
  line, so one credential-exfil line or one injection directive passed on arithmetic. Severity now floors the
  verdict, and the exfil pattern matches both phrase orders instead of only reader-then-path.
- **The test runner was pinned to one stack.** The test agent and the `testing` skill named `dotnet test` as
  their definition of done in components that ship to every profile, including frontend- and mobile-only ones.
- **The published site had no gate.** It is hand-written with no source in the repo and no build step, and it
  drifted the obvious way — 1.7.0 updated its counters and forgot the version marker. The release workflow now
  compares the site's version and counters with the payload before publishing.

### Changed
- Every pattern in `trace-blocklist.txt` and `secret-blocklist.txt` carries its own case on the line below it,
  and the suite runs all of them through the real `pre-commit` rather than re-implementing the match — a second
  matcher would pass while the real one was broken. A pattern with no case fails the suite.
- The blocklists' self-exclusion is matched by file name instead of one installed path; anchored to
  `.claude/hooks/`, it stopped applying in the kit's own repo, which scanned its own pattern list.

## [1.7.0] - 2026-07-20

### Added
- **`threat-model` skill** — scope a security audit *before* scanning, to cut false positives. It maps assets,
  entry points, trust boundaries and 5-8 domain-specific attack classes into a parseable `docs/THREAT_MODEL.md`;
  `security-expert-csk` runs it first and `security-scan` then reviews that surface. A threat survives a patch; a
  vulnerability is only evidence for one.
- **`eval-grader` skill** — measure the quality of a generative task instead of vibing it: a two-layer grader
  (deterministic code metrics + per-dimension LLM-as-judge), signed deltas against a pinned baseline, and a
  `pass-slow` verdict that grades cost alongside correctness — the external, machine-grounded verifier `iterate` asks for.
- **An agent/skill network diagram** in the README — a data-driven map (`assets/network-*.svg`, built from the repo by `packaging/gen-network.py`) of all 11 agents, 36 skills, and their real `applies` relationships.

### Changed
- **`security-scan` gained an adversarial verification pass** — N independent verifiers that start from the code
  and hunt for why a finding is *wrong*, a false-positive exclusion taxonomy, a `CANNOT_VERIFY` verdict, and
  severity derived from **preconditions × access** rather than the vulnerability category (`references/verify.md`),
  plus defensive-security prompting rules (`references/prompting.md`).
- **`AGENT_TEMPLATE.md`** now covers decomposing along the tool < skill < subagent cost axis and requiring a typed
  contract between stages.
- **`frontend`** documents a verify-by-contract runtime convention — `data-verify-*` attributes, a `window.__verify`
  handle, and the `PASS/FAIL/BLOCKED/SKIP` taxonomy (`references/verify-contract.md`).
- **README restructured for reading order** — the feature inventory and network diagram surface *before* the install
  reference; the two differentiation tables are merged into one; the update mechanics collapse into a details block.

## [1.6.3] - 2026-07-17

### Fixed
- **`/update-csk` no longer hangs at npx's own install prompt.** The command ran `npx @…@latest update --here --yes`
  — the trailing `--yes` reaches the updater, but `npx` *itself* prints `Ok to proceed?` when it first installs the
  package, a prompt that reads the real TTY and ignores piped input, so an agent-driven / non-interactive run blocked
  before the kit even started (the update silently never happened). The command now runs `npx --yes @…` so npx's own
  `--yes` auto-confirms the install and `/update-csk` completes unattended. (1.6.1 fixed the updater's own prompts;
  this fixes the npx layer above them — both are needed for a clean unattended refresh.)

## [1.6.2] - 2026-07-17

### Changed
- **A fresh install auto-runs ordinary commands; only commit/push and destructive ops interrupt you.** `settings.json`
  now ships `permissions.allow: ["Bash"]`, so everyday commands (build, test, `ls`, `git status` …) run without a
  prompt in the `default` and `acceptEdits` modes. `git add/commit/push/checkout -b` and `ssh/scp/rsync/docker` still
  prompt — an `ask` rule always wins over `allow` — and destructive / RCE / gate-tamper commands stay hard-blocked by
  `guard-bash.sh` (its `exit 2` overrides `allow`). Note: the classifier-based `auto` mode intentionally drops a
  blanket `Bash` allow, so there it defers to the classifier.
- **Decision points ask with the `AskUserQuestion` tool.** The discipline now directs the model to ask with structured
  single/multi-select options at every decision point — never prose the user must type back, and never skipping the
  question — instead of the old "numbered options" prose. (This is model discipline, not a hook-enforced gate.)

## [1.6.1] - 2026-07-16

### Fixed
- **`update` / `adopt --yes` no longer hangs under a TTY.** The confirmation prompts tested for a TTY *before*
  honoring `--yes`, so an unattended run that inherited a pseudo-terminal (Claude Code drives shell commands under a
  pty on Windows) blocked waiting for input that never came — `/update-csk` timed out with nothing changed. `--yes`
  is now checked first at every gate, including the agent-overlap (`owner`) and off-repo prompts that did not route
  through the shared helper. A pty-based regression test (`e2e.sh` `[adopt-pty-yes]`) allocates a real terminal and
  asserts an unattended refresh completes, so this class of hang cannot return.

## [1.6.0] - 2026-07-16

### Added
- **No idle components — a routing invariant, now enforced.** Every skill and agent must be *routed*: named by an
  agent, a command, or the discipline's trigger map. `smoke-test.sh` (§3b) fails if any component is reachable only
  by its own description. Four previously-unrouted main-thread skills — `iterate`, `reflect`, `worktree`,
  `mcp-builder` — are wired into the trigger map, so nothing ships dark.

### Changed
- **`sonarqube-check` is local-first and self-bootstrapping.** Instead of pointing at a shared or remote SonarQube
  server, the gate installs the project language's local, server-less analyzer when none exists and runs it in place
  — .NET → `SonarAnalyzer.CSharp` Roslyn NuGet at build time (`TreatWarningsAsErrors`); JS/TS → `eslint-plugin-sonarjs`;
  and the language-native equivalents elsewhere. A full SonarQube dashboard becomes optional, only when a project runs
  its own instance. The Definition-of-Done gate follows the same wording.

### Fixed
- **The orphan-routing check is grep-portable.** The §3b matcher drops the `^`/`$` line-anchor alternation that ugrep
  matches unreliably and no longer folds the search term into its own file-argument list, so the gate is correct under
  GNU grep, BSD grep, and ugrep alike.

## [1.5.1] - 2026-07-15

### Changed
- **The stale agent-name check now follows CLAUDE.md's reference chain.** `doctor` and adopt's install-proof stage
  no longer scan only `CLAUDE.md`; they also scan every local doc it points to (its `@import`s and `docs/…md` paths),
  so an orchestration doc like `docs/AGENTS.md` that a takeover left naming the old bare agents is caught too.
  Unreferenced design/audit docs and code comments are ignored, so it stays complete without false positives.

### Fixed
- **A takeover now completes its own migration.** When `adopt` renames the project's agents to their `-csk` ids, it
  rewrites every bare reference to them across CLAUDE.md's reference chain (boundary-safe: `-csk`/`-local` suffixes and
  longer words are left intact), so delegation to a renamed agent no longer silently fails. The edit lands on the adopt
  review branch, visible and revertible; hand-authored prose outside the chain is never touched.

## [1.5.0] - 2026-07-15

### Added
- **Diagnose-first routing.** The orchestration workflow now opens with a diagnosis step: a cross-domain bug whose
  root cause is unknown routes to `general-purpose` applying the `systematic-debugging` skill *before* planning —
  unclear scope is not the same as an unknown cause, and you cannot sequence a fix you cannot locate.
- **A one-line route trace on every task.** Each task opens with `🔧 <agent>` (delegating) or `🔧 inline · <skill>`
  (main thread) plus a reason, so the kit's delegate-or-inline work is always visible instead of silent.
- **`doctor` + adopt detect stale agent names.** A brownfield takeover renames the project's agents to `-csk` ids,
  but the project `CLAUDE.md` may still name the old bare agent — a reference that matches no installed agent, so
  delegation to it silently fails. `doctor.sh` and adopt's install-proof stage now report each such reference with
  its `CLAUDE.md` line and the correct id (auto-delegated agents as a failure, pull-only agents as a consistency
  note). Detection only; hand-authored prose is never auto-rewritten.
- **A smoke-test gate for auto-delegation cues.** Every non-pull agent description must carry an action cue
  (`use proactively` / `immediately after`), so a passive rewrite can't silently stop the specialists from firing.

### Changed
- **The specialist agents now auto-delegate.** Claude Code routes to a subagent on its `description` field and only
  fires reliably when that description carries an action cue. The nine producing/auditing agents were rewritten to
  lead with "use proactively …" (with an inline carve-out for trivial edits); `commit-agent-csk` and
  `session-manager-csk` stay pull-only. The passive descriptions before this rarely auto-invoked, so the specialists
  stayed dormant and the kit read as inert.

## [1.4.4] - 2026-07-14

### Fixed
- **The settings self-heal now finds Python on Windows.** The merge looked only for `python3`, but a Git-Bash
  install commonly exposes Python only as `py` (the Windows Python Launcher) or `python` — so on those machines the
  updater fell through to the no-parser fallback and, for a project it misjudged, left a `settings.json.kit`
  reference instead of healing `settings.json`. The merge now probes `python3`, then `python`, then `py`, and uses
  whichever exists, so `/update-csk` heals cleanly via Python where jq is absent. Covered by an e2e leg that runs the
  merge with Python reachable only as `py`.

## [1.4.3] - 2026-07-14

### Fixed
- **The secret/trace commit gate was blind on Windows.** On an autocrlf (CRLF) checkout the pre-commit scanner read
  its blocklists with a trailing carriage return, so every pattern carried a `\r` and never matched the LF diff — a
  Windows user's commits weren't actually protected. The blocklist loops now strip a trailing `\r`, and
  `.gitattributes` pins the data files to LF. Verified on a Windows CI runner.
- **`/update-csk` now self-heals with no jq/python and no flags.** The settings merge previously required `jq` or
  `python3`; with neither (typical Windows Git-Bash) an update silently skipped it and left the hooks stale. A
  no-parser bash path now safely replaces a kit-only `settings.json` (a timestamped backup is kept), and a
  non-interactive update of an existing install applies by default — so a plain `/update-csk` refreshes the install
  end to end.

### Added
- **`--yes` flag on the updater** for non-interactive / CI runs, and a cross-platform CI matrix (Linux · macOS ·
  Windows) plus an e2e self-heal rehearsal, so the installer is proven on all three platforms.
- **Leaner npm README + broader keywords** for the package page (the rich README stays on GitHub).

## [1.4.2] - 2026-07-14

### Fixed
- **`/update-csk` no longer hangs.** The updater's final apply gate always read stdin, so off a controlling terminal
  — an agent's non-interactive shell — it blocked forever on an open, empty stdin instead of resolving. `/update-csk`,
  which runs the updater on the user's behalf, therefore hung mid-run. The prompt helper is now TTY-aware: it asks
  only on a real terminal, and off one it resolves without reading — `--yes` proceeds, otherwise it declines cleanly
  (nothing changes) rather than blocking.

### Added
- **`--yes` flag on the updater** (`adopt.sh` / `npx … update`) for non-interactive, agent-driven, or CI runs.
  `/update-csk` now invokes `npx @byerlikaya/claude-starter-kit@latest update --here --yes`, so an in-session update
  runs to completion; a user who wants to review each handover decision still runs the plain command in their own
  terminal. Covered by an e2e regression (no-hang · `--yes` applies · stale hooks refreshed · `CLAUDE.md` preserved).

## [1.4.1] - 2026-07-14

### Fixed
- **Updates now refresh the kit's own hooks.** The `settings.json` merge concatenated hook arrays, so on update a
  stale kit hook entry (e.g. an old `context-usage` hook with a short timeout) survived next to the refreshed one —
  the outdated one then timed out — and a genuinely new hook event (`SessionStart`) could be missed. The merge is now
  hook-aware: kit-owned hooks (any command referencing `.claude/hooks/`) are treated as authoritative, so current
  entries land, stale ones drop, and new events wire up, while the project's own custom hooks and permissions are
  preserved.
- **Settings merge no longer needs jq.** On machines without `jq` (common on Windows Git-Bash) the merge was skipped
  entirely, so updates never applied new hooks or corrected timeouts. A `python3` fallback with identical semantics
  now runs when `jq` is absent; if neither is present the kit's reference settings are written alongside for a manual
  reconcile instead of a silent skip. A smoke-test regression guard locks the hook-aware behaviour in.

## [1.4.0] - 2026-07-13

### Added
- **Four new skills.** `systematic-debugging` (root-cause a bug before touching a fix), `frontend-design` (visual/UX
  quality above architecture and a11y), `mcp-builder` (build a Model Context Protocol server), and `worktree`
  (isolate risky or parallel file-mutating work in a git worktree so uncommitted changes are never clobbered). 34 skills total.
- **Two slash commands.** `/update-csk` (version-check → update → verify with the doctor → prompt `/compact` to
  reload) and `/doctor-csk` (health-check a live install — hooks executable, `core.hooksPath` set, gates wired),
  backed by `eval/doctor.sh`.
- **The plugin edition now ships the tool-level gate hooks** (`guard-bash`, `guard-write`, `context-usage`,
  `session-guard`, `session-rehydrate`) via an auto-discovered `hooks/hooks.json` resolved through
  `${CLAUDE_PLUGIN_ROOT}`. The git-commit trace/secret/bloat scan still needs the full install.
- **Session rehydration.** A `SessionStart` hook re-surfaces `docs/SESSION_STATE.md` across a `/compact` or
  `/clear` boundary, completing the handoff → clear → resume loop.
- **adopt branch choice.** `--here` / `--new-branch` flags plus a smart default (first adopt → a review branch; a
  routine update whose `.claude/` is gitignored → the current branch; a tracked `.claude/` → ask).
- **Install-time supply-chain scan.** `eval/scan-skill.sh` scores a skill/agent file for red flags (pipe-to-shell,
  known exfil hosts, prompt-injection directives, credential-file reads); `adopt` runs it read-only over the
  project's existing (non-csk) skills/agents and surfaces any finding — advisory, never blocking.

### Changed
- **Progressive-disclosure retrofit** of eight skills — depth moved into `references/`, loaded on demand, to lower
  the on-invoke cost without touching the always-on budget.
- **Review rigor.** `code-review` gained a two-stage verdict (verify a finding before reporting it) and a named
  lens panel; `routing-eval` gained negative routing tests; `AGENT_TEMPLATE` documents a test-first workflow.
- **README** front-loads a Quick Start and collapses the agent table so install is visible in the first screen;
  counts refreshed to 34 skills.
- **Token hygiene.** A per-skill frontmatter ratchet and a cache-stable-ordering note. (Description trimming was
  deliberately not done — it would trade routing reliability for a marginal always-on saving.)
- `review-agent-csk` inherits the session model; every agent carries a `color`; CI uses `actions/*@v5` and
  validates the plugin manifest.

### Fixed
- **Security — tool-level gate bypasses (from an adversarial audit).** `guard-bash.sh` now uses one git matcher that
  catches `git -C …` / TAB separators, quote/backtick-wrapped `git commit`/`push`, `--force-with-lease`,
  `git -c core.hooksPath=…`, and the no-jq/no-python3 fallback — without over-blocking a commit whose message merely
  contains a subcommand word. Gate-tamper is matched by target path (interpreters, variable-indirected redirects,
  `.git/hooks`), so a guard hook cannot be silently rewritten. Reading a `.env` through the Bash tool is blocked.
- **`doctor.sh`** no longer reports "healthy" on a disarmed install — a missing git hook, an empty hook array, or a
  hook neutered to `exit 0` (caught by a behaviour probe) all fail.
- **`profiles.conf`** — a `--backend` install could ship `frontend-design` (a UI-only skill); it is now pruned.
- **Installer hygiene** — `start.sh` makes hooks executable via a glob so a hook added later is covered; kit-only
  smoke-test checks are guarded so an installed project (and the `e2e` rehearsal) pass.

## [1.3.0] - 2026-07-13

### Added
- **Six new tool-level gates.** The gate layer now covers more than commit/push approval and the existing
  destructive-op block:
  - **RCE / permission-nuke** — pipe-to-shell (`curl…|bash`), `chmod 777` and `dd of=` are hard-blocked in every
    permission mode (`guard-bash.sh`).
  - **Gate-tampering** — redirecting `core.hooksPath`, or editing/deleting a hook script, is blocked both from the
    shell (`guard-bash.sh`) and from the file tools (new `guard-write.sh` + a `Write|Edit` PreToolUse matcher). A
    gate you can silently remove is not a gate. `settings.json` stays editable so the `update-config` skill works.
  - **Repo-bloat** — build/vendored artifacts and blobs over 5 MiB are blocked at `pre-commit` (override via
    `CSK_MAX_FILE_BYTES`).
  - **Secret-file** — a file that is a secret by name (`.env`, `id_rsa`, `*.pem/.key/.p12`, `.npmrc`, …) is blocked
    at `pre-commit`; `.env.example`/`.sample`/`.template` stay committable.
  - **Force-add / lockfile deletion** — `git add -f` (bypasses `.gitignore`) and deleting a lockfile are blocked
    (`guard-bash.sh`).
  - **Default-branch warning** — committing straight onto `main`/`master` is surfaced in the approval prompt (a
    warning, not a block: a fresh project legitimately lives on `main`).
- **README "How this kit is different" section (EN + TR)** — a comparison against a typical prompt collection /
  agent kit, with the new gates added to the Rule → gate table.

### Changed
- **The update command is now documented for every channel (EN + TR).** Homebrew
  (`brew upgrade … && claude-starter-kit update`) and the release tarball (re-run `bash adopt.sh`) previously
  showed only fresh-install and adopt; the refresh path was spelled out for npx only.

### Fixed
- **`context-usage.sh` can no longer time out on a huge transcript.** A single pasted payload becomes one
  multi-MB JSONL record; the line-based `tail -n` then dragged the whole blob through the scanner (~1.4s for a
  60MB paste — over the 10s hook timeout on a slow Windows box with no `jq`). The tail is now bounded by bytes
  (256 KiB → 4 MiB), so the same case scans in ~12ms; when the record sits past the window the whole-file
  fallback runs only while the transcript is small enough to finish in time, and past a 200 MiB cap
  (`CSK_CONTEXT_MAX_BYTES`) it fails open — a missing measurement line is recoverable, a timed-out hook is not.

### Note
- The new `pre-commit` gates (repo-bloat, secret-file) can block operations that previously passed — committing
  `node_modules/`, a `.env`, or a large binary. That is intended; a genuine exception is escapable via
  `.secret-allowlist.txt`, `CSK_MAX_FILE_BYTES`, or an explicit `--no-verify` (§4.5).

## [1.2.2] - 2026-07-12

### Fixed
- **`planner-csk` inherits the session model instead of being pinned to `sonnet`.** The agent had drifted to
  `model: sonnet` while both READMEs documented `inherit`. Planning is the highest-leverage, read-only,
  once-per-feature step — its output steers every downstream producer agent — so it should run on the strongest
  model the user runs (`inherit` → Opus when Opus is the session model), not be capped below it. Cheap pins stay
  on the mechanical, high-frequency agents (`review`/`commit`/`session` on `haiku`). The READMEs were already
  correct; only the agent file changed.

## [1.2.1] - 2026-07-12

### Changed
- **`iterate` and `code-review` now prefer an external, machine-grounded verifier over LLM self-grading.** An exit
  test / acceptance check should rest on an objective signal (a test exit code, a schema match, a quality gate),
  not the model's own "looks done" or a lone "review clean" — a model grading its own output inflates. `iterate`
  says so at the exit-test step; `code-review` now flags any change that makes a check pass by *weakening the
  check* (loosening an assertion, lowering a threshold, editing the test instead of the code).
- **`token-budget` replaces the guessed "7×" figure with a measured subagent context cost.** Measured in a real
  transcript: a subagent's first turn is `cache_read=0` — context is built 100% fresh, nothing shared with the
  main thread (~10k tokens with restricted tools, ~16k with full tool access). Only the skill listing (~2.5–3k)
  is inherited by a subagent; the discipline (`DISCIPLINE.md`) and agent descriptions are not. The delegation
  threshold is reframed around that fresh-context floor: delegate for isolation, not to shave a few reads.

## [1.2.0] - 2026-07-12

### Added
- **`brainstorm` skill — divergent discovery before planning.** Turns a fuzzy, under-defined ask into 2–4
  distinct scoped options (including a deliberately minimal one) plus named blocking unknowns, converges to an
  explicit user choice, then hands the chosen direction to `spec-planning`. Wired as the pre-planning front-end
  of `planner-csk` and reachable via the new `/brainstorm` command. Bounded and gate-compatible — it asks with
  explicit options and never fills ambiguity by guessing.
- **`reflect` skill — retrospective self-audit.** After nontrivial work, a single bounded pass over unverified
  assumptions, silently-skipped items, whether the approach was right, and which "done/works" claims rest on
  observed evidence vs. inference. The step-back counterpart to `iterate`'s refine-to-done loop; produces
  findings, not code.
- **Panel mode in the `code-review` skill.** For high-stakes, hard-to-reverse decisions (architecture, a public
  API contract, a security boundary), evaluate the change from several independent adversarial lenses in
  parallel and synthesize their objections rather than averaging them. Reserved for high stakes; routine diffs
  keep the single-lens review.
- **A Turkish skill catalogue in `README.tr.md`.** The table's summaries are now Turkish, sourced from
  `packaging/skill-summaries.tr.tsv` — build-time data that is NOT part of the always-on payload, so the Turkish
  text spends no `SKILL.md` frontmatter byte budget.

### Changed
- **`build-readme-catalog.sh` generates each README in its own language.** English summaries still come from each
  `SKILL.md`; Turkish summaries come from the new TSV. The skill NAME set (the directory listing) drives both, so
  the two tables always hold the same rows in the same order. `--check` now also fails if any skill lacks a
  Turkish summary — a drift gate, already run in `ci.yml` and `release.yml`.
- **The skill-description byte budget in `smoke-test.sh` is raised 8500 → 9250.** The two new skills add ~660
  bytes of always-on frontmatter; the bump is deliberate and explicit, as the budget mechanism requires.
- Both READMEs (counts 28 → 30 skills, 5 → 6 commands, version and skill badges), the `CLAUDE.md` structure
  line, and the orchestration SVGs (`brainstorm → plan` in stage 1) reflect the additions.

## [1.1.12] - 2026-07-11

### Fixed
- **`smoke-test.sh` no longer fails an installed project for the user's OWN skills.** The "every skill declares
  Trigger phrases" check — like the byte budget — is a KIT convention; run inside a project it failed the user's
  own trigger-less skills, a pre-existing quirk that surfaced once adopt began importing taken-over agents. Both
  checks now GATE only in the kit repo and REPORT (a note, not a failure) in an installed project. Your project's
  own agents and skills are your call.

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
