#!/usr/bin/env bash
# What the kit LOADS versus what it actually FIRES.
#
# Every installed skill spends its name and description in EVERY session's skill listing, forever, whether or not
# it is ever used. doctor.sh §4a already measures the loaded half and reports it against the budget. This
# measures the other half, because the documented remedy for an over-budget listing — setting rarely-used skills
# to "name-only" in skillOverrides — needs a list of WHICH skills, and nothing produced one. A cold skill is not
# automatically a bad skill (an incident runbook earns its keep by existing), so this REPORTS and never enforces.
#
# Usage:  bash utilization.sh [--all-projects]
# Exit:   0 always. Measuring context cost must never fail a build.
#
# PRIVACY (§4.3): the current project only, unless --all-projects is asked for explicitly. What is printed is
# skill NAMES and COUNTS — never a path, never the encoded project directory, never a prompt or a file content.
# Nothing is written anywhere; this script only reads.
set -uo pipefail

ALL=0
case "${1:-}" in
  --all-projects) ALL=1 ;;
  ""|--help|-h) [ "${1:-}" != "" ] && { sed -n '2,12p' "$0"; exit 0; } ;;
esac

# Where the skills live: an installed project, or this repo's payload when run from the kit's own checkout.
SKILLS=""; OWNREPO=0
for d in .claude/skills claude-starter/skills; do [ -d "$d" ] && { SKILLS="$d"; break; }; done
[ "$SKILLS" = "claude-starter/skills" ] && OWNREPO=1
if [ -z "$SKILLS" ]; then echo "utilization: no skills directory here (looked for .claude/skills)"; exit 0; fi

TR=""
# ---- CSK-TRANSCRIPT-DIR (kept byte-identical in context-usage.sh and session-stats.sh; smoke-test §6i3 pins it)
# Claude Code stores a session under $HOME/.claude/projects/<cwd encoded as a directory name>. Reproducing that
# encoding is the ONLY way a by-hand call (no hook payload on stdin) can find its own transcript.
csk_project_dirs(){   # candidate directory names for the current cwd, best first, one per line
  local w p
  # Windows first. Claude Code sees the NATIVE cwd (C:\repo\app) while Git Bash's `pwd` reports /c/repo/app, so
  # the drive letter never matched and the by-hand call could not resolve a transcript on Windows AT ALL — the
  # same "transcript not found" was reported from that machine three separate times before the cause was found.
  # `pwd -W` is the MSYS builtin that returns the native form; elsewhere it just fails and is discarded.
  w="$(pwd -W 2>/dev/null || true)"
  # The encoder folds : \ / . AND _ to '-'. The underscore is the one that hides: a project named `report_api`
  # lands in `...-report-api`, so folding only slashes and dots misses every path containing an underscore — on
  # every platform, not just Windows.
  for p in "$w" "$(pwd)"; do
    [ -n "$p" ] && printf '%s\n' "$(printf '%s' "$p" | sed 's#[:\\/._]#-#g')"
  done
  # Legacy shapes, kept so a directory written by an older client still resolves.
  printf '%s\n' "$(pwd | sed 's#[/.]#-#g')" "$(pwd | sed 's#/#-#g')"
}
if [ -z "$TR" ]; then
  while IFS= read -r esc; do
    [ -n "$esc" ] || continue
    cand="$(ls -t "$HOME/.claude/projects/$esc"/*.jsonl 2>/dev/null | head -1)"
    [ -n "$cand" ] && { TR="$cand"; break; }
  done <<CSKEOF
$(csk_project_dirs)
CSKEOF
fi
# ---- /CSK-TRANSCRIPT-DIR

# THE TRANSCRIPTS ARE NOT ONE FILE, AND THAT IS THE WHOLE MEASUREMENT. A project directory holds
# <session>.jsonl at the top AND a <session>/ directory per session whose subagents/ tree carries one transcript
# per delegated agent. Measured on this machine while writing this: 14 transcripts at the top level, 306 nested.
# A parser that reads only the top level therefore misses most of the work — and delegated agents are precisely
# where skills fire, because that is what they are delegated with. Counting only the top level reported 2 of 40
# skills as used; counting the tree reported 21. The difference is not a rounding error, it is the answer.
if [ "$ALL" = 1 ]; then
  DIRS="$HOME/.claude/projects"
  [ -d "$DIRS" ] || { echo "utilization: NOT MEASURED — no transcripts directory"; exit 0; }
  SCOPE="all projects"
else
  [ -n "$TR" ] || { echo "utilization: NOT MEASURED — no transcript found for this project."
                    echo "  (a fresh checkout, a first session, or a project directory the encoder cannot reproduce)"
                    echo "  NOT MEASURED is not the same as 'nothing fired'; it means nothing was read."; exit 0; }
  DIRS="$(dirname "$TR")"
  SCOPE="this project"
fi

# One grep over the tree, not one per skill: 40 greps × 320 files is the cost pattern this kit keeps removing.
#
# TWO SHAPES COUNT AS A FIRING, and only these two:
#   "file_path":"…/skills/<name>/SKILL.md"   — the skill was READ (how a skill is actually consumed)
#   "name":"Skill","input":{"skill":"<name>" — the Skill tool was invoked by name
# THE ANCHOR IS THE POINT. Matching a bare skill name anywhere in the JSON would count the kit measuring itself:
# a single `grep -rn description: skills/` tool result echoes all 40 paths on one line, and every skill would
# report as used forever. Both patterns above require the name to sit in a position only a real invocation puts
# it in. Lines carrying "is_error":true are dropped first — a read that failed is not a use. That drop is
# line-level, so it catches the error record itself; correlating a failed result back to its own tool_use id
# would need a second pass over every line, and a Read of a file that is installed rarely fails.
HITS="$(grep -rhI --include='*.jsonl' -e '"file_path":"' -e '"name":"Skill"' "$DIRS" 2>/dev/null \
        | grep -v '"is_error":true' \
        | grep -ohE '/skills/[A-Za-z0-9._-]+/SKILL\.md|"name":"Skill","input":\{"skill":"[A-Za-z0-9._-]+"' 2>/dev/null \
        | sed -e 's#^/skills/##' -e 's#/SKILL\.md$##' -e 's#.*"skill":"##' -e 's#"$##' \
        | sort | uniq -c | sort -rn)"

FIRED=0; COLD=0; COLDLIST=""; COLDBYTES=0; FIREDLIST=""
for f in "$SKILLS"/*/SKILL.md; do
  [ -e "$f" ] || continue
  n="$(basename "$(dirname "$f")")"
  c="$(printf '%s\n' "$HITS" | awk -v s="$n" '$2==s {print $1; exit}')"
  if [ -n "$c" ]; then
    FIRED=$((FIRED+1)); FIREDLIST="$FIREDLIST  $n($c)"
  else
    COLD=$((COLD+1)); COLDLIST="$COLDLIST  $n"
    b="$(awk '/^---$/{k++; next} k==1' "$f" | awk '/^(name|description):/,0' | wc -c | tr -d ' ')"
    COLDBYTES=$((COLDBYTES + b))
  fi
done
TOTAL=$((FIRED+COLD))
[ "$TOTAL" -gt 0 ] || { echo "utilization: NOT MEASURED — no skills installed"; exit 0; }

NSESS="$(find "$DIRS" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
echo "== skill utilization ($SCOPE, $NSESS transcript file(s)) =="
echo "  fired : $FIRED/$TOTAL"
echo "  cold  : $COLD/$TOTAL   (${COLDBYTES} B of always-on listing spent on skills nothing reached)"
[ -n "$FIREDLIST" ] && { echo "  --- fired (times reached) ---"; printf '%s\n' "$FIREDLIST" | tr ' ' '\n' | grep -v '^$' | sort | paste -sd' ' - | fold -s -w 100 | sed 's/^/    /'; }
[ -n "$COLDLIST" ]  && { echo "  --- cold ---";                  printf '%s\n' "$COLDLIST"  | tr ' ' '\n' | grep -v '^$' | sort | paste -sd' ' - | fold -s -w 100 | sed 's/^/    /'; }
echo "  ---"
# The kit's own repository is the one place where this number lies, so it says so rather than being quoted out
# of context later. Here a SKILL.md is opened to EDIT it, and an edit is indistinguishable from an invocation at
# the transcript level — both are a Read of the same path. In a project that USES the kit there is no such
# traffic, which is the case the measurement is for.
[ "$OWNREPO" = 1 ] && {
  echo "  NOTE: read from the kit's OWN repository, where a SKILL.md is opened to be EDITED. Those edits are"
  echo "  indistinguishable from invocations here, so 'fired' is inflated. Run this in a project that USES the"
  echo "  kit for a number that means what it says."
  echo "  ---"; }
echo "  A cold skill is not a bad skill — a runbook earns its place by existing. This is the evidence for the"
echo "  skillOverrides \"name-only\" decision doctor.sh §4a asks you to make, not the decision itself."
exit 0
