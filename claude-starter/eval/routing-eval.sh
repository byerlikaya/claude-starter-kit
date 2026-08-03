#!/usr/bin/env bash
# Behavioral eval: does a golden prompt route to the expected target via a trigger (deterministic)?
# Does NOT run Claude Code; it statically proxies the routing correctness of the trigger design:
#   1) Golden routing  — each example prompt must contain (as a substring) one trigger of its expected target.
#   2) Agent collision  — two DIFFERENT agents must not share the same trigger phrase (routing ambiguity).
# Turkish diacritics are normalized on both sides (guvenlik == güvenlik), so it is also robust for
# users who type without diacritics. In a pruned install, a line whose target is not installed is SKIPPED.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
AGENTS="$ROOT/agents"; SKILLS="$ROOT/skills"
GOLD="$HERE/golden-routing.txt"
FAIL=0; SKIP=0
pass(){ echo "  ✅ $1"; }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
skip(){ echo "  ⏭  $1"; SKIP=$((SKIP+1)); }

# Turkish diacritics -> ascii, lowercase, then every run of non-alphanumerics becomes ONE space and the whole
# string is space-padded. That padding is what makes the match word-bounded: a bare substring test routed "the
# build fails on CI" to the frontend expert, because `build` contains `ui` and `UI` is one of its triggers.
# Every short trigger has that failure mode (ui · api · e2e), and it points the wrong way — a CI failure sent to
# the frontend agent is worse than no routing at all, because it looks like the kit worked.
norm() {
  printf '%s' "$1" | sed \
    -e 's/Ç/c/g' -e 's/ç/c/g' -e 's/Ğ/g/g' -e 's/ğ/g/g' -e 's/İ/i/g' -e 's/ı/i/g' \
    -e 's/Ö/o/g' -e 's/ö/o/g' -e 's/Ş/s/g' -e 's/ş/s/g' -e 's/Ü/u/g' -e 's/ü/u/g' \
    | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/ /g' -e 's/^/ /' -e 's/$/ /'
}

triggers_of() {  # $1 = target name; prints its trigger phrases line by line (exit 1 if none)
  local n="$1" f=""
  if   [ -f "$AGENTS/$n.md" ];      then f="$AGENTS/$n.md"
  elif [ -f "$SKILLS/$n/SKILL.md" ]; then f="$SKILLS/$n/SKILL.md"
  else return 1; fi
  grep -i "Trigger phrases:" "$f" | head -1 | grep -oE '"[^"]+"' | sed 's/"//g'
}

echo "== 1) Golden routing (prompt -> expected target) =="
[ -f "$GOLD" ] || { fail "golden-routing.txt missing"; }
while IFS='|' read -r prompt expected; do
  case "$prompt" in ''|\#*) continue ;; esac
  expected="$(printf '%s' "$expected" | tr -d '[:space:]')"
  [ -n "$expected" ] || continue
  neg=0; case "$expected" in '!'*) neg=1; expected="${expected#!}" ;; esac   # !target = must NOT route here
  # Pre-2.0 this skipped when the target was pruned by profile. Profiles are gone: every install carries every
  # agent and skill, so an absent target is a missing component or a stale golden row — both real failures. The
  # exception is the .NET pattern skill, the one component a --generic install legitimately does not have.
  if ! trs="$(triggers_of "$expected")"; then
    case "$expected" in
      devarch-module) skip "\"$prompt\" -> $expected (generic backend: the .NET pattern skill is not installed)" ;;
      *)              fail "\"$prompt\" -> $expected: target not installed — 2.0 ships every component" ;;
    esac
    continue
  fi
  np="$(norm "$prompt")"
  hit=0
  while IFS= read -r ph; do
    [ -n "$ph" ] || continue
    nph="$(norm "$ph")"
    case "$np" in *"$nph"*) hit=1; break ;; esac
  done <<EOF
$trs
EOF
  if [ "$neg" = 1 ]; then
    if [ "$hit" = 0 ]; then pass "\"$prompt\" -/-> $expected (correctly not matched)"
    else fail "\"$prompt\" -/-> $expected (over-broad trigger — matched a prompt it should not route)"; fi
  else
    if [ "$hit" = 1 ]; then pass "\"$prompt\" -> $expected"
    else fail "\"$prompt\" -> $expected (no trigger matched — routing gap)"; fi
  fi
done < "$GOLD"

echo "== 1b) Routing COVERAGE — every installed component has at least one positive case =="
# The golden set proves that the cases in it route. It never proved that every component HAS a case, and an audit
# found 12 skills and one agent with none — including security-scan, code-review, testing and spec-planning. A
# component with no case is a component whose reachability is nobody's job to check, which is exactly how
# frontend-expert-csk stayed unreachable for a whole class of request while every gate reported green. Adding a
# component now means adding the sentence that must reach it.
MISSING_CASE=""
for f in "$AGENTS"/*.md "$SKILLS"/*/SKILL.md; do
  [ -e "$f" ] || continue
  case "$f" in */SKILL.md) n="$(basename "$(dirname "$f")")" ;; *) n="$(basename "$f" .md)" ;; esac
  grep -qE "^[^#]*\|$n\$" "$GOLD" || MISSING_CASE="$MISSING_CASE $n"
done
[ -z "$MISSING_CASE" ] && pass "every installed agent/skill has a positive routing case" \
  || fail "no positive golden case for:$MISSING_CASE — add the sentence a user would type to reach it"

echo "== 2) Agent-agent trigger collision =="
# NOTE: Only AGENT-AGENT collisions matter (routing ambiguity lives here). An agent sharing a trigger
# with the skill it OWNS (backend-expert-csk<->devarch-module, security-expert-csk<->security-scan,
# devops-expert-csk<->incident-runbook ...) is EXPECTED: the skill is the agent's internal "how"
# source, not a separate dispatch — the router picks the agent, the agent reads the skill inside a
# single subagent. So an agent<->its-own-skill overlap is intentional and is NOT a FAIL here.
# Collect each agent's unique (normalized) triggers; anything appearing in 2+ agents = collision.
dupe="$(
  for f in "$AGENTS"/*.md; do
    grep -i "Trigger phrases:" "$f" | head -1 | grep -oE '"[^"]+"' | sed 's/"//g' | while IFS= read -r p; do
      [ -n "$p" ] && norm "$p"
    done | sort -u
  done | sort | uniq -d
)"
if [ -n "$dupe" ]; then
  while IFS= read -r d; do [ -n "$d" ] && fail "same trigger in multiple agents: \"$d\""; done <<EOF
$dupe
EOF
else
  pass "agent triggers unique (no collision)"
fi

echo "---"
if [ "$FAIL" -eq 0 ]; then echo "ROUTING-EVAL: PASSED ✅  (skipped: $SKIP)"; exit 0
else echo "ROUTING-EVAL: $FAIL errors ❌  (skipped: $SKIP)"; exit 1; fi
