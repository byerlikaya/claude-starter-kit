#!/usr/bin/env bash
# Install doctor — verify a LIVE kit install in a CONSUMER repo is actually active. This is the counterpart to
# smoke-test.sh: smoke-test checks the kit's SOURCE (dev-side, in this repo); doctor checks a real install on a
# user's machine — the things that silently make the gates inert: a hook left non-executable, core.hooksPath not
# set (so the commit trace/secret scan never runs), settings.json missing (so the tool-level gates never fire).
# Zero-dep, bash-only, Git-Bash safe. Run from the project root (or pass the path):  bash .claude/eval/doctor.sh
set -uo pipefail
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "doctor: cannot enter '$ROOT'"; exit 2; }

FAIL=0
ok(){  echo "  ✅ $1"; }
bad(){ echo "  ❌ $1"; echo "     ↳ fix: $2"; FAIL=$((FAIL+1)); }
warn(){ echo "  ⚠️  $1"; }

echo "== Claude Starter Kit — install doctor =="

# 0) Is the kit even here?
[ -d .claude ] || { echo "  ❌ no .claude/ in '$PWD' — is the kit installed here?"; echo "     ↳ fix: npx @byerlikaya/claude-starter-kit adopt"; exit 1; }

# 1) VERSION (marks a full install; also what /update-csk compares)
if [ -f .claude/VERSION ]; then ok "VERSION present ($(head -1 .claude/VERSION | tr -cd '0-9A-Za-z.-'))"
else bad "VERSION missing" "reinstall or update the kit (npx @byerlikaya/claude-starter-kit update)"; fi

# 2) Hooks present + executable. The .sh set is a glob (extras ok); pre-commit + commit-msg are REQUIRED — they
#    ARE the §4.1/§4.2 trace/secret gate, so a MISSING one is a failure, not a silent skip.
NX=""; GONE=""
for h in .claude/hooks/*.sh; do [ -e "$h" ] || continue; [ -x "$h" ] || NX="$NX $(basename "$h")"; done
for h in .claude/hooks/pre-commit .claude/hooks/commit-msg; do
  if [ ! -e "$h" ]; then GONE="$GONE $(basename "$h")"; elif [ ! -x "$h" ]; then NX="$NX $(basename "$h")"; fi
done
[ -z "$GONE" ] && ok "required git hooks present (pre-commit, commit-msg)" \
              || bad "MISSING git hook(s):$GONE — the commit trace/secret scan is absent" "reinstall or update the kit"
[ -z "$NX" ] && ok "all hooks are executable" \
             || bad "not executable:$NX" "chmod +x .claude/hooks/*.sh .claude/hooks/pre-commit .claude/hooks/commit-msg"

# 2b) Behaviour probe — a hook that is present + executable can still be NEUTERED (its body replaced with `exit 0`).
#     Drive guard-bash with a command it MUST block; if it does not exit 2, the §4.5 gate is disarmed.
if [ -x .claude/hooks/guard-bash.sh ]; then
  if printf '%s' '{"tool_name":"Bash","permission_mode":"auto","tool_input":{"command":"git push --force"}}' | bash .claude/hooks/guard-bash.sh >/dev/null 2>&1; then
    bad "guard-bash.sh did NOT block a force-push — the §4.5 gate is neutered/disarmed" "restore guard-bash.sh from the kit"
  else ok "guard-bash.sh blocks a force-push (gate live, not neutered)"; fi
fi

# 3) core.hooksPath — without it the §4.1/§4.2 commit trace + secret/bloat scan never runs
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HP="$(git config --get core.hooksPath 2>/dev/null || true)"
  case "$HP" in
    */.claude/hooks|.claude/hooks) ok "core.hooksPath -> $HP (commit-time gates active)" ;;
    "") bad "core.hooksPath is unset — commit trace/secret/bloat gates are INACTIVE" "git config core.hooksPath .claude/hooks" ;;
    *)  bad "core.hooksPath -> $HP (not the kit's hooks)" "git config core.hooksPath .claude/hooks" ;;
  esac
else
  warn "not a git repo — commit gates need: git init && git config core.hooksPath .claude/hooks"
fi

# 4) settings.json wires the tool-level gates, and each event maps to a NON-EMPTY hook array (an empty [] wires
#    nothing). PreToolUse/UserPromptSubmit/Stop are required; SessionStart (rehydration) is a warn if absent.
S=.claude/settings.json
if [ -f "$S" ]; then
  if command -v jq >/dev/null 2>&1; then
    if jq empty "$S" 2>/dev/null; then
      ok "settings.json is valid JSON"
      EMPTY=""
      for ev in PreToolUse UserPromptSubmit Stop; do
        n="$(jq -r --arg e "$ev" '(.hooks[$e] // []) | length' "$S" 2>/dev/null)"
        case "$n" in ''|0) EMPTY="$EMPTY $ev" ;; esac
      done
      [ -z "$EMPTY" ] && ok "settings.json wires PreToolUse / UserPromptSubmit / Stop (non-empty)" \
                      || bad "settings.json hook events empty or missing:$EMPTY — those gates won't fire" "restore settings.json from the kit"
      sn="$(jq -r '(.hooks.SessionStart // []) | length' "$S" 2>/dev/null)"
      case "$sn" in ''|0) warn "SessionStart not wired — session rehydration after /compact or /clear is inactive (update the kit)" ;; *) ok "SessionStart wired (session rehydration active)" ;; esac
    else bad "settings.json is invalid JSON" "restore settings.json from the kit"; fi
  else
    # no jq: best-effort — each required event name must appear, and a hook command must be wired somewhere.
    MISS=""
    for ev in PreToolUse UserPromptSubmit Stop; do grep -q "\"$ev\"" "$S" || MISS="$MISS $ev"; done
    { [ -z "$MISS" ] && grep -q 'hooks/' "$S"; } && ok "settings.json wires the required hook events (no jq: name check)" \
      || bad "settings.json missing hook events or wiring:$MISS" "restore settings.json from the kit"
    grep -q '"SessionStart"' "$S" || warn "SessionStart not wired — session rehydration inactive (update the kit)"
  fi
else
  bad "settings.json missing — the tool-level gates (commit approval, guards, context) are INACTIVE" "reinstall the kit"
fi

# 5) Agent-name references in CLAUDE.md resolve to an installed agent. A brownfield adopt renames the project's
#    own agents to the kit's `-csk` ids (and carries their knowledge into `-local` skills), but the project's
#    CLAUDE.md may still name the OLD bare agent ("→ backend-expert"). That bare name matches no installed agent,
#    so delegation to it silently fails and the specialist never fires — invisible to every other check here.
if [ -f CLAUDE.md ] && ls .claude/agents/*.md >/dev/null 2>&1; then
  # Two pull-only agents are invoked explicitly (a commit needs approval; session health is emitted by a hook),
  # NOT auto-delegated — so a bare reference to them does not break delegation; it is only a naming inconsistency.
  PULL_AGENTS=" commit-agent-csk session-manager-csk "
  STALE=""; STALE_PULL=""
  for f in .claude/agents/*.md; do
    [ -e "$f" ] || continue
    name="$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1 | tr -cd 'a-zA-Z0-9-')"
    [ -n "$name" ] || name="$(basename "$f" .md)"
    case "$name" in *-csk) base="${name%-csk}" ;; *) continue ;; esac
    # bare `base` NOT followed by `-` (so not base-csk) and not glued into a longer word
    lines="$(grep -nE "(^|[^a-zA-Z-])$base([^a-zA-Z-]|$)" CLAUDE.md 2>/dev/null | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')"
    [ -n "$lines" ] || continue
    entry="
     ↳ \"$base\" → \"$name\"   (CLAUDE.md line(s): $lines)"
    case "$PULL_AGENTS" in *" $name "*) STALE_PULL="$STALE_PULL$entry" ;; *) STALE="$STALE$entry" ;; esac
  done
  if [ -n "$STALE" ]; then
    bad "CLAUDE.md names auto-delegated agent(s) that no installed agent matches — delegation to them silently fails" \
        "rename each bare reference to its \`-csk\` id in CLAUDE.md:$STALE"
  fi
  [ -n "$STALE_PULL" ] && warn "CLAUDE.md names pull-only agent(s) by their old bare id — invoked explicitly, so delegation still works; rename for consistency:$STALE_PULL"
  [ -z "$STALE$STALE_PULL" ] && ok "CLAUDE.md agent references resolve to installed agents"
fi

echo "---"
if [ "$FAIL" -eq 0 ]; then echo "DOCTOR: healthy ✅"; exit 0
else echo "DOCTOR: $FAIL issue(s) ❌ — apply the fixes above"; exit 1; fi
