---
name: doctor-csk
description: Health-check the installed kit — hooks executable, core.hooksPath set, gates wired.
---
# /doctor-csk
Verify the kit is actually *active* in this project (not just present on disk):
1. Run `bash .claude/eval/doctor.sh`.
2. Read its report. It checks: VERSION present · every hook executable · `core.hooksPath` points at `.claude/hooks`
   (else the §4.1/§4.2 commit trace + secret/bloat scan never runs) · `settings.json` valid and wiring the
   PreToolUse / UserPromptSubmit / Stop gates.
3. For each ❌, apply the printed fix. Anything that changes git config or file permissions needs approval first —
   show the exact command and wait.
4. Summarise: **healthy**, or the precise fixes applied/needed. If it's not a git repo, note that the commit-time
   gates need `git init` + `git config core.hooksPath .claude/hooks`.

If `.claude/eval/doctor.sh` doesn't exist, this is not a full (start.sh / adopt.sh) install — the kit is likely
running as a **plugin**, whose hooks are managed by Claude Code itself; there's nothing for the doctor to check.
