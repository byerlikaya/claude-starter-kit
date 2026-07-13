---
name: update-csk
description: Check for a newer kit version, update, report what changed, then prompt /compact to reload.
---
# /update-csk
Bring the installed kit up to the latest published version:
1. **Detect install type.** If `.claude/VERSION` exists → a full install (steps below). If the kit runs as a
   **plugin** (no `.claude/VERSION`), it updates through the plugin system — tell the user to run
   `claude plugin update claude-starter-kit` and stop here.
2. **Current version:** read `.claude/VERSION`.
3. **Latest version:** `npm view @byerlikaya/claude-starter-kit version` (needs network). If it can't be reached,
   say so and stop — don't guess.
4. **Compare.** Already on the latest → report "up to date (vX)" and stop. Otherwise show **old → new**.
5. **Update** — this rewrites the kit-owned files under `.claude/` (your `./CLAUDE.md` and project skills are
   preserved). **Show this plan first, then run:** `npx @byerlikaya/claude-starter-kit@latest update`.
6. **Verify:** run `/doctor-csk` (or `bash .claude/eval/doctor.sh`) so a bad/partial update surfaces immediately.
7. **Report** old → new + the headline changes (from the release notes / CHANGELOG).
8. **Reload (manual — a command can't do it itself):** the discipline in the running session is still the OLD one.
   Tell the user to run **`/compact`** (or `/clear`) so the updated `.claude/DISCIPLINE.md` is re-read in the same
   session — no restart needed.
