#!/usr/bin/env bash
# Audit the installer message tables. Pure bash + awk on purpose, no python and no jq.
#
# WHY NO PYTHON. A stock Windows desktop carries a Microsoft Store `python3` stub that satisfies
# `command -v`, prints "Python was not found" and exits 49. A checker written in python therefore SKIPS on
# the one platform where these scripts are hardest to get right — and a skipped check reads as a pass. The
# same reasoning already keeps the hooks on a pure-bash tier.
#
# The tables use THE ENGLISH STRING AS THE KEY (see the long note in start.sh). Six properties have to hold,
# and every one of them is a mistake that leaves valid syntax and a running script behind:
#
#   1  pattern quoted      In `case`, an unquoted pattern is a GLOB. `Install with these settings?)` makes
#                          `?` match any character, so a message matches its own near-twin. Silent and
#                          selective: a `*` matches far too much, a `[...]` can fail to match itself.
#   2  no colour/ANSI      Colour belongs in the h1/sub/row helpers, which receive an already-translated
#                          string. A translator copying an escape sequence is a translator breaking it.
#   3  no backslash        The message is the printf FORMAT, so a stray `\` in it is an escape, not text.
#   4  %s counts match     A translation with fewer %s eats an argument; with more, it prints garbage.
#   5  literal % is %%     "%100 yerel" is a format specifier. Same failure, different spelling.
#   6  pattern not stale   Editing an English string silently drops its translation and the line reverts to
#                          English. Catchable: every pattern must still occur in the file it belongs to.
#   7  no '' in a value    In bash, '' inside a single-quoted string is CONCATENATION, not an escaped
#                          apostrophe: `.NET''e` prints `.NETe`. Turkish is full of apostrophes, so this one
#                          has a high hit rate — it was written nine times across two files before it was
#                          noticed, with valid syntax and quietly wrong output every time.
#
# Usage: bash packaging/i18n-audit.sh [file ...]   (default: the three files that carry a table)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SQ=$'\047'   # a literal apostrophe, passed into awk rather than quoted inside it
FILES=("$@")
[ ${#FILES[@]} -gt 0 ] || FILES=(start.sh adopt.sh kit/eval/preflight.sh kit/eval/lib/star.sh)

fails=0
total=0
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then printf 'MISSING  %s\n' "$f"; fails=$((fails+1)); continue; fi
  # The block is delimited so a `case` elsewhere in the script is never mistaken for a message table.
  if ! grep -q 'CSK-I18N' "$f"; then printf 'NO TABLE %s\n' "$f"; fails=$((fails+1)); continue; fi

  # One awk pass per file: it reads the whole file so it can answer the staleness question (property 6)
  # without a second read, and prints one FAIL line per violation plus a COUNT line at the end.
  out="$(LC_ALL=C awk -v FNAME="$f" -v Q="$SQ" '
    { all[NR] = $0 }
    /---- CSK-I18N/      { inblk = 1 }
    /---- \/CSK-I18N/    { inblk = 0 }
    inblk && /\) *s=/ && !/case / {
      line = $0
      # pattern = text before the first `)` that closes it; value = between `s=` and the trailing `;;`
      p = line; sub(/\) *s=.*$/, "", p); sub(/^[ \t]+/, "", p)
      v = line; sub(/^.*\) *s=/, "", v); sub(/[ \t]*;;[ \t]*$/, "", v)
      rows[++n] = p SUBSEP v SUBSEP NR
    }
    END {
      for (i = 1; i <= n; i++) {
        split(rows[i], a, SUBSEP); p = a[1]; v = a[2]; ln = a[3]

        q = substr(p, 1, 1)
        if (q != "\"" && q != Q)
          printf "FAIL %s:%s [1 unquoted pattern] %s\n", FNAME, ln, substr(p, 1, 60)
        P = (q == "\"" || q == Q) ? substr(p, 2, length(p) - 2) : p
        qv = substr(v, 1, 1)
        V = (qv == "\"" || qv == Q) ? substr(v, 2, length(v) - 2) : v

        if (index(P "" V, "\033") || index(P "" V, "\\033") || index(P "" V, "\\e") \
            || index(P "" V, "$B") || index(P "" V, "${B}") || index(P "" V, "$R") || index(P "" V, "${R}"))
          printf "FAIL %s:%s [2 colour or escape in a message] %s\n", FNAME, ln, substr(P, 1, 50)

        if (index(P, "\\") || index(V, "\\"))
          printf "FAIL %s:%s [3 backslash in a message] %s\n", FNAME, ln, substr(P, 1, 50)

        # %s parity and stray %: remove %% first, then count %s, then look for any % that is left over
        pp = P; gsub(/%%/, "", pp); vv = V; gsub(/%%/, "", vv)
        np = gsub(/%s/, "", pp); nv = gsub(/%s/, "", vv)
        if (np != nv)
          printf "FAIL %s:%s [4 %%s count en=%d tr=%d] %s\n", FNAME, ln, np, nv, substr(P, 1, 50)
        if (index(pp, "%")) printf "FAIL %s:%s [5 unescaped %% in the key] %s\n", FNAME, ln, substr(P, 1, 50)
        if (index(vv, "%")) printf "FAIL %s:%s [5 unescaped %% in the value] %s\n", FNAME, ln, substr(V, 1, 50)

        # Property 7 only applies to a single-quoted VALUE — inside double quotes '' is two real characters.
        if (qv == Q && index(V, Q Q))
          printf "FAIL %s:%s [7 doubled apostrophe in a single-quoted value swallows it] %s\n", FNAME, ln, substr(V, 1, 50)

        # Property 6: the pattern has to occur somewhere in the file OUTSIDE the table block.
        seen = 0
        for (k = 1; k <= NR; k++) {
          if (all[k] ~ /---- CSK-I18N/) { skip = 1 }
          if (all[k] ~ /---- \/CSK-I18N/) { skip = 0; continue }
          if (!skip && index(all[k], P)) { seen = 1; break }
        }
        if (!seen)
          printf "FAIL %s:%s [6 stale pattern, no longer in the file] %s\n", FNAME, ln, substr(P, 1, 60)
      }
      printf "COUNT %d\n", n
    }
  ' "$f")"

  awk_rc=$?
  c="$(printf '%s\n' "$out" | sed -n 's/^COUNT //p')"
  # If the trace is empty the measurement is broken, not the product. awk failing and this script printing
  # "OK" is exactly the fail-open the kit exists to stop, and it happened on the first run of this file.
  if [ "$awk_rc" -ne 0 ] || [ -z "$c" ]; then
    printf 'FAIL %s [0 the audit itself could not run: awk rc=%s, no COUNT line]\n' "$f" "$awk_rc"
    fails=$((fails+1)); continue
  fi
  if [ "$c" -eq 0 ]; then
    printf 'FAIL %s [0 table found but zero entries parsed — the extractor is broken]\n' "$f"
    fails=$((fails+1)); continue
  fi
  bad="$(printf '%s\n' "$out" | grep -c '^FAIL ' || true)"
  printf '%s\n' "$out" | grep '^FAIL ' || true
  printf '  %-34s %3s entries, %s\n' "$f" "${c:-0}" "$([ "$bad" -eq 0 ] && echo OK || echo "$bad FAILED")"
  total=$((total + ${c:-0})); fails=$((fails + bad))
done

printf '\nI18N-AUDIT: %d entries, %d failed\n' "$total" "$fails"
[ "$fails" -eq 0 ]
