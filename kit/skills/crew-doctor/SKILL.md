---
name: crew-doctor
description: Health-check the install — hooks executable, core.hooksPath set, gates wired, discipline loaded.
metadata:
  kind: command
---
# /crew-doctor
Verify Crewforth is actually *active* in this project (not just present on disk):
1. Run `bash .claude/eval/doctor.sh` (Bash tool, not PowerShell).
2. Read its report. It checks: VERSION present · every hook executable · the required git hooks (pre-commit,
   commit-msg) present · **guard-bash actually blocks a force-push** (catches a hook that is present but neutered) ·
   `core.hooksPath` points at `.claude/hooks` (else the §4.1/§4.2 commit trace + secret/bloat scan never runs) ·
   `settings.json` valid and wiring the PreToolUse / UserPromptSubmit / Stop gates to **non-empty** hook arrays
   (an empty `[]` wires nothing); SessionStart (rehydration) is reported as a warning if absent · **`./CLAUDE.md`
   actually imports `.claude/DISCIPLINE.md`** — without that line the discipline sits on disk and never loads, which
   every other check is blind to.
3. For each ❌, apply the printed fix. Anything that changes git config or file permissions needs approval first —
   show the exact command and wait.
4. Read the **Readiness** block too. It is advisory (never changes the verdict) and asks a different question — is
   this *project* set up to be worked on by agents: CLAUDE.md project section filled in · a project-specific skill
   alongside Crewforth's generic ones · a devcontainer to sandbox agent commands · an MCP server · CLAUDE.md not
   drifted behind the code. Report the gaps as suggestions, not as failures, and never "fix" them unasked — adding
   a devcontainer or an MCP server is the user's call.
5. Summarise: **healthy**, or the precise fixes applied/needed, plus the readiness score. If it's not a git repo,
   note that the commit-time gates need `git init` + `git config core.hooksPath .claude/hooks`.
   If the output contains a line starting with ⭐, pass it to the user verbatim as the LAST line of your summary —
   it prints once per Crewforth version, and it is meant for the user, not for you.

If `.claude/eval/doctor.sh` doesn't exist, this is not a full (start.sh / adopt.sh) install — Crewforth is likely
running as a **plugin**, whose hooks are managed by Claude Code itself; there's nothing for the doctor to check,
with one exception: the skill listing, which a plugin cannot size for itself (its settings cannot set
`skillListingBudgetFraction`). Count it the way the full install's doctor does:
`LC_ALL=C awk -f "${CLAUDE_PLUGIN_ROOT}/eval/lib/skill-listing.awk" "${CLAUDE_PLUGIN_ROOT}"/skills/*/SKILL.md`
(prints characters, then skills). At the default fraction a 200,000-token model has 8,000 characters for the whole
listing, and Claude Code's own skills take about 5,900 of them (measured on v2.1.282). If Crewforth's number plus
5,900 is over 8,000, tell the user plainly: on such a model the least-used skills lose their descriptions and are
less likely to be picked on their own; one line in `~/.claude/settings.json` fixes it — `"skillListingBudgetFraction": 0.04`; the cost is
that the listing is then sent whole every turn, about (that total ÷ 4) tokens, (tokens ÷ 2,000)% of a 200k window.
It is their call — show the line and the cost, do not edit their settings. On a 1,000,000-token model the default
already fits.

**The eval scripts are installer-only, by decision.** `eval/` — `doctor.sh`, `smoke-test.sh`, `routing-eval.sh`,
`scan-skill.sh`, `utilization.sh` — ships with `start.sh` and `adopt.sh` and NOT with the plugin edition. The eval
scripts are developer instruments: they inspect an installation from outside it, and the plugin edition has no
installation to inspect. Say this plainly when someone asks why `/crew-doctor` reports only the listing on a plugin install,
rather than treating it as a defect. The Studio panel ships in both editions (`/crew-studio`).
