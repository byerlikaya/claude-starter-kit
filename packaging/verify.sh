#!/usr/bin/env bash
# verify.sh — run a CI gate locally, from the SAME definition CI runs.
#
# Why this exists. Every gate in this repo was reachable locally except as a set: the suites lived in
# eval/, the catalogue and manifest checks lived only in ci.yml, and "green" locally meant a strictly
# smaller thing than "green" in CI. That gap is not theoretical — a branch was pushed with all three
# eval suites green and CI failed on the one check that had no local runner, because the README
# catalogue is GENERATED and a hand-edited row silently drifts from the skill it describes.
#
# The fix is one definition, not two. ci.yml calls `verify.sh <step>` per step so GitHub still shows a
# named box per gate, and a developer calls `verify.sh` with no argument to run every step this machine
# can run. Writing the commands in both places is the anti-pattern the kit flags elsewhere: two copies
# of one rule drift, and the copy that drifts is always the one nobody runs.
#
#   bash packaging/verify.sh              # every step (cross steps included), stop at the first failure
#   bash packaging/verify.sh syntax       # one step by name
#   bash packaging/verify.sh --list       # the step names, in order
#
# Exit 0 only if every step attempted PASSED. A step whose tool is absent is reported SKIPPED and is
# NOT counted as a pass — the same rule the suites themselves follow, for the same reason: a check that
# did not run must never read like a check that succeeded.
#
# CSK_VERIFY_STRICT=1 turns a skip into a failure. CI sets it, because there a missing tool is a broken
# runner rather than an honest local limitation, and a gate that goes quiet on a broken runner is worse
# than no gate: it reports success for a check nobody performed.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

B=""; D=""; R=""; RD=""; GR=""; YE=""
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; D=$'\033[2m'; R=$'\033[0m'; RD=$'\033[31m'; GR=$'\033[32m'; YE=$'\033[33m'
fi

# The step list is the contract with ci.yml. Adding a gate here is what makes it runnable locally;
# adding it to ci.yml alone is what put this file here in the first place.
STEPS="syntax smoke routing catalogue manifests e2e studio parser i18n"

step_syntax(){
  bash -n start.sh || return 1
  bash -n adopt.sh || return 1
  local s
  for s in claude-starter/hooks/*.sh claude-starter/eval/*.sh packaging/*.sh packaging/studio-test/*.sh \
           claude-starter/studio/*.sh claude-starter/studio/server/hooks/*.sh; do
    [ -f "$s" ] || continue
    bash -n "$s" || return 1
  done
  echo "shell syntax ok"
}

step_smoke(){     bash claude-starter/eval/smoke-test.sh; }
step_routing(){   bash claude-starter/eval/routing-eval.sh; }
step_catalogue(){ bash packaging/build-readme-catalog.sh --check; }
step_e2e(){       bash packaging/e2e.sh; }

# The gate must reach the same verdict whichever parser decoded the payload. This is a real step rather than a
# smoke section because it needs a SECOND parser to compare against, and a machine with only one has measured
# nothing — the script answers 3 for that, which is this file's skip, so the rc passes straight through with no
# translation: 0 every case agreed, 1 a divergence, 3 nothing compared. Under CSK_VERIFY_STRICT, which CI sets,
# that skip turns red, and it should: on a runner a missing parser is a broken runner.
#
# It is wired without `CSK_CONFORMANCE_KNOWN_OPEN`, deliberately. That variable exists to let the file land
# while its three findings were still open; all three are closed, so setting it here would mean a gate that
# cannot report the next one. The variable stays in the script and is pinned there to fail if a row it excuses
# starts passing — a safety valve that cleans itself up, not a permanent dispensation.
step_parser(){    bash claude-starter/eval/parser-conformance.sh; }

# The bilingual installer's message tables, audited statically: patterns quoted (an unquoted one is a GLOB, and
# a lot of prose ends in `?`), no colour or raw ESC inside a message, no stray backslash or bare `%` in a string
# that printf takes as its FORMAT, matching `%s` counts across languages, no `''` (bash concatenates it and eats
# the apostrophe, so `.NET''e` prints `.NETe` — valid syntax, silently wrong output), and no stale pattern that
# no longer matches anything in its script.
#
# Its own step rather than folded into `syntax`, because it has its own verdict to report and hiding it inside a
# step whose name says something else is how a gate stops being read. It is pure bash + awk deliberately: a
# python one would SKIP on a stock Windows desktop, where the Store's python3 stub resolves and then fails — the
# platform where the installer matters most, and the exact shape of four incidents this repo has already paid
# for. Whether gawk (Git Bash, ubuntu) and BSD awk (macOS) agree on it is not measurable on one machine, which
# is why it runs on every platform CI covers.
step_i18n(){      bash packaging/i18n-audit.sh; }

# The panel IS part of the payload now; it keeps its own step because it is a
# NODE gate, not because it sits outside what ships. Node is the only thing it
# needs, and a machine without one must say SKIPPED rather than quietly pass —
# CI, which has node, turns that skip red.
#
# A missing directory is a FAILURE, not a skip. It was a skip while the panel
# was optional; now that every channel ships it, a botched move would show as a
# yellow "skipped, NOT a pass" that nobody reads as broken.
step_studio(){
  [ -d claude-starter/studio ] || { echo "claude-starter/studio is MISSING — the panel ships in the payload"; return 1; }
  command -v node >/dev/null 2>&1 || { echo "SKIP: node is not on PATH"; return 3; }
  node --version >/dev/null 2>&1 || { echo "SKIP: node is on PATH but does not run"; return 3; }
  node packaging/studio-test/selfcheck.mjs || return 1
  # The panel needs a runtime; ensure-node.sh is what finds or fetches one. Its own
  # cases run here because they need bash, and the branches worth testing are the ones
  # a machine WITH node can never reach on its own.
  bash packaging/studio-test/ensure-node-cases.sh || return 1
  # The plugin edition ships the panel too. It is NOT tested separately, and the entire argument for
  # not testing it is that it is a byte copy of the payload — so that has to be asserted rather than
  # assumed. The release-time sync gate catches drift only at release; this catches it on every run.
  [ -f plugin/studio/server/index.js ] || {
    echo "plugin/studio is MISSING — the plugin edition ships the panel; run packaging/build-plugin.sh"; return 1; }
  diff -r claude-starter/studio plugin/studio >/dev/null 2>&1 || {
    echo "plugin/studio has drifted from claude-starter/studio — run packaging/build-plugin.sh and commit the result"
    diff -rq claude-starter/studio plugin/studio | head -10; return 1; }
}

# The only step that needs a tool the repo does not carry. CI installs the CLI; a developer machine
# usually already has it, and a machine without it must say SKIPPED rather than quietly pass.
step_manifests(){
  command -v claude >/dev/null 2>&1 || { echo "SKIP: the claude CLI is not on PATH"; return 3; }
  claude plugin validate plugin --strict || return 1
  claude plugin validate .claude-plugin/marketplace.json --strict || return 1
}

case "${1:-}" in
  --list|-l) printf '%s\n' $STEPS; exit 0 ;;
  --help|-h) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

WANT="${1:-}"
if [ -n "$WANT" ]; then
  case " $STEPS " in *" $WANT "*) ;; *) echo "unknown step: $WANT (try --list)" >&2; exit 2 ;; esac
  STEPS="$WANT"
fi

FAILED=""; SKIPPED=""; PASSED=0
for s in $STEPS; do
  printf '%s\n' "${B}── $s ${R}${D}$(printf '%.0s─' $(seq 1 $((60 - ${#s}))))${R}"
  if "step_$s"; then
    PASSED=$((PASSED + 1)); printf '%s\n\n' "${GR}✅ $s${R}"
  else
    rc=$?
    if [ "$rc" = 3 ] && [ "${CSK_VERIFY_STRICT:-0}" != "1" ]; then
      SKIPPED="$SKIPPED $s"; printf '%s\n\n' "${YE}⏭  $s — skipped, NOT a pass${R}"
    elif [ "$rc" = 3 ]; then
      FAILED="$FAILED $s"; printf '%s\n\n' "${RD}❌ $s — skipped under CSK_VERIFY_STRICT, which means the runner is missing a tool it should have${R}"; break
    else FAILED="$FAILED $s"; printf '%s\n\n' "${RD}❌ $s (rc=$rc)${R}"; break
    fi
  fi
done

printf '%s\n' "${B}VERIFY:${R} $PASSED passed${SKIPPED:+ · skipped:$SKIPPED}${FAILED:+ · ${RD}FAILED:$FAILED${R}}"
[ -z "$FAILED" ] || exit 1
