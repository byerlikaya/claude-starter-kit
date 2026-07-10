#!/usr/bin/env bash
# Generates the skill catalogue that appears in README.md and README.tr.md, from the SINGLE source of truth:
# each skill's own SKILL.md frontmatter. The README is a VIEW of the skills, never a hand-maintained copy —
# that is what let the count drift (27 vs 28) once. A table of 28 rows in two languages would drift 28x worse.
#
# Each README carries a marked block:
#   <!-- SKILLS:START -->  ... generated table ...  <!-- SKILLS:END -->
# and this script rewrites what is between the markers.
#
# Usage:
#   bash packaging/build-readme-catalog.sh          # rewrite the block in both READMEs
#   bash packaging/build-readme-catalog.sh --check   # exit 1 if either README's block is stale (smoke-test gate)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SKILLS="$ROOT/claude-starter/skills"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

# --- Build the table from every SKILL.md frontmatter (name + the first description line as the summary). ---
# The summary is the first indented line under `description:` (the Trigger-phrases line is never first).
table() {
  printf '| Skill | What it does |\n|:--|:--|\n'
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
        gsub(/\|/,"\\|",s)
        printf "| `%s` | %s |\n", n, s
      }
    ' "$f"
  done | LC_ALL=C sort -t'`' -k2   # stable, name-sorted order
}

TABLE="$(table)"

# --- Write or check the block between the markers in one file. ---
apply() {  # $1 = README path
  local file="$1" start="<!-- SKILLS:START -->" end="<!-- SKILLS:END -->"
  grep -qF "$start" "$file" && grep -qF "$end" "$file" || { echo "ERROR: markers missing in $(basename "$file")" >&2; return 2; }
  local new; new="$(printf '%s\n\n%s\n\n%s' "$start" "$TABLE" "$end")"
  local cur; cur="$(awk -v s="$start" -v e="$end" 'index($0,s){p=1} p{print} index($0,e){p=0}' "$file")"
  if [ "$CHECK" = 1 ]; then
    [ "$cur" = "$new" ] || { echo "STALE: $(basename "$file") skill catalogue is out of sync — run build-readme-catalog.sh" >&2; return 1; }
    return 0
  fi
  # Rewrite as: everything before the start marker + the fresh block + everything after the end marker.
  # (Building the block via string concat, not `awk -v`, since a multi-line -v value breaks BWK awk.)
  local before after
  before="$(awk -v s="$start" 'index($0,s){exit} {print}' "$file")"
  after="$(awk -v e="$end" 'f{print} index($0,e){f=1}' "$file")"
  # Blank lines around the block: GitHub only renders a markdown table inside <details> when a blank line
  # separates </summary> from the content (command substitution ate the one that was there).
  printf '%s\n\n%s\n\n%s\n' "$before" "$new" "$after" > "$file.tmp" && mv "$file.tmp" "$file"
}

rc=0
for r in "$ROOT/README.md" "$ROOT/README.tr.md"; do
  apply "$r" || rc=$?
done
[ "$CHECK" = 1 ] && [ "$rc" = 0 ] && echo "skill catalogue in sync ($(printf '%s' "$TABLE" | grep -c '^| `') skills)"
[ "$CHECK" = 0 ] && [ "$rc" = 0 ] && echo "skill catalogue written to both READMEs ($(printf '%s' "$TABLE" | grep -c '^| `') skills)"
exit $rc
