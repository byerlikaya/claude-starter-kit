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
# Windows hands both CLAUDE_PROJECT_DIR and the stdin `cwd` over as native paths (`C:\Repos\app`), and the stdin
# one arrives JSON-ENCODED on top of that — `C:\\Repos\\app`. Slicing it out with sed keeps the doubled
# backslashes, so ROOT pointed at a directory that cannot exist and the hook silently rehydrated nothing.
# Undo the JSON escaping first (`\\`), then fold any lone separator. Both are no-ops on a POSIX path.
ROOT="${ROOT//\\\\//}"; ROOT="${ROOT//\\//}"

STATE="$ROOT/docs/SESSION_STATE.md"
[ -s "$STATE" ] || exit 0   # no (non-empty) handover → nothing to rehydrate, stay silent

MSG="A session handover from before this context boundary exists at docs/SESSION_STATE.md. If the user's request continues that work, read it first — it holds the in-progress task state, open decisions, and the intended next step — and do not restart from scratch. If the request is about something else, do not bring it up."

# hookSpecificOutput.additionalContext is the documented channel that injects text into the model's context.
# ONE PATH, no jq: MSG is a fixed constant with no quote, backslash, control character or newline, so it needs no
# escaping and every machine emits the same bytes. If you ever make MSG dynamic, escape it the way board-sync.sh
# does (jq-identical, measured) — a raw quote or tab here makes JSON the CLI silently drops.
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$MSG"
exit 0
