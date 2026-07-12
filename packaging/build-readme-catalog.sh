#!/usr/bin/env bash
# Generates the skill catalogue that appears in README.md and README.tr.md. The README is a VIEW of the skills,
# never a hand-maintained copy — that is what let the count drift (27 vs 28) once. A table of 30 rows in two
# languages would drift 30x worse, so both are generated, never edited by hand.
#
# Two sources, one row set:
#   - README.md   (English) summaries come from each SKILL.md frontmatter's first description sentence.
#   - README.tr.md (Turkish) summaries come from packaging/skill-summaries.tr.tsv (build-time DATA — it is NOT
#     loaded into any session, so Turkish text does not spend the SKILL.md frontmatter byte budget).
# The skill NAME set is the directory listing for both, so the two tables always hold the same rows in the same
# order. --check FAILS if a skill has no Turkish line (drift gate): a new skill must ship its TR summary too.
#
# Each README carries a marked block:
#   <!-- SKILLS:START -->  ... generated table ...  <!-- SKILLS:END -->
# and this script rewrites what is between the markers.
#
# Usage:
#   bash packaging/build-readme-catalog.sh          # rewrite the block in both READMEs
#   bash packaging/build-readme-catalog.sh --check   # exit 1 if either README's block is stale (smoke-test gate)
set -euo pipefail
# Force byte semantics everywhere. macOS ships BWK awk (byte-based length/substr); Ubuntu CI ships gawk, which
# in a UTF-8 locale counts CHARACTERS — so a summary truncated near a multibyte char (`·`, `→`, `…`) would cut
# at a different point on the two, and the README generated on one would fail --check on the other. LC_ALL=C
# makes gawk byte-based too, so the output is identical on both. (This is why the first v1.1.6 release failed.)
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SKILLS="$ROOT/claude-starter/skills"
TRMAP="$HERE/skill-summaries.tr.tsv"       # Turkish summaries (build-time data; see file header)
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1
TAB="$(printf '\t')"

# --- Raw rows: `name<TAB>english-summary`, one per skill, from each SKILL.md frontmatter. ---
# The summary is the first indented sentence under `description:` (the Trigger-phrases line is never first).
raw_rows() {
  for d in "$SKILLS"/*/; do
    f="$d/SKILL.md"; [ -f "$f" ] || continue
    awk '
      /^---[ \t]*$/ { fm++; if (fm==2) exit; next }
      fm==1 {
        if ($0 ~ /^name:/)       { n=$0; sub(/^name:[ \t]*/,"",n) }
        if ($0 ~ /^description:/) { ind=1; next }
        if (ind) {
          if ($0 ~ /^[A-Za-z]/) { ind=0; next }          # a later top-level key ends the description
          line=$0; sub(/^[ \t]+/,"",line)
          if (line=="" || line ~ /^Trigger phrases:/) next
          desc = (desc=="" ? line : desc " " line)
        }
      }
      END {
        s=desc
        if (match(s, /\. /)) s=substr(s,1,RSTART)          # first sentence (keep the period)
        if (length(s)>140) { s=substr(s,1,138); sub(/[ ][^ ]*$/,"",s); s=s "…" }
        printf "%s\t%s\n", n, s
      }
    ' "$f"
  done
}
ROWS="$(raw_rows)"

# Turkish summary for one skill from the TSV; nonzero exit if the skill has no line (the drift signal).
tr_summary() { awk -F'\t' -v n="$1" '$0 !~ /^#/ && $1==n { print $2; found=1 } END { exit !found }' "$TRMAP"; }

# Drift gate: every skill directory must have a Turkish summary, or the TR table would silently lose a row.
missing="$(printf '%s\n' "$ROWS" | while IFS="$TAB" read -r name _; do
  [ -z "$name" ] && continue
  tr_summary "$name" >/dev/null 2>&1 || printf '%s ' "$name"
done)"
[ -n "$missing" ] && { echo "ERROR: no Turkish summary in $(basename "$TRMAP") for: $missing— add a line there." >&2; exit 3; }

# --- Build one language's table from the shared row set. $1 = en|tr ---
table() {
  local lang="$1"
  if [ "$lang" = tr ]; then printf '| Beceri | Ne yapar |\n|:--|:--|\n'
  else                      printf '| Skill | What it does |\n|:--|:--|\n'; fi
  printf '%s\n' "$ROWS" | while IFS="$TAB" read -r name en; do
    [ -z "$name" ] && continue
    sum="$en"
    [ "$lang" = tr ] && sum="$(tr_summary "$name")"
    sum="${sum//|/\\|}"
    printf '| `%s` | %s |\n' "$name" "$sum"
  done | LC_ALL=C sort -t'`' -k2   # stable, name-sorted order
}

TABLE_EN="$(table en)"
TABLE_TR="$(table tr)"

# --- Write or check the block between the markers in one file. ---
apply() {  # $1 = README path, $2 = the table for that file's language
  local file="$1" tbl="$2" start="<!-- SKILLS:START -->" end="<!-- SKILLS:END -->"
  grep -qF "$start" "$file" && grep -qF "$end" "$file" || { echo "ERROR: markers missing in $(basename "$file")" >&2; return 2; }
  local new; new="$(printf '%s\n\n%s\n\n%s' "$start" "$tbl" "$end")"
  local cur; cur="$(awk -v s="$start" -v e="$end" 'index($0,s){p=1} p{print} index($0,e){p=0}' "$file")"
  if [ "$CHECK" = 1 ]; then
    [ "$cur" = "$new" ] || { echo "STALE: $(basename "$file") skill catalogue is out of sync — run build-readme-catalog.sh" >&2; return 1; }
    return 0
  fi
  # Rewrite as: everything before the start marker + the fresh block + everything after the end marker.
  # (Building the block via string concat, not `awk -v`, since a multi-line -v value breaks BWK awk.)
  local before after
  # Strip the blank lines adjacent to the block on both sides (command substitution already trims `before`'s
  # trailing blanks; `awk 'NF{f=1} f'` trims `after`'s leading blanks) so the single blanks re-added by printf
  # below don't accumulate on every run — the rewrite must be idempotent.
  before="$(awk -v s="$start" 'index($0,s){exit} {print}' "$file")"
  after="$(awk -v e="$end" 'f{print} index($0,e){f=1}' "$file" | awk 'NF{f=1} f')"
  # Blank lines around the block: GitHub only renders a markdown table inside <details> when a blank line
  # separates </summary> from the content (command substitution ate the one that was there).
  printf '%s\n\n%s\n\n%s\n' "$before" "$new" "$after" > "$file.tmp" && mv "$file.tmp" "$file"
}

rc=0
apply "$ROOT/README.md"    "$TABLE_EN" || rc=$?
apply "$ROOT/README.tr.md" "$TABLE_TR" || rc=$?
N="$(printf '%s' "$TABLE_EN" | grep -c '^| `')"
[ "$CHECK" = 1 ] && [ "$rc" = 0 ] && echo "skill catalogue in sync — EN + TR ($N skills)"
[ "$CHECK" = 0 ] && [ "$rc" = 0 ] && echo "skill catalogue written — EN → README.md, TR → README.tr.md ($N skills)"
exit $rc
