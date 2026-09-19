#!/usr/bin/env bash
# Find assertions whose PASS/FAIL never reaches the suite's counters.
#
# THE DEFECT THIS EXISTS FOR. `pass` and `fail` increment shell variables. A subshell gets a COPY of those
# variables, so an assertion inside `( … )` prints its green line and the parent's totals do not move. The
# rows look right, the summary is short by exactly the rows that ran there, and — this is the part that
# matters — a `fail` in such a block is INVISIBLE: the suite stays green while a gate is broken. It was found
# in this repo by watching the total go up by one where six rows had printed, not by reading the output.
#
# Bash creates that copy in three shapes, and all three are checked:
#   ( … )                           an explicit group
#   cmd | while …; do … done        the last stage of a pipeline is a child
#   cmd | { … }                     same
#
# NOT flagged, because the counters survive: a `for`/`while` loop that is not fed by a pipe, an `if`, a `case`
# branch, `$( … )` used for a value, `<( … )` process substitution, and `( … ) && pass` where the assertion
# sits outside the group. Every one of those produced a false positive in an earlier version of this file and
# each is now pinned by --selftest. A scanner that cries wolf is worse than no scanner: the first run of this
# one reported six assertions in smoke-test.sh that were plain `for`-loop rows, and the only reason that did
# not become a wasted hour was that the calibration cases were written before the real scan.
#
# Pure bash + awk. No python: on a stock Windows desktop the Store `python3` stub resolves and exits 49, so a
# python checker skips on the platform this suite most needs it — and a skip reads as a pass.
#
# Usage: bash packaging/subshell-audit.sh [--selftest] [file ...]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

AWKP='
BEGIN { Q1 = sprintf("%c",34); Q2 = sprintf("%c",39)
        WORDS["pass"]=1; WORDS["fail"]=1; WORDS["skip"]=1 }
function isword(c){ return (c ~ /[A-Za-z0-9_]/) }
# A command position: start of line, or after ; & | ( { or one of do/then/else. Used for BOTH the assertion
# word and the opening paren, which is what keeps `name()`, a case pattern`s `)`, `$(`, `<(` and an arithmetic
# `((` from drifting the depth. The drift is not theoretical: it is what produced this file`s false positives.
function cmdpos(s, p,   c) {
  while (p >= 1) { c = substr(s,p,1); if (c == " " || c == "\t") { p--; continue } break }
  if (p < 1) return 1
  c = substr(s,p,1)
  if (c == ";" || c == "&" || c == "|" || c == "(" || c == "{") return 1
  if (substr(s, p-1, 2) == "do"   && !isword(substr(s,p-2,1))) return 1
  if (substr(s, p-3, 4) == "then" && !isword(substr(s,p-4,1))) return 1
  if (substr(s, p-3, 4) == "else" && !isword(substr(s,p-4,1))) return 1
  return 0
}
{
  raw = $0; line = $0
  # A heredoc body is DATA, not code. Without this the file`s own --selftest fixtures are reported as
  # findings in itself, which is how this check first ran: 8 hits, 7 of them its own calibration text.
  if (hd != "") { if (raw ~ ("^[ \t]*" hd "[ \t]*$")) hd = ""; next }
  if (match(raw, /<<-?[ \t]*[\047\042]?[A-Za-z_][A-Za-z0-9_]*[\047\042]?/)) {
    t = substr(raw, RSTART, RLENGTH); gsub(/^<<-?[ \t]*|[\047\042]/, "", t); hd = t; next
  }
  gsub(/\\./, "..", line)                      # an escaped char cannot open anything
  n = length(line); i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    if (c == Q1 || c == Q2) { q = c; i++; while (i <= n && substr(line,i,1) != q) i++; i++; continue }
    if (c == "#") break
    if (c == "(" && cmdpos(line, i-1) && substr(line,i+1,1) != "(") { depth++; i++; continue }
    if (c == ")") { if (depth > 0) depth--; i++; continue }
    for (w in WORDS) {
      if (substr(line, i, length(w)) == w && !isword(substr(line, i+length(w), 1)) && cmdpos(line, i-1)) {
        # A deliberate exception is written down, not remembered: `# subshell-audit: intentional` on the line
        # or the one above it. The one real case in this repo probes `skip` itself and must run in a child so
        # the live counters are not disturbed — that is correct, and marking it keeps this usable as a gate.
        if (raw ~ /subshell-audit: intentional/ || prev ~ /subshell-audit: intentional/) { }
        else if (depth > 0)  printf "HIT %s:%d [subshell]   %s\n", FILENAME, NR, substr(raw, 1, 84)
        else if (pipe)       printf "HIT %s:%d [pipe-child] %s\n", FILENAME, NR, substr(raw, 1, 84)
      }
    }
    if (c == "|" && substr(line, i+1, 1) != "|" && substr(line, i-1, 1) != "|") {
      rest = substr(line, i+1)
      if (rest ~ /^[ \t]*(while|until|\{)/) { pipe = 1; opened = 1 }
    }
    i++
  }
  # The child ends where its block ends. A one-line `cmd | { … ; }` closes on the SAME line, so checking only
  # for a line that STARTS with `}` left the flag set and painted every following assertion as a pipe child.
  if (pipe && (line ~ /(^|[ \t;])done([ \t;]|$)/ || line ~ /\}[ \t]*$/ || (opened && line ~ /\}/))) pipe = 0
  opened = 0
  prev = raw
}
END { printf "SCANNED %d\n", NR }
'

scan() { LC_ALL=C awk "$AWKP" "$1" 2>/dev/null; }

if [ "${1:-}" = "--selftest" ]; then
  # Calibration, and it runs BEFORE any real file is believed. Four must-flag shapes and six must-not, because
  # a scanner proven only on what it should catch is a scanner that might catch everything.
  t="$(mktemp -d)"
  cat > "$t/bad.sh" <<'EOS'
( pass "one-line subshell" )
(
  cd /tmp
  fail "multi-line subshell"
)
echo x | while read y; do fail "pipeline child"; done
echo x | { skip tool "pipeline brace child"; }
EOS
  cat > "$t/good.sh" <<'EOS'
pass "plain"
( something ) && pass "assertion outside the group"
for r in a b; do pass "for loop"; done
case x in *foo*) pass "case branch" ;; esac
[ -f x ] || { fail "brace group after ||, not a pipe"; }
comm -23 <(printf a) <(printf b) >/dev/null; pass "after process substitution"
EOS
  nb="$(scan "$t/bad.sh"  | grep -c '^HIT ')"
  ng="$(scan "$t/good.sh" | grep -c '^HIT ')"
  rm -rf "$t"
  printf 'selftest: must-flag %s/4 · must-not-flag %s (want 0)\n' "$nb" "$ng"
  [ "$nb" -eq 4 ] && [ "$ng" -eq 0 ] || { echo "SELFTEST FAILED — the scanner cannot be trusted on real files"; exit 1; }
  echo "selftest OK"
  exit 0
fi

FILES=("$@")
if [ ${#FILES[@]} -eq 0 ]; then
  while IFS= read -r f; do FILES+=("$f"); done < <(
    { ls claude-starter/eval/*.sh packaging/*.sh evals/run.sh 2>/dev/null; } | LC_ALL=C sort -u )
fi

hits=0; files=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  out="$(scan "$f")"
  # If the trace is empty the measurement is broken, not the product: awk must report how many lines it read.
  if ! printf '%s\n' "$out" | grep -q '^SCANNED '; then
    printf 'FAIL %s [the audit itself could not run — no SCANNED line from awk]\n' "$f"
    hits=$((hits+1)); continue
  fi
  n="$(printf '%s\n' "$out" | grep -c '^HIT ')"
  printf '%s\n' "$out" | sed -n 's/^HIT /  /p'
  hits=$((hits+n)); files=$((files+1))
done

printf '\nSUBSHELL-AUDIT: %d files, %d assertion(s) in a child shell\n' "$files" "$hits"
[ "$hits" -eq 0 ]
