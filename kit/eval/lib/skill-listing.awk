# The size of the skill listing Claude Code puts into context, counted the way Claude Code counts it — the one
# method doctor.sh and smoke-test.sh share, so there is one number and not two.
#
#   LC_ALL=C awk -f skill-listing.awk .claude/skills/*/SKILL.md          ->  "<chars> <skills> <unmeasured>"
#   LC_ALL=C awk -v per=1 -f skill-listing.awk …                         ->  one "<name>\t<chars>" row per skill, then the line above
#
# Measured against Claude Code's own counter (the "Skill listing over budget: N skills, C chars" debug warning, read
# with an isolated config and bundled skills off, so only these files are listed):
#   - a skill costs  len(name) + len(description) + 4;  skills are joined by one more character each
#       fixtures: name "aa" + "bbb" -> 9 · two skills (aa/bbb, cc/dddd) -> 20 · "aa" + 40 chars -> 46
#   - a block description (`description: |`) counts its lines with nothing between them: the line breaks cost 0
#       46 shipped skills one by one: every multi-line description read (lines - 1) under "joined by a space"
#   - a skill with `disable-model-invocation: true` is not listed at all
#   - characters, not bytes: an em dash is one (UTF-8 continuation bytes are not counted)
#   the 46 skills a fresh install lists: 9063 — the same figure Claude Code printed for them together.
# `when_to_use` and a folded (`>`) description were not measured; they are reported as "unmeasured" so a caller can
# refuse to trust the total rather than guess.
function chars(s,   t) { t = s; gsub(/[\200-\277]/, "", t); return length(t) }
function flush() {
  if (open && !dmi && name != "") {
    n++; c = chars(name) + dlen + 4; total += c
    if (per) printf "%s\t%d\n", name, c
  }
  open = 0
}
FNR == 1 { flush(); open = 1; fm = 0; name = ""; dlen = 0; blk = 0; dmi = 0 }
fm >= 2 { next }
/^---[[:space:]]*$/ { fm++; blk = 0; next }
fm != 1 { next }
blk && /^[[:space:]]+[^[:space:]]/ { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l); dlen += chars(l); next }
blk && /^[[:space:]]*$/ { next }
{ blk = 0 }
/^name:/ { v = $0; sub(/^name:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); name = v; next }
/^description:[[:space:]]*\|[-+]?[[:space:]]*$/ { blk = 1; next }
/^description:[[:space:]]*>/ { blk = 1; unmeasured++; next }
/^description:/ {
  v = $0; sub(/^description:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
  if (v ~ /^".*"$/ || v ~ /^'.*'$/) v = substr(v, 2, length(v) - 2)
  dlen = chars(v); next
}
/^disable-model-invocation:[[:space:]]*true[[:space:]]*$/ { dmi = 1; next }
/^when_to_use:/ { unmeasured++; next }
END { flush(); printf "%d %d %d\n", total + (n > 0 ? n - 1 : 0), n, unmeasured + 0 }
