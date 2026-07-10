#!/usr/bin/env bash
# Kit smoke-test: structural validation (without running Claude Code).
# Usage: bash .claude/eval/smoke-test.sh   (from the repo root or from inside .claude/eval)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"       # .claude/
AGENTS="$ROOT/agents"; SKILLS="$ROOT/skills"; HOOKS="$ROOT/hooks"
FAIL=0
pass(){ echo "  ✅ $1"; }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "== 1) Agent frontmatter & trigger =="
AC=0
for f in "$AGENTS"/*.md; do
  AC=$((AC+1)); n=$(basename "$f")
  grep -q '^name:' "$f"        || fail "$n: no name"
  grep -q '^tools:' "$f"       || fail "$n: no tools"
  grep -qE '^model:' "$f" || true   # no model means inherit (valid)
  grep -q 'Trigger phrases:' "$f" || fail "$n: no Trigger phrases"
done
# Core agents must be present regardless of profile; stack-specific agents (backend/database/
# frontend-expert-csk) vary by install profile, so no fixed count is expected.
for c in planner-csk security-expert-csk privacy-agent-csk test-expert-csk review-agent-csk commit-agent-csk session-manager-csk; do
  [ -f "$AGENTS/$c.md" ] || fail "missing core agent: $c"
done
[ "$AC" -ge 7 ] && pass "$AC agents found (7 core complete)" || fail "agent count below the 7 core: $AC"

echo "== 2) Skill frontmatter & trigger =="
for d in "$SKILLS"/*/; do
  n=$(basename "$d"); f="$d/SKILL.md"
  [ -f "$f" ] || { fail "$n: no SKILL.md"; continue; }
  grep -q '^name:' "$f"           || fail "$n: no name"
  grep -q 'Trigger phrases:' "$f" || fail "$n: no Trigger phrases"
done
pass "$(ls -d "$SKILLS"/*/ | wc -l | tr -d ' ') skills scanned"

echo "== 3) Orphan skill reference (agent -> nonexistent skill) =="
# (a) Do the X's in "applies the \`X\` skill" in an agent body exist?
for f in "$AGENTS"/*.md; do
  for ref in $(grep -oE 'applies the `[a-z0-9-]+` skill' "$f" | grep -oE '`[a-z0-9-]+`' | tr -d '`'); do
    [ -f "$SKILLS/$ref/SKILL.md" ] || fail "$(basename $f): skill '$ref' does not exist"
  done
done
# (b) Do the backticked skill names on "Also apply: \`x\` · \`y\` ..." lines also exist?
for f in "$AGENTS"/*.md; do
  al="$(grep -F 'Also apply' "$f" || true)"
  for ref in $(printf '%s' "$al" | grep -oE '`[a-z0-9-]+`' | tr -d '`'); do
    [ -f "$SKILLS/$ref/SKILL.md" ] || fail "$(basename $f): 'Also apply' skill does not exist: $ref"
  done
done
pass "agent->skill references (applies + Also apply) checked"

echo "== 4) Stub / unfilled skill leftover =="
if grep -rlq "to be filled\|generated from source" "$SKILLS" 2>/dev/null; then
  fail "stub marker still present"; else pass "no stub"
fi

echo "== 5) Trace + secret scanner ready? =="
[ -x "$HOOKS/pre-commit" ] && pass "pre-commit hook +x" || fail "pre-commit missing/not executable"
[ -f "$HOOKS/trace-blocklist.txt" ] && pass "trace-blocklist present" || fail "trace-blocklist.txt missing"
[ -f "$HOOKS/secret-blocklist.txt" ] && pass "secret-blocklist present" || fail "secret-blocklist.txt missing"
# secret scan (behavioral): a staged fake AWS key MUST be blocked by pre-commit (key split in source so THIS file is clean)
SDIR="$(mktemp -d)"
( cd "$SDIR" && git init -q && git config user.email x@x.x && git config user.name x \
  && cp "$HOOKS/pre-commit" "$HOOKS/trace-blocklist.txt" "$HOOKS/secret-blocklist.txt" . \
  && printf 'aws_key = AKIA%s\n' 'IOSFODNN7EXAMPLE' > leak.txt && git add leak.txt ) >/dev/null 2>&1
if ( cd "$SDIR" && bash pre-commit ) >/dev/null 2>&1; then fail "secret scan LET a staged key through"; else pass "secret scan BLOCKED a staged AWS key"; fi
rm -rf "$SDIR"


echo "== 6) Context-usage threshold logic (fixture) + hook integrity =="
FX="$(mktemp)"
printf '%s\n' '{"isSidechain":false,"message":{"usage":{"input_tokens":1000,"cache_read_input_tokens":800000,"cache_creation_input_tokens":0}}}' > "$FX"
o1="$(CONTEXT_WINDOW=1000000 bash "$HOOKS/context-usage.sh" "$FX" 2>/dev/null)"
case "$o1" in *"handoff+clear"*) pass "threshold: ~80% → handoff+clear" ;; *) fail "threshold(high) not 'handoff+clear': $o1" ;; esac
o2="$(CONTEXT_WINDOW=2000000 bash "$HOOKS/context-usage.sh" "$FX" 2>/dev/null)"
case "$o2" in *"continue"*) pass "threshold: CONTEXT_WINDOW=2M → continue" ;; *) fail "threshold(window) not 'continue': $o2" ;; esac
if bash "$HOOKS/context-usage.sh" "/no/such.jsonl" >/dev/null 2>&1; then fail "malformed transcript returned exit 0"; else pass "malformed transcript exit!=0"; fi
rm -f "$FX"
[ -x "$HOOKS/commit-msg" ]       && pass "commit-msg hook +x"           || fail "commit-msg missing/not executable"
[ -x "$HOOKS/context-usage.sh" ] && pass "context-usage.sh +x"          || fail "context-usage.sh missing/not executable"
[ -x "$HOOKS/session-guard.sh" ] && pass "session-guard.sh +x (Stop)"   || fail "session-guard.sh missing/not executable"

echo "== 6b) Stop-hook gate: once per THRESHOLD · never blocks · systemMessage (not a hook error) =="
SGFX="$(mktemp)"
SGPFX="smoketest-$$-${RANDOM:-0}"
mkjson(){ printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$1" "$2" "$3"; }
fill(){ printf '%s\n' "{\"isSidechain\":false,\"message\":{\"usage\":{\"input_tokens\":0,\"cache_read_input_tokens\":$1,\"cache_creation_input_tokens\":0}}}" > "$SGFX"; }
sg(){ mkjson "$1" "$SGFX" "${2:-false}" | CONTEXT_WINDOW=1000000 bash "$HOOKS/session-guard.sh" 2>/dev/null; }
# (1) below the threshold: completely silent
fill 600000
o="$(sg "${SGPFX}-a")"; r=$?
{ [ "$r" = 0 ] && [ -z "$o" ]; } && pass "stop-hook: <75% is silent (exit 0)" || fail "stop-hook spoke below 75% (rc=$r out=$o)"
# (2) first crossing of 75%: exit 0 + a user-facing systemMessage. exit 2 would render as "Stop hook error".
fill 772000
o="$(sg "${SGPFX}-a")"; r=$?
[ "$r" = 0 ] && pass "stop-hook: never blocks (exit 0)" || fail "stop-hook exit $r (must be 0 — a blocking exit shows as a hook error)"
case "$o" in *'"systemMessage"'*'>75%'*) pass "stop-hook: 75% emits a user systemMessage" ;; *) fail "stop-hook did not emit the 75% systemMessage: $o" ;; esac
# (3) same tier again (even at a higher fill): SILENT — no forced extra turn, no per-turn token burn
fill 800000
[ -z "$(sg "${SGPFX}-a")" ] && pass "stop-hook: same tier stays SILENT on later turns" || fail "stop-hook re-fired inside tier 75"
# (4) crossing 90%: escalates exactly once
fill 920000
o="$(sg "${SGPFX}-a")"
case "$o" in *'"systemMessage"'*CRITICAL*) pass "stop-hook: 90% escalates once (CRITICAL)" ;; *) fail "stop-hook did not escalate at 90%: $o" ;; esac
fill 950000
[ -z "$(sg "${SGPFX}-a")" ] && pass "stop-hook: silent again after the 90% alert" || fail "stop-hook re-fired inside tier 90"
# (5) a jump straight past 90 must stamp the lower tier too, so a post-/compact dip cannot re-fire the 75 alert
fill 930000; sg "${SGPFX}-d" >/dev/null
fill 760000
[ -z "$(sg "${SGPFX}-d")" ] && pass "stop-hook: dipping back under 90% does not re-fire the 75% alert" || fail "stop-hook re-fired the 75% alert after a dip"
# (6) emitted payload is valid JSON carrying systemMessage
if command -v jq >/dev/null 2>&1; then
  fill 800000; sg "${SGPFX}-e" | jq -e '.systemMessage' >/dev/null 2>&1 && pass "stop-hook: stdout is valid JSON with .systemMessage" || fail "stop-hook stdout is not valid systemMessage JSON"
else pass "stop-hook JSON check skipped (no jq)"; fi
# (7) fail-open: unreadable transcript -> exit 0 and silent (never blocks on measurement failure)
o="$(mkjson "${SGPFX}-f" "/no/such.jsonl" false | bash "$HOOKS/session-guard.sh" 2>/dev/null)"; r=$?
{ [ "$r" = 0 ] && [ -z "$o" ]; } && pass "stop-hook: measurement failure fails open (exit 0, silent)" || fail "stop-hook not fail-open (rc=$r out=$o)"
# (8) loop guard: stop_hook_active -> silent no-op
fill 920000
[ -z "$(sg "${SGPFX}-g" true)" ] && pass "stop-hook: stop_hook_active loop-guard is a silent no-op" || fail "stop-hook ignored stop_hook_active"
rm -f "$SGFX"; rm -f "${TMPDIR:-/tmp}"/csk-session-guard.${SGPFX}-*.* 2>/dev/null

echo "== 6c) no-jq fallback: sidechain-safe + full token sum =="
JXBIN="$(mktemp -d)"; JXOK=1
BASHBIN="$(command -v bash 2>/dev/null || echo bash)"   # absolute -> the stripped PATH must not hide bash itself
for t in awk sed grep head tail cat ls tr; do
  tp="$(command -v "$t" 2>/dev/null)" && ln -s "$tp" "$JXBIN/$t" 2>/dev/null || JXOK=0
done
if [ "$JXOK" = 1 ] && ! PATH="$JXBIN" command -v jq >/dev/null 2>&1; then
  SX="$(mktemp)"
  printf '%s\n' '{"isSidechain":false,"message":{"usage":{"input_tokens":20,"cache_read_input_tokens":760000,"cache_creation_input_tokens":11936}}}' >  "$SX"
  printf '%s\n' '{"isSidechain":true,"message":{"usage":{"input_tokens":5,"cache_read_input_tokens":30000,"cache_creation_input_tokens":0}}}'        >> "$SX"
  ox="$(PATH="$JXBIN" CONTEXT_WINDOW=1000000 "$BASHBIN" "$HOOKS/context-usage.sh" --verbose "$SX" 2>/dev/null)"
  case "$ox" in
    *"771956/1000000"*handoff+clear*) pass "no-jq: skips sidechain + sums input+cache_read+cache_creation (771956)" ;;
    *) fail "no-jq fallback wrong (sidechain leak or undercount): $ox" ;;
  esac
  rm -f "$SX"
else
  pass "no-jq fallback test skipped (no symlink / jq-less PATH buildable here)"
fi
rm -rf "$JXBIN"

echo "== 6d) locale: percentage keeps '.' under a comma locale =="
FXL="$(mktemp)"
printf '%s\n' '{"isSidechain":false,"message":{"usage":{"input_tokens":1000,"cache_read_input_tokens":800000,"cache_creation_input_tokens":0}}}' > "$FXL"
ol="$(LANG=tr_TR.UTF-8 LC_NUMERIC=tr_TR.UTF-8 CONTEXT_WINDOW=1000000 bash "$HOOKS/context-usage.sh" "$FXL" 2>/dev/null | head -1)"
case "$ol" in *,*) fail "locale: percentage emitted a comma under tr_TR: $ol" ;; *) pass "locale: decimal stays '.' under tr_TR ($ol)" ;; esac
rm -f "$FXL"

echo "== 6e) CLAUDE.md split: sentinel · discipline/project boundary · profiles.conf =="
# In the kit repo ROOT is claude-starter/ (payload). In an installed project it is .claude/, which has no
# CLAUDE.md but does have the already-split DISCIPLINE.md. Assert whichever is present.
if [ -f "$ROOT/CLAUDE.md" ]; then
  grep -qE '^<!-- KIT:DISCIPLINE-END' "$ROOT/CLAUDE.md" && pass "payload CLAUDE.md carries the KIT:DISCIPLINE-END sentinel" \
    || fail "payload CLAUDE.md has no anchored '<!-- KIT:DISCIPLINE-END' line — installers would abort"
  [ "$(grep -cE '^<!-- KIT:DISCIPLINE-END' "$ROOT/CLAUDE.md")" = 1 ] && pass "sentinel appears exactly once" || fail "sentinel is not unique"
  D_HALF="$(awk '/^<!-- KIT:DISCIPLINE-END/{exit} {print}' "$ROOT/CLAUDE.md")"
  P_HALF="$(awk 'f{print} /^<!-- KIT:DISCIPLINE-END/{f=1}' "$ROOT/CLAUDE.md")"
  case "$D_HALF" in *'<PROJECT NAME>'*) fail "discipline half swallows the project template" ;; *) pass "discipline half excludes the project template" ;; esac
  case "$D_HALF" in *'Four working principles'*) pass "discipline half carries the four principles" ;; *) fail "discipline half lost the four principles" ;; esac
  case "$P_HALF" in *'<PROJECT NAME>'*) pass "project half carries the project template" ;; *) fail "project half lost the project template" ;; esac
  case "$P_HALF" in *'Four working principles'*) fail "project half duplicates the discipline" ;; *) pass "project half does not duplicate the discipline" ;; esac
fi
if [ -f "$ROOT/DISCIPLINE.md" ]; then
  case "$(cat "$ROOT/DISCIPLINE.md")" in
    *'<PROJECT NAME>'*) fail "installed DISCIPLINE.md swallowed the project template" ;;
    *) pass "installed DISCIPLINE.md is discipline-only" ;;
  esac
  grep -qE '^<!-- KIT:DISCIPLINE-END' "$ROOT/DISCIPLINE.md" && fail "sentinel leaked into DISCIPLINE.md" || pass "no sentinel leak in DISCIPLINE.md"
fi
if [ -f "$ROOT/profiles.conf" ]; then
  for p in backend frontend mobile fullstack; do
    grep -qE "^$p:" "$ROOT/profiles.conf" || fail "profiles.conf: missing profile row '$p'"
  done
  pass "profiles.conf lists all four profiles (single source of truth for start.sh + adopt.sh)"
  grep -qE '^fullstack::$' "$ROOT/profiles.conf" && pass "fullstack prunes nothing (mobile RN/Expo included)" || fail "fullstack row must prune nothing"
fi
if [ -f "$ROOT/kit.conf" ]; then
  KP="$(sed -n 's/^profile=//p' "$ROOT/kit.conf" | head -1)"
  case "$KP" in backend|frontend|mobile|fullstack) pass "kit.conf records a known profile ($KP)" ;; *) fail "kit.conf profile invalid: '$KP'" ;; esac
fi

echo "== 6f) always-on token budget =="
# Everything below is loaded into EVERY session's context (and, when Claude spawns one, into a subagent's).
# Measured with a real `claude -p` turn: 21804 bytes of always-on material cost 9198 tokens. Bytes are a proxy
# for that cost, and a gate rather than a reminder — a verbose new description fails the suite instead of
# quietly taxing every future session. Budgets sit just above the current sizes: raising one is allowed, but
# only as a deliberate edit here.
BUDGET_DISC=9200     # DISCIPLINE.md (the discipline half of CLAUDE.md); currently 8969
BUDGET_AGENTS=4700   # sum of agent frontmatter; currently 4551
BUDGET_SKILLS=8500   # sum of skill frontmatter; currently 8284
fm_bytes(){ awk '/^---$/{c++; next} c==1' "$1" 2>/dev/null | wc -c | tr -d ' '; }
if [ -f "$ROOT/CLAUDE.md" ]; then
  DB="$(awk '/^<!-- KIT:DISCIPLINE-END/{exit} {print}' "$ROOT/CLAUDE.md" | wc -c | tr -d ' ')"
elif [ -f "$ROOT/DISCIPLINE.md" ]; then DB="$(wc -c < "$ROOT/DISCIPLINE.md" | tr -d ' ')"; else DB=0; fi
AB=0; for f in "$AGENTS"/*.md;      do [ -e "$f" ] && AB=$((AB + $(fm_bytes "$f"))); done
SB=0; for f in "$SKILLS"/*/SKILL.md; do [ -e "$f" ] && SB=$((SB + $(fm_bytes "$f"))); done
[ "$DB" -le "$BUDGET_DISC" ]   && pass "discipline within budget ($DB ≤ $BUDGET_DISC bytes)"        || fail "discipline over budget: $DB > $BUDGET_DISC bytes"
[ "$AB" -le "$BUDGET_AGENTS" ] && pass "agent descriptions within budget ($AB ≤ $BUDGET_AGENTS)"    || fail "agent descriptions over budget: $AB > $BUDGET_AGENTS bytes"
[ "$SB" -le "$BUDGET_SKILLS" ] && pass "skill descriptions within budget ($SB ≤ $BUDGET_SKILLS)"    || fail "skill descriptions over budget: $SB > $BUDGET_SKILLS bytes"
echo "   always-on total: $((DB+AB+SB)) bytes (budget $((BUDGET_DISC+BUDGET_AGENTS+BUDGET_SKILLS)))"
# Every agent/skill must still declare its trigger phrases — that is what routes work to it. Trimming prose
# is the point; trimming triggers would silently break routing, and routing-eval only checks the golden set.
MISSING=""
for f in "$AGENTS"/*.md "$SKILLS"/*/SKILL.md; do
  [ -e "$f" ] || continue
  awk '/^---$/{c++; next} c==1' "$f" | grep -qi 'trigger' || MISSING="$MISSING $(basename "$(dirname "$f")")/$(basename "$f")"
done
[ -z "$MISSING" ] && pass "every agent/skill still declares Trigger phrases" || fail "no trigger phrases in:$MISSING"

echo "== 7) settings.json & guard (§4.4/§4.5) =="
if [ -f "$ROOT/settings.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq empty "$ROOT/settings.json" 2>/dev/null && pass "settings.json valid JSON" || fail "settings.json invalid JSON"
  else pass "settings.json present (no jq, JSON validation skipped)"; fi
else fail "settings.json missing"; fi
[ -x "$HOOKS/guard-bash.sh" ] && pass "guard-bash.sh +x" || fail "guard-bash.sh missing/not executable"
# §4.4 git approval gate (behavioral). Contract:
#   normal modes  -> exit 0 + permissionDecision:"ask"  (the USER approves in-session; Claude then commits)
#   bypass/unknown-> exit 2 (fail closed; no prompt can be proven to reach the user)
#   CLAUDE_GIT_OK -> exit 0, silent (pre-authorised headless/CI)
#   §4.5 ops      -> exit 2 in every mode, even with the key
gj(){ printf '{"tool_name":"Bash","permission_mode":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }
gdec(){ printf '%s' "$1" | sed -n 's/.*"permissionDecision"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1; }
for m in default acceptEdits auto dontAsk; do
  o="$(gj "$m" 'git commit -m x' | bash "$HOOKS/guard-bash.sh" 2>/dev/null)"; r=$?
  { [ "$r" = 0 ] && [ "$(gdec "$o")" = "ask" ]; } \
    && pass "git commit ASKS the user in '$m' (§4.4)" \
    || fail "git commit did not ask in '$m' (rc=$r out=$o)"
done
o="$(gj auto 'git push' | bash "$HOOKS/guard-bash.sh" 2>/dev/null)"
[ "$(gdec "$o")" = "ask" ] && pass "git push ASKS the user (§4.4)" || fail "git push did not ask"
# The ask payload must be parseable JSON. A tab, CR or quote from the commit message, passed through raw,
# would make it a control-character parse error — build the fixture with jq so the INPUT is valid too.
if command -v jq >/dev/null 2>&1; then
  NASTY="$(printf 'git commit -m "a\tb \\"q\\" C:\\\\p"')"
  o="$(jq -nc --arg c "$NASTY" '{tool_name:"Bash",permission_mode:"auto",tool_input:{command:$c}}' | bash "$HOOKS/guard-bash.sh" 2>/dev/null)"
  printf '%s' "$o" | jq -e '.hookSpecificOutput.permissionDecision=="ask"' >/dev/null 2>&1 \
    && pass "ask payload stays valid JSON for a message with tabs/quotes/backslashes" || fail "ask payload is not valid JSON: $o"
else pass "ask-payload JSON check skipped (no jq)"; fi
# fail closed where no prompt can reach the user
gj bypassPermissions 'git commit -m x' | bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && fail "git commit PASSED under bypassPermissions (§4.4 hole)" || pass "git commit FAILS CLOSED under bypassPermissions (§4.4)"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && fail "git commit PASSED with no permission_mode (§4.4 hole)" || pass "git commit FAILS CLOSED when permission_mode is absent"
gj auto 'CLAUDE_GIT_OK=1 git commit -m x' | bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && fail "inline CLAUDE_GIT_OK PASSED (§4.4 hole)" || pass "inline CLAUDE_GIT_OK injection rejected (§4.4)"
# pre-authorised session
gj bypassPermissions 'git commit -m x' | CLAUDE_GIT_OK=1 bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && pass "git commit PASSES with CLAUDE_GIT_OK=1" || fail "keyed commit blocked (gate too strict)"
# §4.5 always wins, key or no key, mode or no mode
gj auto 'git push --force' | CLAUDE_GIT_OK=1 bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && fail "push --force PASSED with key (§4.5 hole)" || pass "push --force BLOCKED even with key (§4.5)"
gj bypassPermissions 'git reset --hard' | CLAUDE_GIT_OK=1 bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && fail "reset --hard PASSED (§4.5 hole)" || pass "reset --hard BLOCKED in bypass + key (§4.5)"

echo "== 8) Slash commands =="
for c in simplify plan review ship handoff; do
  [ -f "$ROOT/commands/$c.md" ] && pass "/$c present" || fail "/$c command missing"
done

echo "---"
if [ "$FAIL" -eq 0 ]; then echo "SMOKE-TEST: PASSED ✅"; exit 0
else echo "SMOKE-TEST: $FAIL errors ❌"; exit 1; fi
