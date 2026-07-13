#!/usr/bin/env bash
# SessionStart hook — after a context boundary (compact / clear / resume), point the model back at the handover
# so in-progress work survives the boundary. This closes the kit's handoff loop: `handoff` writes
# docs/SESSION_STATE.md → the user runs /clear (or context auto-compacts) → a fresh context starts → THIS hook
# re-surfaces the file so the next turn resumes from it instead of from zero.
#
# Deliberate scope (honest, spec-grounded):
#   - SessionStart is the right event: its stdout / hookSpecificOutput.additionalContext is injected into the
#     model's context (docs: "Re-inject context after compaction"). PreCompact is NOT used — it can only block
#     compaction, not add instructions to the summary, and blocking is not what we want.
#   - Matched on compact|clear|resume, NOT startup: those three are explicit "continue where I left off" boundaries.
#     startup fires on every unrelated session open and would keep surfacing a stale handover — that would nag.
#   - CLAUDE.md itself reloads on /compact and /clear on its own, so this hook does NOT re-inject the discipline —
#     only the session-specific state the reload can't recover.
#   - Fails OPEN and SILENT: no handover file, no output. It never blocks the session (always exits 0).
set -uo pipefail
IN="$(cat 2>/dev/null || true)"

# Project root: CLAUDE_PROJECT_DIR (set for hooks) → cwd from the stdin JSON → PWD.
ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(printf '%s' "$IN" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
[ -n "$ROOT" ] || ROOT="$PWD"

STATE="$ROOT/docs/SESSION_STATE.md"
[ -s "$STATE" ] || exit 0   # no (non-empty) handover → nothing to rehydrate, stay silent

MSG="A session handover from before this context boundary exists at docs/SESSION_STATE.md. Read it before continuing — it holds the in-progress task state, open decisions, and the intended next step. Do not restart the work from scratch."

# hookSpecificOutput.additionalContext is the documented channel that injects text into the model's context.
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
  "\"$MSG\""
exit 0
