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
   preserved). **Show this plan first, then run:** `npx --yes @byerlikaya/claude-starter-kit@latest update --here --yes`.
   Two DIFFERENT `--yes` flags, both required for a non-interactive run: the one **before** the package name is
   **npx's own** — it auto-confirms npx's `Ok to proceed?` install prompt, which reads the real TTY and IGNORES piped
   input, so without it the command hangs before the kit even starts. The `--here --yes` **after** the package go to
   the updater (`--here` = apply on the current branch, `--yes` = accept the smart defaults). Together they let it run
   to completion instead of blocking on a prompt your shell can't answer.
   If you'd rather review each handover decision yourself, tell the user to run `npx @byerlikaya/claude-starter-kit@latest update`
   (no flags) in **their own terminal**, where both the npx and the interactive prompts work.
6. **Verify:** run `/doctor-csk` (or `bash .claude/eval/doctor.sh`) so a bad/partial update surfaces immediately.
7. **Report** old → new + the headline changes (from the release notes / CHANGELOG).
8. **Reload (manual — a command can't do it itself):** the discipline in the running session is still the OLD one.
   Tell the user to run **`/compact`** (or `/clear`) so the updated `.claude/DISCIPLINE.md` is re-read in the same
   session — no restart needed.
