#!/usr/bin/env bash
# Stop hook — when session fill crosses a threshold it GUARANTEES the handoff recommendation reaches the USER.
# Session management = a gate at the threshold, not a wish. But the gate must not nag or burn tokens:
#   - It surfaces the recommendation as a neutral `systemMessage` (user-facing warning), NOT a hook error.
#     (Claude Code renders a BLOCKING Stop hook — exit 2 — as "Stop hook error: ...". We deliberately never block.)
#   - It fires ONCE PER THRESHOLD per session: once at 75% (warn), once more at 90% (critical). Never every turn,
#     so it never forces an extra assistant continuation — which would burn tokens and fill the context faster,
#     i.e. the gate would cause the very thing it exists to prevent.
#   - It NEVER blocks the stop: every path exits 0. A measurement failure fails open, silently.
# context-usage.sh does the measurement. No automatic /clear — approval is the user's (§4.4).
# The model is nudged separately every turn by context-usage.sh (UserPromptSubmit); this hook is the
# guaranteed USER-facing alert. A new session (or /clear) mints a new session_id and re-arms both thresholds.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IN="$(cat 2>/dev/null || true)"

# Loop guard: if this Stop is already a Stop-hook continuation, do nothing (defensive; we never block anyway).
case "$IN" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

# Per-session dedup key: session_id from the Stop stdin JSON (documented field), else the transcript
# filename. Sanitized to a safe filename fragment. Without any key we fall back to a shared marker
# (that degenerate case coincides with a measurement failure, which exits silently below anyway).
TP="$(printf '%s' "$IN" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
KEY="$(printf '%s' "$IN" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | tr -cd 'A-Za-z0-9._-')"
[ -n "$KEY" ] || KEY="$(basename "$TP" 2>/dev/null | tr -cd 'A-Za-z0-9._-')"
[ -n "$KEY" ] || KEY="unknown"

# Compaction generation. A `/compact` does NOT mint a new session_id — only a new session or `/clear` does —
# so the per-tier markers below survive it, and that silently disarms this gate exactly where it matters most:
# a session warned at 90% compacts down to ~5%, climbs all the way back, and the user is never told a second
# time. Keying the markers by compaction COUNT gives every generation its own pair of thresholds.
# The boundary record is `"subtype":"compact_boundary"` with `compactMetadata.trigger` (verified against real
# transcripts). grep, not awk: this runs inside a hook timeout on every Stop, and the same size guard
# context-usage.sh uses applies — past the cap we skip the count and fall back to the old single-generation
# behaviour rather than risk the timeout.
COMP=0; AUTOC=0
if [ -n "$TP" ] && [ -f "$TP" ]; then
  SZ="$(wc -c < "$TP" 2>/dev/null | tr -cd '0-9')"; SZ="${SZ:-0}"
  if [ "$SZ" -le "${CSK_CONTEXT_MAX_BYTES:-209715200}" ]; then
    COMP="$(grep -c '"subtype": *"compact_boundary"' "$TP" 2>/dev/null | tr -cd '0-9')";  COMP="${COMP:-0}"
    AUTOC="$(grep -c '"compact_boundary".*"trigger": *"auto"' "$TP" 2>/dev/null | tr -cd '0-9')"; AUTOC="${AUTOC:-0}"
  fi
fi
marker(){ printf '%s/csk-session-guard.%s.c%s.%s' "${TMPDIR:-/tmp}" "$KEY" "$COMP" "$1"; }

# An AUTO compaction is not a milestone, it is a loss: state nobody chose to drop is already gone, and the fill
# reading right after it is reassuringly low precisely because the context was thrown away. Announce it once per
# generation, independently of the fill tier — waiting for 75% would report the loss long after it happened.
if [ "${AUTOC:-0}" -gt 0 ] && [ ! -e "$(marker autocompact)" ]; then
  : > "$(marker autocompact)" 2>/dev/null || true
  printf '{"systemMessage":"⚠️ Auto-compaction has fired %s time(s) this session — context was dropped that nobody chose to drop. Check that docs/SESSION_STATE.md still matches reality, and hand off at the next phase boundary instead of riding the fill up to another one."}\n' "$AUTOC"
  exit 0
fi

# Real context% — context-usage.sh reads transcript_path from the same stdin JSON. Fail-open on any error.
# --verbose here: this line reaches the USER at most twice per session, so the raw token counts are free.
# (The per-turn UserPromptSubmit injection uses the compact form; that one is paid for on every single turn.)
LINE="$(printf '%s' "$IN" | bash "$HERE/context-usage.sh" --verbose 2>/dev/null | head -1 || true)"
[ -n "$LINE" ] || exit 0

# Pull the percentage back out of the "🔋 Session: %77.2 (...)" line. context-usage.sh pins LC_ALL=C, so the
# decimal separator is always '.' whatever the locale. No number -> cannot classify -> stay silent (fail open).
PCT="$(printf '%s' "$LINE" | sed -n 's/.*%\([0-9][0-9]*\(\.[0-9][0-9]*\)*\).*/\1/p' | head -1)"
[ -n "$PCT" ] || exit 0

# Highest threshold crossed. Compared under LC_ALL=C so '77.2' parses identically everywhere.
TIER=""
LC_ALL=C awk -v p="$PCT" 'BEGIN{exit !(p+0>=90)}' && TIER=90
[ -n "$TIER" ] || { LC_ALL=C awk -v p="$PCT" 'BEGIN{exit !(p+0>=75)}' && TIER=75; }
[ -n "$TIER" ] || exit 0

# Already warned at this tier this session? Stay silent — one alert per threshold, not one per turn.
[ -e "$(marker "$TIER")" ] && exit 0
# Stamp this tier AND every lower one: jumping 60 -> 92 in a single turn must not let the 75 warning fire
# later (e.g. once /compact drops the fill back under 90).
for t in 75 90; do
  [ "$t" -le "$TIER" ] && { : > "$(marker "$t")" 2>/dev/null || true; }
done

if [ "$TIER" = 90 ]; then
  MSG="CRITICAL >90% — hand off NOW: apply the handoff skill, write docs/SESSION_STATE.md, then /clear. Auto-compaction is close and it will cost you the handover."
else
  MSG=">75% threshold. Recommended: apply the handoff skill, write docs/SESSION_STATE.md, then /clear. Manual; your call."
fi

# JSON-escape backslash + double-quote in the measured line before embedding it.
SAFE="$(printf '%s' "$LINE" | sed 's/\\/\\\\/g; s/"/\\"/g')"
# exit 0 + systemMessage: a neutral, user-facing warning (NOT a hook error, does NOT force an extra turn).
printf '{"systemMessage":"%s | %s"}\n' "$SAFE" "$MSG"
exit 0
